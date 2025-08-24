import SwiftUI
import Darwin
import CryptoKit
import AppKit

// MARK: - Backup Phase Enum
enum BackupPhase: Int, Comparable {
    case idle = 0
    case analyzingSource = 1
    case buildingManifest = 2
    case copyingFiles = 3
    case flushingToDisk = 4
    case verifyingDestinations = 5
    case complete = 6
    
    static func < (lhs: BackupPhase, rhs: BackupPhase) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Destination Item
struct DestinationItem: Identifiable {
    let id = UUID()
    var url: URL?
}

@Observable
@MainActor
class BackupManager {
    // MARK: - Test Mode
    static var isRunningTests: Bool {
        return ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
    
    // MARK: - Published Properties
    var sourceURL: URL? = nil
    var destinationURLs: [URL?] = []
    var destinationItems: [DestinationItem] = []
    var isProcessing = false
    var statusMessage = ""
    var failedFiles: [(file: String, destination: String, error: String)] = []
    var sessionID = UUID().uuidString
    var shouldCancel = false
    var debugLog: [String] = []
    var hasWrittenDebugLog = false
    var lastDebugLogPath: URL?
    
    // Progress tracking delegated to ProgressTracker
    let progressTracker = ProgressTracker()
    
    // Statistics tracking for completion report
    let statistics = BackupStatistics()
    
    // Expose progress properties for compatibility
    var totalFiles: Int { 
        get { progressTracker.totalFiles }
        set { progressTracker.totalFiles = newValue }
    }
    var processedFiles: Int { 
        get { progressTracker.processedFiles }
        set { progressTracker.processedFiles = newValue }
    }
    var currentFile: String { 
        get { progressTracker.currentFile }
        set { progressTracker.currentFile = newValue }
    }
    var currentFileIndex: Int { 
        get { progressTracker.currentFileIndex }
        set { progressTracker.currentFileIndex = newValue }
    }
    var currentFileName: String { 
        get { progressTracker.currentFileName }
        set { progressTracker.currentFileName = newValue }
    }
    var currentDestinationName: String { 
        get { progressTracker.currentDestinationName }
        set { progressTracker.currentDestinationName = newValue }
    }
    var copySpeed: Double { 
        get { progressTracker.copySpeed }
        set { progressTracker.copySpeed = newValue }
    }
    var totalBytesCopied: Int64 { 
        get { progressTracker.totalBytesCopied }
        set { progressTracker.totalBytesCopied = newValue }
    }
    var totalBytesToCopy: Int64 { 
        get { progressTracker.totalBytesToCopy }
        set { progressTracker.totalBytesToCopy = newValue }
    }
    var estimatedSecondsRemaining: TimeInterval? { progressTracker.estimatedSecondsRemaining }
    var destinationProgress: [String: Int] { progressTracker.destinationProgress }
    var destinationStates: [String: String] { progressTracker.destinationStates }
    var currentPhase: BackupPhase = .idle
    var phaseProgress: Double { progressTracker.phaseProgress }
    var overallProgress: Double { progressTracker.overallProgress }
    
    // Thread-safe progress state (still needed for actor isolation)
    let progressState = BackupProgressState()  // Made internal for extension access
    
    // Resource management
    let resourceManager = ResourceManager()  // Made internal for extension access
    
    // Other UI state
    var overallStatusText: String = "" // For showing mixed states like "1 copying, 1 verifying"
    
    // Destination drive analysis
    var destinationDriveInfo: [UUID: DriveAnalyzer.DriveInfo] = [:] // Use UUID instead of index to avoid mismatch
    
    // File type scanning
    var sourceFileTypes: [ImageFileType: Int] = [:]
    var isScanning = false
    var scanProgress: String = ""
    var sourceTotalBytes: Int64 { progressTracker.sourceTotalBytes }  // Total bytes from scan
    private let fileScanner = ImageFileScanner()
    
    // Backup options
    var excludeCacheFiles = true  // Default to excluding cache files
    var fileTypeFilter = FileTypeFilter()  // Default to no filtering (all files)
    
    // UI state for completion report
    var showCompletionReport = false
    
    // MARK: - Constants
    let sourceKey = "sourceBookmark"
    let destinationKeys = ["dest1Bookmark", "dest2Bookmark", "dest3Bookmark", "dest4Bookmark"]
    
    struct LogEntry {
        let timestamp: Date
        let sessionID: String
        let action: String
        let source: String
        let destination: String
        let checksum: String
        let algorithm: String
        let fileSize: Int64
        let reason: String
    }
    
    var logEntries: [LogEntry] = []
    private var currentOperation: DispatchWorkItem?
    var currentCoordinator: BackupCoordinator?  // Legacy - kept for compatibility
    var currentMonitorTask: Task<Void, Never>?  // Legacy - kept for compatibility
    var currentOrchestrator: BackupOrchestrator?  // New orchestrator for refactored backup
    
    // MARK: - Initialization
    init() {
        // Check if we should restore last session
        if PreferencesManager.shared.restoreLastSession {
            // Load destinations from saved bookmarks
            let loadedURLs = BackupManager.loadDestinationBookmarks()
            self.destinationURLs = loadedURLs
            self.destinationItems = loadedURLs.map { DestinationItem(url: $0) }
            
            // Analyze drives for loaded destinations
            for (index, url) in loadedURLs.enumerated() where url != nil {
                if let url = url, index < self.destinationItems.count {
                    let itemID = self.destinationItems[index].id
                    Task {
                        if let driveInfo = DriveAnalyzer.analyzeDrive(at: url) {
                            await MainActor.run { [weak self] in
                                self?.destinationDriveInfo[itemID] = driveInfo
                                logInfo("Drive analyzed on restore: \(driveInfo.deviceName)")
                            }
                        }
                    }
                }
            }
        } else {
            // Start with one empty destination slot
            self.destinationURLs = [nil]
            self.destinationItems = [DestinationItem(url: nil)]
        }
        
        // Initialize file type filter from preferences
        let filterPref = PreferencesManager.shared.defaultFileTypeFilter
        switch filterPref {
        case "photos":
            self.fileTypeFilter = .photosOnly
        case "raw":
            self.fileTypeFilter = .rawOnly
        case "videos":
            self.fileTypeFilter = .videosOnly
        default:
            self.fileTypeFilter = FileTypeFilter() // All files
        }
        
        // Load source URL and trigger scan if it exists (only if restoring last session)
        if PreferencesManager.shared.restoreLastSession,
           let savedSourceURL = BackupManager.loadBookmark(forKey: sourceKey) {
            // Test if we can actually access this bookmark
            let canAccess = savedSourceURL.startAccessingSecurityScopedResource()
            if canAccess {
                savedSourceURL.stopAccessingSecurityScopedResource()
                self.sourceURL = savedSourceURL
                logInfo("Loaded source: \(savedSourceURL.lastPathComponent)")
                // Trigger scan for the loaded source
                Task {
                    await scanSourceFolder(savedSourceURL)
                }
            } else {
                // Bookmark is invalid - clear it
                logWarning("Saved source bookmark is invalid, clearing...")
                UserDefaults.standard.removeObject(forKey: sourceKey)
                // Don't set sourceURL, leaving it nil will show folder picker
            }
        }
        
        // Analyze drives for loaded destinations and check accessibility
        for (index, item) in destinationItems.enumerated() {
            if let url = item.url {
                let itemID = item.id
                Task {
                    // First check if the destination is still accessible
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer {
                        if accessing {
                            url.stopAccessingSecurityScopedResource()
                        }
                    }
                    
                    // If we can't access the bookmark, clear it
                    if !accessing {
                        await MainActor.run {
                            logWarning("Destination bookmark at index \(index) is invalid, clearing...")
                            if index < destinationURLs.count {
                                destinationURLs[index] = nil
                            }
                            if index < destinationKeys.count {
                                UserDefaults.standard.removeObject(forKey: destinationKeys[index])
                            }
                            // Update the item to have no URL
                            destinationItems[index] = DestinationItem(url: nil)
                        }
                        return
                    }
                    
                    // Check if the path exists and is accessible
                    let isAccessible = FileManager.default.fileExists(atPath: url.path)
                    
                    if isAccessible {
                        // Destination is accessible, analyze it
                        if let driveInfo = DriveAnalyzer.analyzeDrive(at: url) {
                            await MainActor.run {
                                destinationDriveInfo[itemID] = driveInfo
                                logInfo("Initial drive analysis: \(driveInfo.deviceName) - \(driveInfo.connectionType.displayName)", category: .performance)
                            }
                        }
                    } else {
                        // Destination is not accessible (drive disconnected, etc.)
                        await MainActor.run {
                            // Store a special marker to indicate unavailable destination
                            logInfo("Destination not accessible: \(url.lastPathComponent)")
                            // We'll create a special DriveInfo to indicate unavailable
                            let unavailableInfo = DriveAnalyzer.DriveInfo(
                                mountPath: url,
                                connectionType: .unknown,
                                isSSD: false,
                                deviceName: url.lastPathComponent,
                                protocolDetails: "Not Connected",
                                estimatedWriteSpeed: 0,
                                estimatedReadSpeed: 0,
                                volumeUUID: nil,
                                hardwareSerial: nil,
                                deviceModel: nil,
                                totalCapacity: 0,
                                freeSpace: 0,
                                driveType: .generic
                            )
                            destinationDriveInfo[itemID] = unavailableInfo
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Public Methods
    func clearAllSelections() {
        sourceURL = nil
        UserDefaults.standard.removeObject(forKey: sourceKey)
        for (i, _) in destinationURLs.enumerated() {
            destinationURLs[i] = nil
            if i < destinationKeys.count {
                UserDefaults.standard.removeObject(forKey: destinationKeys[i])
            }
        }
        // Clear all drive info
        destinationDriveInfo.removeAll()
        // Reset to show at least one destination slot
        destinationURLs = [nil]
        destinationItems = [DestinationItem()]
    }
    
    func addDestination() {
        if destinationItems.count < 4 {
            let newItem = DestinationItem()
            destinationItems.append(newItem)
            destinationURLs.append(nil)
        }
    }
    
    func setSource(_ url: URL) {
        sourceURL = url
        saveBookmark(url: url, key: sourceKey)
        tagSourceFolder(at: url)
        
        // Clear previous scan results
        sourceFileTypes = [:]
        scanProgress = ""
        progressTracker.sourceTotalBytes = 0
        
        // Start background scan for image files
        Task { [weak self] in
            await self?.scanSourceFolder(url)
        }
    }
    
    func setDestination(_ url: URL, at index: Int) {
        guard index < destinationItems.count else { return }
        guard index < destinationURLs.count else { return }
        
        // Check if this is the same as the source
        if let source = sourceURL, source == url {
            if !BackupManager.isRunningTests {
                let alert = NSAlert()
                alert.messageText = "Invalid Destination"
                alert.informativeText = "The destination folder cannot be the same as the source folder."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
            return
        }
        
        // Check if this destination is already selected
        for (i, existingURL) in destinationURLs.enumerated() {
            if i != index && existingURL == url {
                // Show alert that this destination is already selected
                if !BackupManager.isRunningTests {
                    let alert = NSAlert()
                    alert.messageText = "Duplicate Destination"
                    alert.informativeText = "This folder is already selected as destination #\(i + 1). Please choose a different folder."
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
                return
            }
        }
        
        // Check if this is a source folder
        if checkForSourceTag(at: url) {
            if !BackupManager.isRunningTests {
                // Show choice dialog
                let alert = NSAlert()
                alert.messageText = "Source Folder Selected"
                alert.informativeText = "This folder was previously used as a source. Using it as a destination will remove the source tag. Do you want to continue?"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Use This Folder")
                alert.addButton(withTitle: "Cancel")
                
                let response = alert.runModal()
                if response == .alertSecondButtonReturn {
                    // User clicked "Cancel" - don't set destination
                    return
                }
            }
            
            // Remove source tag and proceed (in tests, always proceed)
            removeSourceTag(at: url)
        }
        
        destinationItems[index].url = url
        destinationURLs[index] = url
        if index < destinationKeys.count {
            saveBookmark(url: url, key: destinationKeys[index])
        }
        
        // Analyze drive for performance estimates
        let itemID = destinationItems[index].id
        Task {
            // Check if the destination is accessible
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            let isAccessible = FileManager.default.fileExists(atPath: url.path)
            
            // Do an immediate space check if we know the backup size
            if totalBytesToCopy > 0 {
                let spaceCheck = DiskSpaceChecker.checkDestinationSpace(
                    destination: url,
                    requiredBytes: totalBytesToCopy
                )
                
                if let error = spaceCheck.error {
                    await MainActor.run {
                        logError("Destination space issue: \(error)")
                        // We'll show the warning but still allow selection
                        // The actual backup will do a final check
                    }
                } else if let warning = spaceCheck.warning {
                    await MainActor.run {
                        logWarning("Destination space warning: \(warning)")
                    }
                }
            }
            
            if isAccessible {
                if let driveInfo = DriveAnalyzer.analyzeDrive(at: url) {
                    await MainActor.run {
                        destinationDriveInfo[itemID] = driveInfo
                        logInfo("Drive analyzed: \(driveInfo.deviceName) - \(driveInfo.connectionType.displayName) - Write: \(driveInfo.estimatedWriteSpeed) MB/s", category: .performance)
                    }
                }
            } else {
                // Destination selected but not accessible
                await MainActor.run {
                    let unavailableInfo = DriveAnalyzer.DriveInfo(
                        mountPath: url,
                        connectionType: .unknown,
                        isSSD: false,
                        deviceName: url.lastPathComponent,
                        protocolDetails: "Not Connected",
                        estimatedWriteSpeed: 0,
                        estimatedReadSpeed: 0,
                        volumeUUID: nil,
                        hardwareSerial: nil,
                        deviceModel: nil,
                        totalCapacity: 0,
                        freeSpace: 0,
                        driveType: .generic
                    )
                    destinationDriveInfo[itemID] = unavailableInfo
                    logInfo("Destination not accessible: \(url.lastPathComponent)")
                }
            }
        }
    }
    
    func clearDestination(at index: Int) {
        guard index < destinationURLs.count else { return }
        guard index < destinationItems.count else { return }
        
        // Clear drive info for this item
        let itemID = destinationItems[index].id
        destinationDriveInfo.removeValue(forKey: itemID)
        
        destinationURLs[index] = nil
        if index < destinationKeys.count {
            UserDefaults.standard.removeObject(forKey: destinationKeys[index])
        }
    }
    
    @MainActor
    func removeDestination(at index: Int) {
        guard index < destinationItems.count else { return }
        
        // Don't remove if it's the last destination
        guard destinationItems.count > 1 else { 
            // Just clear the last one instead
            let itemID = destinationItems[0].id
            destinationItems[0].url = nil
            destinationURLs = [nil]
            destinationDriveInfo.removeValue(forKey: itemID)
            UserDefaults.standard.removeObject(forKey: destinationKeys[0])
            return
        }
        
        // Remove drive info for this item
        let itemID = destinationItems[index].id
        destinationDriveInfo.removeValue(forKey: itemID)
        
        // Remove from items array
        destinationItems.remove(at: index)
        
        // Rebuild URLs array and update UserDefaults
        var newURLs: [URL?] = []
        for (i, item) in destinationItems.enumerated() {
            newURLs.append(item.url)
            
            // Update UserDefaults - shift all bookmarks down
            if i < destinationKeys.count {
                if let url = item.url {
                    saveBookmark(url: url, key: destinationKeys[i])
                } else {
                    UserDefaults.standard.removeObject(forKey: destinationKeys[i])
                }
            }
        }
        
        // Clear any remaining keys
        for i in destinationItems.count..<destinationKeys.count {
            UserDefaults.standard.removeObject(forKey: destinationKeys[i])
        }
        
        // Update the URLs array
        destinationURLs = newURLs
        
        logInfo("Removed destination at index \(index), new count: \(destinationItems.count)")
    }
    
    func canRunBackup() -> Bool {
        return sourceURL != nil && !destinationURLs.compactMap { $0 }.isEmpty && !isProcessing
    }
    
    func runBackup() {
        guard let source = sourceURL else {
            logWarning("Missing source folder.")
            return
        }

        let destinations = destinationURLs.compactMap { $0 }
        
        // Check disk space for all destinations
        let spaceChecks = DiskSpaceChecker.checkAllDestinations(
            destinations: destinations,
            requiredBytes: totalBytesToCopy
        )
        
        let (canProceed, warnings, errors) = DiskSpaceChecker.evaluateSpaceChecks(spaceChecks)
        
        // If we have errors (insufficient space), show alert and abort
        if !canProceed {
            let alert = NSAlert()
            alert.messageText = "Insufficient Disk Space"
            alert.informativeText = errors.joined(separator: "\n\n")
            alert.alertStyle = .critical
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }
        
        // If we have warnings (< 10% free after backup), show alert with option to proceed
        if !warnings.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Low Disk Space Warning"
            alert.informativeText = warnings.joined(separator: "\n\n") + "\n\nDo you want to continue?"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Continue")
            alert.addButton(withTitle: "Cancel")
            
            let response = alert.runModal()
            if response != .alertFirstButtonReturn {
                return
            }
        }
        
        // Show pre-flight summary if enabled
        if PreferencesManager.shared.showPreflightSummary {
            let alert = NSAlert()
            alert.messageText = "Backup Summary"
            
            // Build the summary message
            var message = "Ready to start backup:\n\n"
            
            // Source info
            message += "📁 Source: \(source.lastPathComponent)\n"
            message += "   Path: \(source.path)\n\n"
            
            // File summary
            if let filteredSummary = getFilteredFilesSummary() {
                message += "📊 Files to backup:\n"
                if filteredSummary.willCopy != filteredSummary.total {
                    message += "   \(filteredSummary.willCopy) of \(filteredSummary.total) files (filtered)\n"
                    message += "   Types: \(filteredSummary.summary)\n\n"
                } else {
                    message += "   \(filteredSummary.total) files\n"
                    message += "   Types: \(filteredSummary.summary)\n\n"
                }
            } else if !sourceFileTypes.isEmpty {
                let totalFiles = sourceFileTypes.values.reduce(0, +)
                message += "📊 Files to backup: \(totalFiles)\n"
                message += "   Types: \(getFormattedFileTypeSummary())\n\n"
            }
            
            // Size info
            if sourceTotalBytes > 0 {
                let formatter = ByteCountFormatter()
                formatter.countStyle = .file
                let sizeString = formatter.string(fromByteCount: sourceTotalBytes)
                message += "💾 Total size: \(sizeString)\n\n"
            }
            
            // Destination info
            message += "📍 Destination\(destinations.count > 1 ? "s" : ""):\n"
            for (index, dest) in destinations.enumerated() {
                message += "   \(index + 1). \(dest.lastPathComponent)"
                
                // Add drive info if available
                if index < destinationItems.count {
                    let itemID = destinationItems[index].id
                    if let driveInfo = destinationDriveInfo[itemID] {
                        if !driveInfo.deviceName.isEmpty {
                            message += " (\(driveInfo.deviceName))"
                        }
                    }
                }
                message += "\n"
            }
            
            // Settings info
            message += "\n⚙️ Settings:\n"
            if PreferencesManager.shared.excludeCacheFiles {
                message += "   • Cache files will be excluded\n"
            }
            if PreferencesManager.shared.skipHiddenFiles {
                message += "   • Hidden files will be skipped\n"
            }
            if !fileTypeFilter.includedExtensions.isEmpty {
                message += "   • File type filter is active\n"
            }
            
            alert.informativeText = message
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Start Backup")
            alert.addButton(withTitle: "Cancel")
            
            // Add "Show this summary before run" checkbox
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = "Show this summary before run"
            alert.suppressionButton?.state = .on  // Checked by default
            
            let response = alert.runModal()
            
            // Update preference based on checkbox state
            // Note: suppression button logic is inverted - when unchecked, we disable the summary
            PreferencesManager.shared.showPreflightSummary = (alert.suppressionButton?.state == .on)
            
            if response != .alertFirstButtonReturn {
                return
            }
        }

        isProcessing = true
        statusMessage = "Preparing backup..."
        progressTracker.totalFiles = 0
        progressTracker.processedFiles = 0
        progressTracker.currentFile = ""
        failedFiles = []
        sessionID = UUID().uuidString
        logEntries = []
        shouldCancel = false
        debugLog = []
        hasWrittenDebugLog = false
        
        // Start preventing sleep
        SleepPrevention.shared.startPreventingSleep(reason: "ImageIntact backup to \(destinations.count) destination(s)")
        
        // Use the new queue-based backup system for parallel destination processing
        Task { [weak self] in
            await self?.performQueueBasedBackup(source: source, destinations: destinations)
        }
    }
    
    func cancelOperation() {
        guard !shouldCancel else { return }  // Prevent multiple cancellations
        shouldCancel = true
        statusMessage = "Cancelling backup..."
        
        // Stop preventing sleep
        SleepPrevention.shared.stopPreventingSleep()
        
        // Cancel orchestrator if using new system
        Task { @MainActor [weak self] in
            self?.currentOrchestrator?.cancel()
        }
        
        // Cancel legacy coordinator if still in use
        currentOperation?.cancel()
        
        // Cancel the monitor task
        currentMonitorTask?.cancel()
        currentMonitorTask = nil
        
        // Cancel the queue-based coordinator if it's running
        if let coordinator = currentCoordinator {
            Task { @MainActor [weak coordinator] in
                coordinator?.cancelBackup()
            }
        }
        currentCoordinator = nil
        
        // Clean up resources
        Task { [weak self] in
            await self?.resourceManager.cleanup()
        }
        
        // Force memory cleanup
        cleanupMemory()
    }
    
    /// Force memory cleanup after backup completion or cancellation
    func cleanupMemory() {
        // Clear large data structures
        logEntries.removeAll(keepingCapacity: false)
        debugLog.removeAll(keepingCapacity: false)
        
        // DON'T clear failedFiles - needed for completion report
        // DON'T clear statistics - needed for completion report
        // DON'T clear progress data yet - UI may still need it
        // DON'T clear sourceFileTypes - needed for UI display
        
        // Note: We keep sourceFileTypes since it's needed for the UI
        // It will be refreshed when a new source is selected
        
        // Don't clear destination info - keep it for UI display
        // destinationDriveInfo.removeAll(keepingCapacity: false)
        
        // Clear orchestrator and coordinator references
        currentOrchestrator = nil
        currentCoordinator = nil
        currentMonitorTask = nil
        currentOperation = nil
        
        // Note: Core Data will manage its own memory
        EventLogger.shared.resetContexts()
        
        // Force cleanup with autorelease pool
        autoreleasepool { }
        
        logInfo("Initial memory cleanup completed", category: .performance)
        
        // Schedule deep cleanup after UI has shown stats
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
            
            guard let self = self else { return }
            
            // Now clear the rest
            self.failedFiles.removeAll(keepingCapacity: false)
            self.progressTracker.resetAll()
            self.progressTracker.destinationProgress.removeAll(keepingCapacity: false)
            self.progressTracker.destinationStates.removeAll(keepingCapacity: false)
            self.statistics.reset()
            self.statusMessage = ""
            self.overallStatusText = ""
            // Keep scanProgress - it shows the file type summary
            
            // Clean up checksum buffer pool
            ChecksumBufferPool.shared.cleanupUnusedBuffers()
            
            autoreleasepool { }
            logInfo("Deep memory cleanup completed", category: .performance)
        }
    }
    
    // MARK: - Debug Logging
    @MainActor
    private func writeDebugLog() {
        // Implementation for debug logging - placeholder for now
        logInfo("Debug log: \(failedFiles.count) failed files")
    }
    
    // MARK: - Private Methods
    private func saveBookmark(url: URL, key: String) {
        do {
            // Start accessing the security-scoped resource before creating bookmark
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: key)
            UserDefaults.standard.synchronize() // Force save immediately
            logInfo("Successfully saved bookmark for \(key): \(url.lastPathComponent)")
        } catch {
            logError("Failed to save bookmark for \(key): \(error)")
        }
    }
    
    static func loadBookmark(forKey key: String) -> URL? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        var isStale = false
        return try? URL(resolvingBookmarkData: data, options: [.withoutUI, .withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale)
    }
    
    static func loadDestinationBookmarks() -> [URL?] {
        let keys = ["dest1Bookmark", "dest2Bookmark", "dest3Bookmark", "dest4Bookmark"]
        var urls: [URL?] = []
        
        // Load bookmarks sequentially until we hit a gap
        for key in keys {
            if let url = loadBookmark(forKey: key) {
                logInfo("Loaded destination from \(key): \(url.lastPathComponent)")
                urls.append(url)
            } else {
                logInfo("No bookmark found for \(key)")
                // Stop at first missing bookmark to avoid gaps
                break
            }
        }
        
        // Always show at least one slot
        if urls.isEmpty {
            urls = [nil]
        }
        
        logInfo("Total destinations loaded: \(urls.count)")
        return urls
    }
    
    
    private func tagSourceFolder(at url: URL) {
        let tagFile = url.appendingPathComponent(".imageintact_source")
        let tagContent = """
        {
            "source_id": "\(UUID().uuidString)",
            "tagged_date": "\(Date().ISO8601Format())",
            "app_version": "1.1.0"
        }
        """
        
        do {
            try tagContent.write(to: tagFile, atomically: true, encoding: .utf8)
            // Hide the tag file
            try FileManager.default.setAttributes([.extensionHidden: true], ofItemAtPath: tagFile.path)
        } catch {
            logError("Failed to tag source folder: \(error)")
        }
    }
    
    private func checkForSourceTag(at url: URL) -> Bool {
        let tagFile = url.appendingPathComponent(".imageintact_source")
        return FileManager.default.fileExists(atPath: tagFile.path)
    }
    
    private func removeSourceTag(at url: URL) {
        let tagFile = url.appendingPathComponent(".imageintact_source")
        do {
            try FileManager.default.removeItem(at: tagFile)
            logInfo("Removed source tag from: \(url.path)")
        } catch {
            logError("Failed to remove source tag: \(error)")
        }
    }
    
    // MARK: - Simple Progress Updates
    @MainActor
    func updateProgress(fileName: String, destinationName: String) {
        Task {
            // Update through ProgressTracker
            progressTracker.updateFileProgress(fileName: fileName, destinationName: destinationName)
        }
    }
    
    @MainActor
    func updateCopySpeed(bytesAdded: Int64) {
        progressTracker.totalBytesCopied += bytesAdded
        let elapsed = Date().timeIntervalSince(progressTracker.copyStartTime)
        if elapsed > 0 {
            progressTracker.copySpeed = Double(progressTracker.totalBytesCopied) / (1024 * 1024) / elapsed
            // ETA update is handled by ProgressTracker internally
        }
    }
    
    @MainActor
    func updateETA() {
        // Delegate to ProgressTracker - kept for compatibility
        // The actual ETA calculation happens in ProgressTracker
    }
    
    func formattedETA() -> String {
        return progressTracker.formattedETA()
    }
    
    @MainActor
    func resetProgress() {
        progressTracker.resetAll()
        
        // Reset actor state (still needed for legacy code)
        Task {
            await progressState.resetAll()
        }
    }
    
    @MainActor
    func initializeDestinations(_ destinations: [URL]) async {
        progressTracker.initializeDestinations(destinations)
        await progressState.initializeDestinations(destinations.map { $0.lastPathComponent })
    }
    
    @MainActor
    func incrementDestinationProgress(_ destinationName: String) {
        Task {
            _ = progressTracker.incrementDestinationProgress(destinationName)
            _ = await progressState.incrementDestinationProgress(for: destinationName)
        }
    }
    
    // MARK: - File Scanning Methods
    @MainActor
    func scanSourceFolder(_ url: URL) async {
        isScanning = true
        scanProgress = "Scanning for image files..."
        sourceFileTypes = [:]
        progressTracker.sourceTotalBytes = 0
        
        // Access the security-scoped resource
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        // Check if we actually got access
        if !accessing {
            scanProgress = "⚠️ Cannot access folder - permission denied"
            isScanning = false
            logWarning("Failed to access security-scoped resource for: \(url.lastPathComponent)")
            
            // Clear the invalid bookmark
            if sourceURL == url {
                sourceURL = nil
                UserDefaults.standard.removeObject(forKey: sourceKey)
            }
            return
        }
        
        do {
            let (results, totalBytes) = try await fileScanner.scanWithSize(directory: url) { progress in
                Task { @MainActor in
                    if progress.scanned % 100 == 0 {
                        self.scanProgress = "Scanned \(progress.scanned) files..."
                    }
                }
            }
            
            await MainActor.run {
                self.sourceFileTypes = results
                self.progressTracker.sourceTotalBytes = totalBytes
                self.scanProgress = ImageFileScanner.formatScanResults(results, groupRaw: false)
                self.isScanning = false
            }
        } catch {
            await MainActor.run {
                self.scanProgress = "Scan failed: \(error.localizedDescription)"
                self.isScanning = false
            }
        }
    }
    
    func getFormattedFileTypeSummary(groupRaw: Bool = false) -> String {
        if sourceFileTypes.isEmpty {
            return isScanning ? scanProgress : ""
        }
        
        var result = ImageFileScanner.formatScanResults(sourceFileTypes, groupRaw: groupRaw)
        
        // Add total size if we have it from the scan
        if sourceTotalBytes > 0 {
            // Use 1000^3 to match macOS Finder display (metric GB)
            let gb = Double(sourceTotalBytes) / (1000 * 1000 * 1000)
            result += String(format: " • %.1f GB", gb)
        }
        
        return result
    }
    
    /// Get a summary of what files will be copied with the current filter
    func getFilteredFilesSummary() -> (summary: String, willCopy: Int, total: Int)? {
        guard !sourceFileTypes.isEmpty else { return nil }
        
        var filteredTypes: [ImageFileType: Int] = [:]
        var totalFiltered = 0
        var totalFiles = 0
        
        // Calculate totals
        for (type, count) in sourceFileTypes {
            totalFiles += count
            
            // Check if this type will be included with current filter
            if fileTypeFilter.shouldInclude(fileType: type) {
                filteredTypes[type] = count
                totalFiltered += count
            }
        }
        
        // If no filter is active, all files will be copied
        if fileTypeFilter.includedExtensions.isEmpty {
            return (getFormattedFileTypeSummary(), totalFiles, totalFiles)
        }
        
        // Format the filtered summary
        let filteredSummary = ImageFileScanner.formatScanResults(filteredTypes, groupRaw: false)
        
        return (filteredSummary, totalFiltered, totalFiles)
    }
    
    func getDestinationEstimate(at index: Int) -> String? {
        guard index < destinationItems.count else { return nil }
        let itemID = destinationItems[index].id
        guard let driveInfo = destinationDriveInfo[itemID] else { return nil }
        
        // Check if destination is unavailable
        if driveInfo.estimatedWriteSpeed == 0 && driveInfo.protocolDetails == "Not Connected" {
            return "⚠️ Destination not accessible (drive may be disconnected)"
        }
        
        // Get free space info if available
        var freeSpaceInfo = ""
        if let url = destinationItems[index].url {
            // For network drives, try different approaches
            if driveInfo.connectionType == .network {
                // Try statfs for network volumes
                var stat = statfs()
                if statfs(url.path, &stat) == 0 {
                    let availableBytes = Int64(stat.f_bavail) * Int64(stat.f_bsize)
                    if availableBytes > 0 {
                        let formatter = ByteCountFormatter()
                        formatter.countStyle = .file
                        freeSpaceInfo = " • \(formatter.string(fromByteCount: availableBytes)) free"
                    } else {
                        // Network volume might not report space correctly
                        freeSpaceInfo = ""  // Don't show misleading "Zero KB free"
                    }
                } else {
                    // Can't determine space for network volume
                    freeSpaceInfo = ""  // Don't show misleading info
                }
            } else {
                // For local drives, use the standard approach
                do {
                    let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
                    // Use volumeAvailableCapacityForImportantUsage if available (more accurate for user data)
                    // Falls back to volumeAvailableCapacity if not
                    let importantUsage = values.volumeAvailableCapacityForImportantUsage.map { Int64($0) }
                    let regularCapacity = values.volumeAvailableCapacity.map { Int64($0) }
                    let availableBytes = importantUsage ?? regularCapacity ?? Int64(0)
                    let formatter = ByteCountFormatter()
                    formatter.countStyle = .file
                    freeSpaceInfo = " • \(formatter.string(fromByteCount: availableBytes)) free"
                } catch {
                    // Fall back to the old method if resource values fail
                    if let spaceInfo = try? FileManager.default.attributesOfFileSystem(forPath: url.path),
                       let freeBytes = spaceInfo[.systemFreeSize] as? Int64 {
                        let formatter = ByteCountFormatter()
                        formatter.countStyle = .file
                        freeSpaceInfo = " • \(formatter.string(fromByteCount: freeBytes)) free"
                    }
                }
            }
        }
        
        // For network drives, don't show estimates - too many variables
        if driveInfo.connectionType == .network {
            return "Network Drive\(freeSpaceInfo) • Too many variables to estimate time"
        }
        
        // Calculate total size
        var totalBytes: Int64 = 0
        
        // Use actual size from scan if available
        if sourceTotalBytes > 0 {
            totalBytes = sourceTotalBytes
        } else if !sourceFileTypes.isEmpty {
            // Use a conservative estimate based on file count if scan hasn't provided size yet
            // Use 500KB average per file as a very conservative estimate
            let totalFiles = sourceFileTypes.values.reduce(0, +)
            totalBytes = Int64(totalFiles) * 500_000  // 500KB per file average
        } else if isScanning {
            // Currently scanning
            return "Scanning files..."
        } else if sourceURL != nil {
            // Source selected but no scan data yet
            return "Analyzing source..."
        } else {
            // No source selected
            return nil
        }
        
        guard totalBytes > 0 else { return nil }
        
        // Adjust estimate based on number of simultaneous destinations
        // Multiple destinations slow things down due to disk contention
        let activeDestinations = destinationItems.compactMap { $0.url }.count
        var adjustedTotalBytes = totalBytes
        if activeDestinations > 1 {
            // Add overhead for multiple simultaneous writes (roughly 30% penalty per extra destination)
            let overhead = 1.0 + (Double(activeDestinations - 1) * 0.3)
            adjustedTotalBytes = Int64(Double(totalBytes) * overhead)
        }
        
        let estimate = driveInfo.formattedEstimate(totalBytes: adjustedTotalBytes)
        // Use decimal GB to match Finder
        let totalGB = Double(totalBytes) / (1000 * 1000 * 1000)
        let sizeStr = String(format: "%.2f GB", totalGB)
        
        // Show drive type properly - Network vs SSD vs HDD
        let driveType = driveInfo.connectionType == .network ? "Network" : (driveInfo.isSSD ? "SSD" : "HDD")
        
        return "\(driveInfo.connectionType.displayName) • \(driveType) • \(sizeStr)\(freeSpaceInfo) • \(estimate)"
    }
}

// MARK: - Backup Operations Extension
extension BackupManager {
    // Static checksum calculation method used by all backup engines
    // Now uses native Swift SHA-256 for maximum reliability with all file types
    nonisolated static func sha256ChecksumStatic(for fileURL: URL, shouldCancel: Bool, isNetworkVolume: Bool = false) throws -> String {
        // First check if file exists
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw NSError(domain: "ImageIntact", code: 1, userInfo: [NSLocalizedDescriptionKey: "File does not exist: \(fileURL.lastPathComponent)"])
        }
        
        // Special handling for files that might be in iCloud and not downloaded
        let resourceValues = try? fileURL.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
        if let status = resourceValues?.ubiquitousItemDownloadingStatus {
            // Status can be: .current, .downloaded, .notDownloaded
            if status == .notDownloaded {
                logWarning("File is in iCloud but not downloaded locally: \(fileURL.lastPathComponent)")
                throw NSError(domain: "ImageIntact", code: 7, userInfo: [NSLocalizedDescriptionKey: "File is in iCloud but not downloaded: \(fileURL.lastPathComponent)"])
            }
        }
        
        // Check if file is readable
        guard FileManager.default.isReadableFile(atPath: fileURL.path) else {
            throw NSError(domain: "ImageIntact", code: 1, userInfo: [NSLocalizedDescriptionKey: "File is not readable: \(fileURL.lastPathComponent)"])
        }
        
        // Use native Swift checksum as primary method for reliability
        return try calculateNativeChecksum(for: fileURL, shouldCancel: shouldCancel)
    }
    
    // Native Swift checksum using CryptoKit - now with optimized implementation
    nonisolated private static func calculateNativeChecksum(for fileURL: URL, shouldCancel: Bool = false) throws -> String {
        // Use the optimized checksum implementation for better performance
        do {
            return try OptimizedChecksum.sha256(for: fileURL, shouldCancel: { shouldCancel })
        } catch {
            // Fall back to size-based checksum if file can't be read
            if let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
               let size = attributes[.size] as? Int64 {
                let sizeHash = String(format: "%016x", size)
                return "size:\(sizeHash)"
            }
            throw error
        }
    }
    
    // Legacy streaming checksum - kept for compatibility but not used
    // The optimized implementation in OptimizedChecksum.swift is now used instead
    nonisolated private static func calculateStreamingChecksum(for fileURL: URL, size: Int64, shouldCancel: Bool = false) throws -> String {
        // This method is no longer called - OptimizedChecksum handles all streaming
        return try OptimizedChecksum.sha256(for: fileURL, shouldCancel: { shouldCancel })
    }
    
    // MARK: - Formatting Helpers
    
    public func formatTime(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "\(Int(seconds))s"
        } else if seconds < 3600 {
            let minutes = Int(seconds / 60)
            let secs = Int(seconds.truncatingRemainder(dividingBy: 60))
            return "\(minutes)m \(secs)s"
        } else {
            let hours = Int(seconds / 3600)
            let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(hours)h \(minutes)m"
        }
    }
    
    public func formatDataSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }
}