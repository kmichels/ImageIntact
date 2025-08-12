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
    var destinationURLs: [URL?] = BackupManager.loadDestinationBookmarks()
    var destinationItems: [DestinationItem] = BackupManager.loadDestinationItems()
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
    private var atomicFileCounter = 0
    
    // ETA tracking
    var totalBytesToCopy: Int64 = 0
    var estimatedSecondsRemaining: TimeInterval? = nil
    private var recentSpeedSamples: [Double] = []
    private var lastETAUpdate: Date = Date()
    
    // Per-destination progress (simple version)
    var destinationProgress: [String: Int] = [:] // destinationName -> completed files
    
    // Phase-based backup tracking
    var currentPhase: BackupPhase = .idle
    var phaseProgress: Double = 0.0  // Progress within current phase (0-1)
    var overallProgress: Double = 0.0  // Overall progress across all phases (0-1)
    
    // File type scanning
    var sourceFileTypes: [ImageFileType: Int] = [:]
    var isScanning = false
    var scanProgress: String = ""
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
    
    // MARK: - Initialization
    init() {
        // Load source URL and trigger scan if it exists
        if let savedSourceURL = BackupManager.loadBookmark(forKey: sourceKey) {
            self.sourceURL = savedSourceURL
            // Trigger scan for the loaded source
            Task {
                await scanSourceFolder(savedSourceURL)
            }
        }
        
        // Initialize destination items if needed
        if destinationItems.isEmpty && !destinationURLs.isEmpty {
            destinationItems = destinationURLs.map { DestinationItem(url: $0) }
        }
        
        // Ensure at least one destination slot
        if destinationItems.isEmpty {
            destinationItems = [DestinationItem()]
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
        
        // Start background scan for image files
        Task {
            await scanSourceFolder(url)
        }
    }
    
    func setDestination(_ url: URL, at index: Int) {
        guard index < destinationItems.count else { return }
        guard index < destinationURLs.count else { return }
        
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
    }
    
    func clearDestination(at index: Int) {
        guard index < destinationURLs.count else { return }
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
            destinationItems[0].url = nil
            destinationURLs = [nil]
            UserDefaults.standard.removeObject(forKey: destinationKeys[0])
            return
        }
        
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
        
        // Run the new phase-based backup operation
        Task {
            await performPhaseBasedBackup(source: source, destinations: destinations)
        }
    }
    
    func cancelOperation() {
        guard !shouldCancel else { return }  // Prevent multiple cancellations
        shouldCancel = true
        statusMessage = "Cancelling backup..."
        currentOperation?.cancel()
    }
    
    // MARK: - Private Methods
    private func saveBookmark(url: URL, key: String) {
        do {
            let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: key)
        } catch {
            print("Failed to save bookmark: \(error)")
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
        
        // Load all saved bookmarks in their exact positions
        for key in keys {
            if let url = loadBookmark(forKey: key) {
                print("Loaded destination from \(key): \(url.lastPathComponent)")
                urls.append(url)
            } else {
                print("No bookmark found for \(key)")
                // Stop looking for more bookmarks after finding an empty slot
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
    
    static func loadDestinationItems() -> [DestinationItem] {
        let urls = loadDestinationBookmarks()
        return urls.map { DestinationItem(url: $0) }
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
        // Thread-safe increment
        atomicFileCounter += 1
        currentFileIndex = atomicFileCounter
        currentFileName = fileName
        currentDestinationName = destinationName
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
    private func updateETA() {
        // Only update ETA every second to avoid too frequent updates
        guard Date().timeIntervalSince(lastETAUpdate) >= 1.0 else { return }
        lastETAUpdate = Date()
        
        // Don't calculate ETA until we have at least 5 seconds of data
        let elapsed = Date().timeIntervalSince(copyStartTime)
        guard elapsed >= 5.0 else {
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
        guard remainingBytes > 0 && averageSpeed > 0 else {
            estimatedSecondsRemaining = nil
            return
        }
        
        let remainingMB = Double(remainingBytes) / (1024 * 1024)
        estimatedSecondsRemaining = remainingMB / averageSpeed
    }
    
    func formattedETA() -> String {
        guard let seconds = estimatedSecondsRemaining else {
            if Date().timeIntervalSince(copyStartTime) < 5.0 {
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
        atomicFileCounter = 0
        destinationProgress.removeAll()
        
        // Reset ETA tracking
        totalBytesToCopy = 0
        estimatedSecondsRemaining = nil
        recentSpeedSamples.removeAll()
        lastETAUpdate = Date()
    }
    
    @MainActor
    func initializeDestinations(_ destinations: [URL]) {
        for destination in destinations {
            destinationProgress[destination.lastPathComponent] = 0
        }
    }
    
    @MainActor
    func incrementDestinationProgress(_ destinationName: String) {
        destinationProgress[destinationName, default: 0] += 1
    }
    
    // MARK: - File Scanning Methods
    @MainActor
    func scanSourceFolder(_ url: URL) async {
        isScanning = true
        scanProgress = "Scanning for image files..."
        sourceFileTypes = [:]
        
        // Access the security-scoped resource
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        do {
            let results = try await fileScanner.scan(directory: url) { progress in
                Task { @MainActor in
                    if progress.scanned % 100 == 0 {
                        self.scanProgress = "Scanned \(progress.scanned) files..."
                    }
                }
            }
            
            await MainActor.run {
                self.sourceFileTypes = results
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
        return ImageFileScanner.formatScanResults(sourceFileTypes, groupRaw: groupRaw)
    }
}

// MARK: - Backup Operations Extension
extension BackupManager {
    // Static checksum calculation method used by all backup engines
    // Now uses native Swift SHA-256 for maximum reliability with all file types
    static func sha256ChecksumStatic(for fileURL: URL, shouldCancel: Bool) throws -> String {
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
}