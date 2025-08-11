import SwiftUI
import Darwin

// MARK: - Backup Phase Enum
enum BackupPhase {
    case idle
    case analyzingSource
    case buildingManifest
    case copyingFiles
    case flushingToDisk
    case verifyingDestinations
    case complete
}

@Observable
class BackupManager {
    // MARK: - Published Properties
    var sourceURL: URL? = BackupManager.loadBookmark(forKey: "sourceBookmark")
    var destinationURLs: [URL?] = BackupManager.loadDestinationBookmarks()
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
    
    // Per-destination progress (simple version)
    var destinationProgress: [String: Int] = [:] // destinationName -> completed files
    
    // Phase-based backup tracking
    var currentPhase: BackupPhase = .idle
    
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
    }
    
    func addDestination() {
        if destinationURLs.count < 4 {
            destinationURLs.append(nil)
        }
    }
    
    func setSource(_ url: URL) {
        sourceURL = url
        saveBookmark(url: url, key: sourceKey)
        tagSourceFolder(at: url)
    }
    
    func setDestination(_ url: URL, at index: Int) {
        guard index < destinationURLs.count else { return }
        
        // Check if this is a source folder
        if checkForSourceTag(at: url) {
            // Show alert
            let alert = NSAlert()
            alert.messageText = "Source Folder Selected"
            alert.informativeText = "This folder has been tagged as a source folder. Using it as a destination could lead to data loss. Please select a different folder."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }
        
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
}

// MARK: - Backup Operations Extension
extension BackupManager {
    // This will contain the main backup logic - moving it in the next step
    // to keep this file manageable for now
}