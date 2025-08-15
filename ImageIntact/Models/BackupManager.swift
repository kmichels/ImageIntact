import SwiftUI
import Darwin
import CryptoKit

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
class BackupManager {
    // MARK: - Published Properties
    var sourceURL: URL? = nil
    var destinationURLs: [URL?] = []
    var destinationItems: [DestinationItem] = []
    var isProcessing = false
    var statusMessage = ""
    var totalFiles = 0
    var processedFiles = 0
    var currentFile = ""
    var failedFiles: [(file: String, destination: String, error: String)] = []
    var sessionID = UUID().uuidString
    var shouldCancel = false
    var debugLog: [String] = []
    var hasWrittenDebugLog = false
    var lastDebugLogPath: URL?
    
    // Simple progress tracking
    var currentFileIndex: Int = 0
    var currentDestinationName: String = ""
    var currentFileName: String = ""
    var copySpeed: Double = 0.0 // MB/s
    var copyStartTime: Date = Date()
    var totalBytesCopied: Int64 = 0
    
    // Thread-safe progress state
    let progressState = BackupProgressState()  // Made internal for extension access
    
    // Resource management
    let resourceManager = ResourceManager()  // Made internal for extension access
    
    // ETA tracking
    var totalBytesToCopy: Int64 = 0
    var estimatedSecondsRemaining: TimeInterval? = nil
    private var recentSpeedSamples: [Double] = []
    private var lastETAUpdate: Date = Date()
    
    // UI-visible progress (updated from actor)
    var destinationProgress: [String: Int] = [:] // destinationName -> completed files
    var destinationStates: [String: String] = [:] // destinationName -> "copying" | "verifying" | "complete"
    var overallStatusText: String = "" // For showing mixed states like "1 copying, 1 verifying"
    
    // Destination drive analysis
    var destinationDriveInfo: [UUID: DriveAnalyzer.DriveInfo] = [:] // Use UUID instead of index to avoid mismatch
    
    // Phase-based backup tracking
    var currentPhase: BackupPhase = .idle
    var phaseProgress: Double = 0.0  // Progress within current phase (0-1)
    var overallProgress: Double = 0.0  // Overall progress across all phases (0-1)
    
    // File type scanning
    var sourceFileTypes: [ImageFileType: Int] = [:]
    var isScanning = false
    var scanProgress: String = ""
    var sourceTotalBytes: Int64 = 0  // Total bytes from manifest
    private let fileScanner = ImageFileScanner()
    
    // Backup options
    var excludeCacheFiles = true  // Default to excluding cache files
    
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
    var currentCoordinator: BackupCoordinator?  // Made internal so extension can access it
    var currentMonitorTask: Task<Void, Never>?  // Made internal so extension can access it
    
    // MARK: - Initialization
    init() {
        // Load destinations first (only once)
        let loadedURLs = BackupManager.loadDestinationBookmarks()
        self.destinationURLs = loadedURLs
        self.destinationItems = loadedURLs.map { DestinationItem(url: $0) }
        
        // Load source URL and trigger scan if it exists
        if let savedSourceURL = BackupManager.loadBookmark(forKey: sourceKey) {
            // Test if we can actually access this bookmark
            let canAccess = savedSourceURL.startAccessingSecurityScopedResource()
            if canAccess {
                savedSourceURL.stopAccessingSecurityScopedResource()
                self.sourceURL = savedSourceURL
                print("Loaded source: \(savedSourceURL.lastPathComponent)")
                // Trigger scan for the loaded source
                Task {
                    await scanSourceFolder(savedSourceURL)
                }
            } else {
                // Bookmark is invalid - clear it
                print("⚠️ Saved source bookmark is invalid, clearing...")
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
                            print("⚠️ Destination bookmark at index \(index) is invalid, clearing...")
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
                                print("Initial drive analysis: \(driveInfo.deviceName) - \(driveInfo.connectionType.displayName)")
                            }
                        }
                    } else {
                        // Destination is not accessible (drive disconnected, etc.)
                        await MainActor.run {
                            // Store a special marker to indicate unavailable destination
                            print("Destination not accessible: \(url.lastPathComponent)")
                            // We'll create a special DriveInfo to indicate unavailable
                            let unavailableInfo = DriveAnalyzer.DriveInfo(
                                mountPath: url,
                                connectionType: .unknown,
                                isSSD: false,
                                deviceName: url.lastPathComponent,
                                protocolDetails: "Not Connected",
                                estimatedWriteSpeed: 0,
                                estimatedReadSpeed: 0
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
        sourceTotalBytes = 0
        
        // Start background scan for image files
        Task {
            await scanSourceFolder(url)
        }
    }
    
    func setDestination(_ url: URL, at index: Int) {
        guard index < destinationItems.count else { return }
        guard index < destinationURLs.count else { return }
        
        // Check if this is the same as the source
        if let source = sourceURL, source == url {
            let alert = NSAlert()
            alert.messageText = "Invalid Destination"
            alert.informativeText = "The destination folder cannot be the same as the source folder."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }
        
        // Check if this destination is already selected
        for (i, existingURL) in destinationURLs.enumerated() {
            if i != index && existingURL == url {
                // Show alert that this destination is already selected
                let alert = NSAlert()
                alert.messageText = "Duplicate Destination"
                alert.informativeText = "This folder is already selected as destination #\(i + 1). Please choose a different folder."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
                return
            }
        }
        
        // Check if this is a source folder
        if checkForSourceTag(at: url) {
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
            
            // User clicked "Use This Folder" - remove source tag and proceed
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
            
            if isAccessible {
                if let driveInfo = DriveAnalyzer.analyzeDrive(at: url) {
                    await MainActor.run {
                        destinationDriveInfo[itemID] = driveInfo
                        print("Drive analyzed: \(driveInfo.deviceName) - \(driveInfo.connectionType.displayName) - Write: \(driveInfo.estimatedWriteSpeed) MB/s")
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
                        estimatedReadSpeed: 0
                    )
                    destinationDriveInfo[itemID] = unavailableInfo
                    print("Destination not accessible: \(url.lastPathComponent)")
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
        
        print("Removed destination at index \(index), new count: \(destinationItems.count)")
    }
    
    func canRunBackup() -> Bool {
        return sourceURL != nil && !destinationURLs.compactMap { $0 }.isEmpty && !isProcessing
    }
    
    func runBackup() {
        guard let source = sourceURL else {
            print("Missing source folder.")
            return
        }

        let destinations = destinationURLs.compactMap { $0 }

        isProcessing = true
        statusMessage = "Preparing backup..."
        totalFiles = 0
        processedFiles = 0
        currentFile = ""
        failedFiles = []
        sessionID = UUID().uuidString
        logEntries = []
        shouldCancel = false
        debugLog = []
        hasWrittenDebugLog = false
        
        // Use the new queue-based backup system for parallel destination processing
        Task {
            await performQueueBasedBackup(source: source, destinations: destinations)
        }
    }
    
    func cancelOperation() {
        guard !shouldCancel else { return }  // Prevent multiple cancellations
        shouldCancel = true
        statusMessage = "Cancelling backup..."
        currentOperation?.cancel()
        
        // Cancel the monitor task
        currentMonitorTask?.cancel()
        currentMonitorTask = nil
        
        // Cancel the queue-based coordinator if it's running
        if let coordinator = currentCoordinator {
            Task { @MainActor in
                coordinator.cancelBackup()
            }
        }
        currentCoordinator = nil
        
        // Clean up resources
        Task {
            await resourceManager.cleanup()
        }
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
            print("Successfully saved bookmark for \(key): \(url.lastPathComponent)")
        } catch {
            print("Failed to save bookmark for \(key): \(error)")
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
                print("Loaded destination from \(key): \(url.lastPathComponent)")
                urls.append(url)
            } else {
                print("No bookmark found for \(key)")
                // Stop at first missing bookmark to avoid gaps
                break
            }
        }
        
        // Always show at least one slot
        if urls.isEmpty {
            urls = [nil]
        }
        
        print("Total destinations loaded: \(urls.count)")
        return urls
    }
    
    // No longer needed - we load directly in init
    // static func loadDestinationItems() -> [DestinationItem] {
    //     let urls = loadDestinationBookmarks()
    //     return urls.map { DestinationItem(url: $0) }
    // }
    
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
            print("Failed to tag source folder: \(error)")
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
            print("Removed source tag from: \(url.path)")
        } catch {
            print("Failed to remove source tag: \(error)")
        }
    }
    
    // MARK: - Simple Progress Updates
    @MainActor
    func updateProgress(fileName: String, destinationName: String) {
        Task {
            // Thread-safe increment through actor
            let newIndex = await progressState.incrementFileCounter()
            currentFileIndex = newIndex
            currentFileName = fileName
            currentDestinationName = destinationName
        }
    }
    
    @MainActor
    func updateCopySpeed(bytesAdded: Int64) {
        totalBytesCopied += bytesAdded
        let elapsed = Date().timeIntervalSince(copyStartTime)
        if elapsed > 0 {
            copySpeed = Double(totalBytesCopied) / (1024 * 1024) / elapsed
            updateETA()
        }
    }
    
    @MainActor
    func updateETA() {
        // Only update ETA every second to avoid too frequent updates
        guard Date().timeIntervalSince(lastETAUpdate) >= 1.0 else { return }
        lastETAUpdate = Date()
        
        // Don't calculate ETA until we have at least 2 seconds of data (reduced from 5)
        let elapsed = Date().timeIntervalSince(copyStartTime)
        guard elapsed >= 2.0 else {
            estimatedSecondsRemaining = nil
            return
        }
        
        // Add current speed to samples (keep last 30 samples for 30-second average)
        if copySpeed > 0 {
            recentSpeedSamples.append(copySpeed)
            if recentSpeedSamples.count > 30 {
                recentSpeedSamples.removeFirst()
            }
        }
        
        // Calculate weighted average speed (recent samples weighted more)
        guard !recentSpeedSamples.isEmpty else {
            estimatedSecondsRemaining = nil
            return
        }
        
        var weightedSum: Double = 0
        var totalWeight: Double = 0
        for (index, speed) in recentSpeedSamples.enumerated() {
            let weight = Double(index + 1) // More recent samples have higher weight
            weightedSum += speed * weight
            totalWeight += weight
        }
        let averageSpeed = weightedSum / totalWeight // MB/s
        
        // Calculate remaining bytes and ETA
        let remainingBytes = totalBytesToCopy - totalBytesCopied
        
        // Debug logging
        print("ETA Debug: totalBytesToCopy=\(totalBytesToCopy), totalBytesCopied=\(totalBytesCopied), remainingBytes=\(remainingBytes), averageSpeed=\(averageSpeed) MB/s, copySpeed=\(copySpeed) MB/s")
        
        guard remainingBytes > 0 && averageSpeed > 0 else {
            estimatedSecondsRemaining = nil
            print("ETA Debug: No ETA - remainingBytes=\(remainingBytes), averageSpeed=\(averageSpeed)")
            return
        }
        
        let remainingMB = Double(remainingBytes) / (1024 * 1024)
        let calculatedETA = remainingMB / averageSpeed
        
        // Sanitize ETA to reasonable bounds (max 24 hours)
        if calculatedETA.isNaN || calculatedETA.isInfinite || calculatedETA < 0 {
            estimatedSecondsRemaining = nil
        } else if calculatedETA > 86400 { // More than 24 hours
            estimatedSecondsRemaining = 86400
        } else {
            estimatedSecondsRemaining = calculatedETA
        }
        
        print("ETA Debug: remainingMB=\(remainingMB), calculatedETA=\(calculatedETA), final estimatedSecondsRemaining=\(estimatedSecondsRemaining ?? -1)")
    }
    
    func formattedETA() -> String {
        guard let seconds = estimatedSecondsRemaining else {
            if Date().timeIntervalSince(copyStartTime) < 2.0 {
                return "Calculating..."
            }
            return ""
        }
        
        // Round to nearest 5 seconds for stability
        let roundedSeconds = round(seconds / 5.0) * 5.0
        
        if roundedSeconds < 60 {
            return "Less than 1 minute remaining"
        } else if roundedSeconds < 300 { // Less than 5 minutes
            let minutes = Int(roundedSeconds / 60)
            return "About \(minutes) minute\(minutes == 1 ? "" : "s") remaining"
        } else if roundedSeconds < 3600 { // Less than 1 hour
            let minutes = Int(roundedSeconds / 60)
            return "About \(minutes) minutes remaining"
        } else { // More than 1 hour
            let hours = Int(roundedSeconds / 3600)
            let minutes = Int((roundedSeconds.truncatingRemainder(dividingBy: 3600)) / 60)
            if minutes > 0 {
                return "About \(hours) hour\(hours == 1 ? "" : "s") \(minutes) minutes remaining"
            } else {
                return "About \(hours) hour\(hours == 1 ? "" : "s") remaining"
            }
        }
    }
    
    @MainActor
    func resetProgress() {
        currentFileIndex = 0
        currentFileName = ""
        currentDestinationName = ""
        copySpeed = 0.0
        copyStartTime = Date()
        totalBytesCopied = 0
        destinationProgress.removeAll()
        destinationStates.removeAll()
        
        // Reset ETA tracking
        totalBytesToCopy = 0
        estimatedSecondsRemaining = nil
        recentSpeedSamples.removeAll()
        lastETAUpdate = Date()
        
        // Reset actor state
        Task {
            await progressState.resetAll()
        }
    }
    
    @MainActor
    func initializeDestinations(_ destinations: [URL]) async {
        let destNames = destinations.map { $0.lastPathComponent }
        await progressState.initializeDestinations(destNames)
        
        // Update local cache for UI
        for destination in destinations {
            destinationProgress[destination.lastPathComponent] = 0
            destinationStates[destination.lastPathComponent] = "copying"
        }
    }
    
    @MainActor
    func incrementDestinationProgress(_ destinationName: String) {
        Task {
            let newValue = await progressState.incrementDestinationProgress(for: destinationName)
            destinationProgress[destinationName] = newValue
        }
    }
    
    // MARK: - File Scanning Methods
    @MainActor
    func scanSourceFolder(_ url: URL) async {
        isScanning = true
        scanProgress = "Scanning for image files..."
        sourceFileTypes = [:]
        sourceTotalBytes = 0
        
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
            print("⚠️ Failed to access security-scoped resource for: \(url.lastPathComponent)")
            
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
                self.sourceTotalBytes = totalBytes
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
        
        // Add total size if we have it from the manifest
        if sourceTotalBytes > 0 {
            // Use 1000^3 to match macOS Finder display
            let gb = Double(sourceTotalBytes) / (1000 * 1000 * 1000)
            result += String(format: " • %.2f GB", gb)
        }
        
        return result
    }
    
    func getDestinationEstimate(at index: Int) -> String? {
        guard index < destinationItems.count else { return nil }
        let itemID = destinationItems[index].id
        guard let driveInfo = destinationDriveInfo[itemID] else { return nil }
        
        // Check if destination is unavailable
        if driveInfo.estimatedWriteSpeed == 0 && driveInfo.protocolDetails == "Not Connected" {
            return "⚠️ Destination not accessible (drive may be disconnected)"
        }
        
        // For network drives, don't show estimates - too many variables
        if driveInfo.connectionType == .network {
            return "Network Drive • Too many variables to estimate time"
        }
        
        // Calculate total size
        var totalBytes: Int64 = 0
        
        // Use actual size from manifest if available
        if sourceTotalBytes > 0 {
            totalBytes = sourceTotalBytes
        } else if !sourceFileTypes.isEmpty {
            // Fall back to estimates from file types
            for (fileType, count) in sourceFileTypes {
                let avgSize = fileType.averageFileSize
                totalBytes += Int64(avgSize * count)
            }
        } else if sourceURL != nil {
            // If no scan yet, return a placeholder
            return "Calculating size..."
        } else {
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
        
        return "\(driveInfo.connectionType.displayName) • \(driveType) • \(sizeStr) • \(estimate)"
    }
}

// MARK: - Backup Operations Extension
extension BackupManager {
    // Static checksum calculation method used by all backup engines
    // Now uses native Swift SHA-256 for maximum reliability with all file types
    static func sha256ChecksumStatic(for fileURL: URL, shouldCancel: Bool, isNetworkVolume: Bool = false) throws -> String {
        // First check if file exists
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw NSError(domain: "ImageIntact", code: 1, userInfo: [NSLocalizedDescriptionKey: "File does not exist: \(fileURL.lastPathComponent)"])
        }
        
        // Special handling for files that might be in iCloud and not downloaded
        let resourceValues = try? fileURL.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
        if let status = resourceValues?.ubiquitousItemDownloadingStatus {
            // Status can be: .current, .downloaded, .notDownloaded
            if status == .notDownloaded {
                print("⚠️ File is in iCloud but not downloaded locally: \(fileURL.lastPathComponent)")
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
    
    // Native Swift checksum using CryptoKit - more reliable than external commands
    private static func calculateNativeChecksum(for fileURL: URL, shouldCancel: Bool = false) throws -> String {
        // Check file size first
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let size = attributes[.size] as? Int64 ?? 0
        
        if size == 0 {
            return "empty-file-0-bytes"
        }
        
        // For large files, use streaming to avoid memory issues
        if size > 10_000_000 { // 10MB - stream to prevent memory pressure
            return try calculateStreamingChecksum(for: fileURL, size: size, shouldCancel: shouldCancel)
        }
        
        // Check cancellation
        if shouldCancel {
            throw NSError(domain: "ImageIntact", code: 6, userInfo: [NSLocalizedDescriptionKey: "Checksum cancelled by user"])
        }
        
        // For smaller files, read entire file
        do {
            let fileData = try Data(contentsOf: fileURL, options: .mappedIfSafe)
            let hash = SHA256.hash(data: fileData)
            let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
            return hashString
        } catch {
            // Fall back to file size-based checksum if file can't be read
            let sizeHash = String(format: "%016x", size)
            return "size:\(sizeHash)"
        }
    }
    
    // Streaming checksum for large files
    private static func calculateStreamingChecksum(for fileURL: URL, size: Int64, shouldCancel: Bool = false) throws -> String {
        guard let inputStream = InputStream(url: fileURL) else {
            throw NSError(domain: "ImageIntact", code: 8, userInfo: [NSLocalizedDescriptionKey: "Cannot open file stream"])
        }
        
        inputStream.open()
        defer { inputStream.close() }
        
        var hasher = SHA256()
        let bufferSize = 1024 * 1024 // 1MB buffer
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        
        var totalBytesRead: Int64 = 0
        
        while inputStream.hasBytesAvailable {
            // Check for cancellation
            if shouldCancel {
                throw NSError(domain: "ImageIntact", code: 6, userInfo: [NSLocalizedDescriptionKey: "Checksum cancelled by user"])
            }
            
            let bytesRead = inputStream.read(buffer, maxLength: bufferSize)
            if bytesRead < 0 {
                // Stream error
                throw NSError(domain: "ImageIntact", code: 9, userInfo: [NSLocalizedDescriptionKey: "Stream read error: \(inputStream.streamError?.localizedDescription ?? "unknown")"])
            } else if bytesRead == 0 {
                // End of stream
                break
            } else {
                // Add bytes to hasher
                hasher.update(data: Data(bytes: buffer, count: bytesRead))
                totalBytesRead += Int64(bytesRead)
            }
        }
        
        let hash = hasher.finalize()
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
        return hashString
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