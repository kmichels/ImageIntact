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
    var showUpdateAlert = false
    var downloadProgress: Double = 0.0
    var isDownloadingUpdate = false
    var lastError: UpdateError?
    var showUpdateSheet = false
    var updateCheckResult: UpdateCheckResult = .checking
    
    private var updateProvider: UpdateProvider
    private var settings = UpdateSettings.load()
    private var downloadTask: Task<Void, Never>?
    
    /// Get current app version from Info.plist
    var currentVersion: String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    
    init(provider: UpdateProvider? = nil) {
        // Default to GitHub provider, but allow injection for testing
        self.updateProvider = provider ?? GitHubUpdateProvider()
        print("UpdateManager initialized with \(updateProvider.providerName)")
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
                if isManual {
                    updateCheckResult = .updateAvailable(update)
                } else {
                    // For automatic checks, use the old alert system
                    showUpdateAlert = true
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
        updateCheckResult = .downloading(progress: 0.0)
        
        downloadTask = Task {
            do {
                print("Downloading update v\(update.version)...")
                let localURL = try await updateProvider.downloadUpdate(update) { progress in
                    Task { @MainActor in
                        self.downloadProgress = progress
                        self.updateCheckResult = .downloading(progress: progress)
                    }
                }
                
                print("Update downloaded to: \(localURL)")
                
                // Open the DMG
                NSWorkspace.shared.open(localURL)
                
                // Dismiss sheets
                showUpdateAlert = false
                showUpdateSheet = false
                isDownloadingUpdate = false
                
                // Show completion message
                showDownloadCompleteAlert(at: localURL)
                
            } catch {
                print("Download failed: \(error)")
                lastError = error as? UpdateError ?? .downloadFailed(error)
                isDownloadingUpdate = false
                updateCheckResult = .error(error)
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
        showUpdateAlert = false
        availableUpdate = nil
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
        return AppUpdate(
            version: "99.9.9",
            releaseNotes: "This is a test update for development purposes.\n\n• Feature 1\n• Feature 2\n• Bug fixes",
            downloadURL: URL(string: "https://example.com/test.dmg")!,
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