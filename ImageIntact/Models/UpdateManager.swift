import Foundation
import SwiftUI

// MARK: - Update Check Result States
enum UpdateCheckResult {
    case checking
    case upToDate
    case updateAvailable(AppUpdate)
    case error(Error)
    case downloading(progress: Double)
}

/// Manages application updates using a protocol-based provider system
@Observable
class UpdateManager {
    // MARK: - Published Properties
    var isCheckingForUpdates = false
    var availableUpdate: AppUpdate?
    var downloadProgress: Double = 0.0
    var isDownloadingUpdate = false
    var lastError: UpdateError?
    var showUpdateSheet = false
    var updateCheckResult: UpdateCheckResult = .checking
    
    // MARK: - Test Mode Properties
    static var testMode = false
    static var mockVersion: String?
    var isTestMode: Bool { UpdateManager.testMode }
    
    private var updateProvider: UpdateProvider
    private var settings = UpdateSettings.load()
    private var downloadTask: Task<Void, Never>?
    
    /// Get current app version from Info.plist (or mock version in test mode)
    var currentVersion: String {
        // Check for test mode mock version
        if UpdateManager.testMode, let mockVersion = UpdateManager.mockVersion {
            print("🧪 TEST MODE: Reporting mock version \(mockVersion)")
            return mockVersion
        }
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    
    init(provider: UpdateProvider? = nil) {
        // Default to GitHub provider, but allow injection for testing
        self.updateProvider = provider ?? GitHubUpdateProvider()
        print("UpdateManager initialized with \(updateProvider.providerName)")
        
        // Check for test mode from launch arguments
        checkForTestMode()
    }
    
    /// Check launch arguments and environment for test mode
    private func checkForTestMode() {
        let arguments = ProcessInfo.processInfo.arguments
        let environment = ProcessInfo.processInfo.environment
        
        // Check for test mode flag
        if arguments.contains("--test-update") || environment["IMAGEINTACT_TEST_UPDATE"] == "1" {
            UpdateManager.testMode = true
            print("🧪 TEST MODE ACTIVATED")
            
            // Check for mock version
            if let index = arguments.firstIndex(of: "--mock-version"),
               index + 1 < arguments.count {
                UpdateManager.mockVersion = arguments[index + 1]
                print("🧪 Mock version set to: \(arguments[index + 1])")
            } else if let mockVersion = environment["IMAGEINTACT_MOCK_VERSION"] {
                UpdateManager.mockVersion = mockVersion
                print("🧪 Mock version set to: \(mockVersion)")
            } else {
                // Default mock version if test mode but no version specified
                UpdateManager.mockVersion = "1.0.0"
                print("🧪 Using default mock version: 1.0.0")
            }
        }
    }
    
    // MARK: - Public Methods
    
    /// Check for updates (called on app launch if auto-check enabled)
    func checkForUpdates() {
        guard settings.shouldCheckForUpdates() else {
            print("Skipping automatic update check")
            return
        }
        
        Task {
            await performUpdateCheck()
        }
    }
    
    /// Manually check for updates (via menu command)
    @MainActor
    func performUpdateCheck(isManual: Bool = false) async {
        guard !isCheckingForUpdates else { return }
        
        if isManual {
            showUpdateSheet = true
            updateCheckResult = .checking
        }
        
        isCheckingForUpdates = true
        lastError = nil
        
        defer {
            isCheckingForUpdates = false
            settings.markUpdateCheck()
        }
        
        // Add a small delay so the user sees the checking state
        if isManual {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }
        
        do {
            print("Checking for updates via \(updateProvider.providerName)...")
            let update = try await updateProvider.checkForUpdates(currentVersion: currentVersion)
            
            if let update = update {
                // Check if this version is skipped
                if settings.isVersionSkipped(update.version) {
                    print("Version \(update.version) is skipped by user preference")
                    if isManual {
                        updateCheckResult = .upToDate
                    }
                    return
                }
                
                // Check OS compatibility
                if let minOS = update.minimumOSVersion {
                    if !isOSCompatible(minimumVersion: minOS) {
                        print("Update requires macOS \(minOS) or later")
                        lastError = .unsupportedPlatform
                        if isManual {
                            updateCheckResult = .error(UpdateError.unsupportedPlatform)
                        }
                        return
                    }
                }
                
                print("Update available: v\(update.version)")
                availableUpdate = update
                updateCheckResult = .updateAvailable(update)
                
                // Always show the update sheet for consistency
                if !isManual {
                    // For auto-check, show the sheet with the update
                    showUpdateSheet = true
                }
            } else {
                print("No updates available (current: v\(currentVersion))")
                
                if isManual {
                    updateCheckResult = .upToDate
                }
            }
        } catch {
            print("Update check failed: \(error)")
            lastError = error as? UpdateError ?? .networkError(error)
            
            if isManual {
                updateCheckResult = .error(error)
            }
        }
    }
    
    /// Download the available update
    @MainActor
    func downloadUpdate(_ update: AppUpdate) async {
        guard !isDownloadingUpdate else { return }
        
        isDownloadingUpdate = true
        downloadProgress = 0.0
        
        // Ensure the update sheet is visible to show progress
        await MainActor.run { [weak self] in
            self?.showUpdateSheet = true
            self?.updateCheckResult = .downloading(progress: 0.0)
        }
        
        downloadTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                print("🔄 Starting download of update v\(update.version)...")
                print("📦 Download URL: \(update.downloadURL)")
                
                let localURL = try await self.updateProvider.downloadUpdate(update) { progress in
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        self.downloadProgress = progress
                        self.updateCheckResult = .downloading(progress: progress)
                        print("📊 Download progress: \(Int(progress * 100))%")
                    }
                }
                
                print("✅ Update downloaded successfully to: \(localURL)")
                
                // Mount and open the DMG
                await self.mountAndOpenDMG(at: localURL)
                
                // Dismiss sheets
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    self.showUpdateSheet = false
                    self.isDownloadingUpdate = false
                    
                    // Show completion message
                    self.showDownloadCompleteAlert(at: localURL)
                }
                
            } catch {
                print("Download failed: \(error)")
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    self.lastError = error as? UpdateError ?? .downloadFailed(error)
                    self.isDownloadingUpdate = false
                    self.updateCheckResult = .error(error)
                }
            }
        }
    }
    
    /// Cancel ongoing download
    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        isDownloadingUpdate = false
        downloadProgress = 0.0
    }
    
    /// Skip a version
    func skipVersion(_ version: String) {
        var updatedSettings = settings
        updatedSettings.skipVersion(version)
        settings = updatedSettings
        showUpdateSheet = false
        availableUpdate = nil
    }
    
    // MARK: - DMG Handling
    
    /// Mount a DMG and open it in Finder
    private func mountAndOpenDMG(at url: URL) async {
        print("💿 Mounting DMG: \(url.lastPathComponent)")
        
        do {
            // Use hdiutil to mount the DMG
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            process.arguments = ["attach", url.path, "-autoopen"]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                print("✅ DMG mounted successfully")
                
                // Read output to find mount point
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    print("Mount output: \(output)")
                    
                    // Extract mount point (usually /Volumes/ImageIntact-X.X.X)
                    let lines = output.components(separatedBy: .newlines)
                    for line in lines {
                        if line.contains("/Volumes/") {
                            let components = line.components(separatedBy: .whitespaces)
                            if let volumePath = components.last {
                                print("📂 Opening mounted volume: \(volumePath)")
                                // Open the mounted volume in Finder
                                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: volumePath)
                            }
                        }
                    }
                }
            } else {
                print("❌ Failed to mount DMG (exit code: \(process.terminationStatus))")
                // Fallback: just open the DMG file
                NSWorkspace.shared.open(url)
            }
        } catch {
            print("❌ Error mounting DMG: \(error)")
            // Fallback: just open the DMG file
            NSWorkspace.shared.open(url)
        }
    }
    
    // MARK: - Settings Management
    
    /// Enable or disable automatic update checks
    func setAutomaticChecking(_ enabled: Bool) {
        settings.automaticallyCheckForUpdates = enabled
        settings.save()
    }
    
    /// Set update check interval
    func setCheckInterval(_ interval: TimeInterval) {
        settings.checkInterval = interval
        settings.save()
    }
    
    // MARK: - Helper Methods
    
    /// Check if current OS is compatible with minimum version
    private func isOSCompatible(minimumVersion: String) -> Bool {
        let currentOS = ProcessInfo.processInfo.operatingSystemVersion
        let currentOSString = "\(currentOS.majorVersion).\(currentOS.minorVersion)"
        
        return currentOSString.compare(minimumVersion, options: .numeric) != .orderedAscending
    }
    
    /// Show alert when no updates are available
    private func showNoUpdatesAlert() {
        let alert = NSAlert()
        alert.messageText = "You're up to date!"
        alert.informativeText = "ImageIntact \(currentVersion) is the latest version available."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    /// Show error alert
    private func showErrorAlert() {
        guard let error = lastError else { return }
        
        let alert = NSAlert()
        alert.messageText = "Update Check Failed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    /// Show download complete alert
    private func showDownloadCompleteAlert(at url: URL) {
        let alert = NSAlert()
        alert.messageText = "Download Complete"
        alert.informativeText = "The update has been downloaded to:\n\n\(url.path)\n\nThe DMG will now open. Please drag ImageIntact to your Applications folder to complete the update."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

// MARK: - Mock Provider for Testing

#if DEBUG
/// Mock provider for testing update UI without hitting GitHub
class MockUpdateProvider: UpdateProvider {
    var providerName: String { "Mock Provider" }
    
    func checkForUpdates(currentVersion: String) async throws -> AppUpdate? {
        // Simulate network delay
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        // Return a fake update
        guard let testURL = URL(string: "https://example.com/test.dmg") else {
            return nil
        }
        return AppUpdate(
            version: "99.9.9",
            releaseNotes: "This is a test update for development purposes.\n\n• Feature 1\n• Feature 2\n• Bug fixes",
            downloadURL: testURL,
            publishedDate: Date(),
            minimumOSVersion: "14.0",
            fileSize: 10_000_000
        )
    }
    
    func downloadUpdate(_ update: AppUpdate, progress: @escaping (Double) -> Void) async throws -> URL {
        // Simulate download progress
        for i in 0...10 {
            try await Task.sleep(nanoseconds: 100_000_000)
            progress(Double(i) / 10.0)
        }
        
        // Return a fake path
        return FileManager.default.temporaryDirectory.appendingPathComponent("test.dmg")
    }
}
#endif