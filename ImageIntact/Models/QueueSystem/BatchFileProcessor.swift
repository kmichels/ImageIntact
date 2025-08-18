//
//  BatchFileProcessor.swift
//  ImageIntact
//
//  Batch file operations for improved memory efficiency
//

import Foundation

/// Processes files in batches for better memory efficiency
actor BatchFileProcessor {
    
    // MARK: - URL Cache
    private var urlCache = [String: URL]()
    private let maxCacheSize = 1000
    
    // MARK: - Buffer Pool
    private var bufferPool: [Data] = []
    private let bufferSize = 4 * 1024 * 1024 // 4MB buffers for better disk I/O
    private let maxBuffers = 4
    
    // MARK: - Batch Configuration
    private let batchSize = 50 // Process 50 files at a time
    
    init() {
        // Pre-allocate buffers
        for _ in 0..<maxBuffers {
            bufferPool.append(Data(capacity: bufferSize))
        }
    }
    
    // MARK: - URL Caching
    
    /// Get a cached URL or create a new one
    func getCachedURL(for path: String) -> URL {
        if let cached = urlCache[path] {
            return cached
        }
        
        let url = URL(fileURLWithPath: path)
        
        // Limit cache size
        if urlCache.count >= maxCacheSize {
            // Remove oldest entries (simple FIFO)
            let toRemove = urlCache.count / 4
            urlCache = Dictionary(uniqueKeysWithValues: 
                urlCache.dropFirst(toRemove).map { ($0.key, $0.value) })
        }
        
        urlCache[path] = url
        return url
    }
    
    /// Clear the URL cache to free memory
    func clearURLCache() {
        urlCache.removeAll(keepingCapacity: true)
    }
    
    // MARK: - Buffer Management
    
    /// Get a buffer from the pool
    func borrowBuffer() -> Data {
        if !bufferPool.isEmpty {
            return bufferPool.removeLast()
        }
        // Create new buffer if pool is empty
        return Data(capacity: bufferSize)
    }
    
    /// Return a buffer to the pool
    func returnBuffer(_ buffer: Data) {
        if bufferPool.count < maxBuffers {
            var reusableBuffer = buffer
            reusableBuffer.removeAll(keepingCapacity: true)
            bufferPool.append(reusableBuffer)
        }
    }
    
    // MARK: - Batch Processing
    
    /// Process files in batches
    func processBatch<T>(
        _ files: [T],
        batchOperation: @escaping ([T]) async throws -> Void
    ) async throws {
        for batch in files.chunked(into: batchSize) {
            try await batchOperation(batch)
        }
    }
    
    /// Copy files in batches with optimized buffer usage
    func batchCopyFiles(
        _ tasks: [(source: URL, destination: URL)],
        progress: @escaping (Int) -> Void
    ) async throws {
        var completed = 0
        
        for batch in tasks.chunked(into: batchSize) {
            // Use autoreleasepool for each batch
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                autoreleasepool {
                    do {
                        for (source, destination) in batch {
                            // Create parent directory if needed
                            let destDir = destination.deletingLastPathComponent()
                            if !FileManager.default.fileExists(atPath: destDir.path) {
                                try FileManager.default.createDirectory(
                                    at: destDir,
                                    withIntermediateDirectories: true
                                )
                            }
                            
                            // Use optimized copy with larger buffer
                            try copyFileWithBuffer(from: source, to: destination)
                            
                            completed += 1
                            Task {
                                await MainActor.run {
                                    progress(completed)
                                }
                            }
                        }
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
    
    /// Copy a file using an optimized buffer
    private func copyFileWithBuffer(from source: URL, to destination: URL) throws {
        // For now, use FileManager's optimized copy
        // In future, could implement streaming copy with our buffer pool
        try FileManager.default.copyItem(at: source, to: destination)
    }
    
    // MARK: - Batch Checksum Calculation
    
    /// Calculate checksums for multiple files in a batch
    func batchCalculateChecksums(
        _ files: [URL],
        shouldCancel: @escaping () -> Bool
    ) async throws -> [URL: String] {
        var results = [URL: String]()
        
        for batch in files.chunked(into: batchSize) {
            // Process batch with autoreleasepool
            let batchResults = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[URL: String], Error>) in
                autoreleasepool {
                    var batchChecksums = [URL: String]()
                    
                    do {
                        for file in batch {
                            guard !shouldCancel() else {
                                continuation.resume(returning: batchChecksums)
                                return
                            }
                            
                            let checksum = try BackupManager.sha256ChecksumStatic(
                                for: file,
                                shouldCancel: shouldCancel()
                            )
                            batchChecksums[file] = checksum
                        }
                        continuation.resume(returning: batchChecksums)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            
            // Merge batch results
            results.merge(batchResults) { _, new in new }
            
            // Check cancellation between batches
            guard !shouldCancel() else {
                throw CancellationError()
            }
        }
        
        return results
    }
}

// MARK: - Helper Extensions

extension Array {
    /// Split array into chunks of specified size
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

struct CancellationError: Error {
    var localizedDescription: String {
        "Operation was cancelled"
    }
}