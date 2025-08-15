import Foundation

/// Handles building file manifests for backup operations
/// Extracted from BackupManager to follow Single Responsibility Principle
actor ManifestBuilder {
    
    // MARK: - Properties
    
    /// Callback for status updates
    private var onStatusUpdate: ((String) -> Void)?
    
    /// Callback for failed files
    private var onFileError: ((String, String, String) -> Void)?
    
    // MARK: - Initialization
    
    init() {}
    
    // MARK: - Callbacks
    
    func setStatusCallback(_ callback: @escaping (String) -> Void) {
        self.onStatusUpdate = callback
    }
    
    func setErrorCallback(_ callback: @escaping (String, String, String) -> Void) {
        self.onFileError = callback
    }
    
    // MARK: - Main API
    
    /// Build manifest of files to copy
    /// - Parameters:
    ///   - source: Source directory URL
    ///   - shouldCancel: Closure to check if operation should be cancelled
    /// - Returns: Array of manifest entries or nil if cancelled/failed
    func build(
        source: URL,
        shouldCancel: @escaping () -> Bool
    ) async -> [FileManifestEntry]? {
        var manifest: [FileManifestEntry] = []
        
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: source,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        
        var fileCount = 0
        
        while let url = enumerator.nextObject() as? URL {
            guard !shouldCancel() else { return nil }
            
            do {
                let resourceValues = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                
                guard resourceValues.isRegularFile == true else { continue }
                guard ImageFileType.isSupportedFile(url) else { 
                    // Debug: log skipped files
                    if url.pathExtension.lowercased() == "mp4" || url.pathExtension.lowercased() == "mov" {
                        print("⚠️ Video file skipped (not supported?): \(url.lastPathComponent)")
                    }
                    continue 
                }
                
                fileCount += 1
                
                // Update status
                let statusMessage = "Analyzing file \(fileCount)..."
                if let callback = onStatusUpdate {
                    Task { @MainActor in
                        callback(statusMessage)
                    }
                }
                
                // Debug logging for video files in manifest
                if url.pathExtension.lowercased() == "mp4" || url.pathExtension.lowercased() == "mov" {
                    print("🎬 Adding video to manifest: \(url.lastPathComponent)")
                }
                
                // Calculate checksum with better error handling
                let checksum: String
                do {
                    checksum = try await calculateChecksum(for: url, shouldCancel: shouldCancel)
                } catch {
                    // Log specific error and continue with next file
                    print("⚠️ Checksum failed for \(url.lastPathComponent): \(error.localizedDescription)")
                    
                    if let callback = onFileError {
                        Task { @MainActor in
                            callback(url.lastPathComponent, "manifest", error.localizedDescription)
                        }
                    }
                    continue
                }
                
                // Check cancellation after potentially long checksum operation
                guard !shouldCancel() else { 
                    print("🛑 Manifest building cancelled by user")
                    return nil 
                }
                
                let relativePath = url.path.replacingOccurrences(of: source.path + "/", with: "")
                let size = resourceValues.fileSize ?? 0
                
                let entry = FileManifestEntry(
                    relativePath: relativePath,
                    sourceURL: url,
                    checksum: checksum,
                    size: Int64(size)
                )
                
                manifest.append(entry)
                
            } catch {
                print("Error processing \(url.lastPathComponent): \(error)")
            }
        }
        
        return manifest
    }
    
    // MARK: - Private Methods
    
    /// Calculate SHA256 checksum for a file
    private func calculateChecksum(for url: URL, shouldCancel: @escaping () -> Bool) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try BackupManager.sha256ChecksumStatic(for: url, shouldCancel: shouldCancel())
        }.value
    }
}