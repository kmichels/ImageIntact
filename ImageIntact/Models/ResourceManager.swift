import Foundation

/// Manages system resources and ensures proper cleanup
actor ResourceManager {
    private var activeTasks: Set<Task<Void, Never>> = []
    private var fileHandles: [URL: FileHandle] = [:]
    private var securityScopedURLs: Set<URL> = []
    private var timers: [Timer] = []
    
    /// Maximum concurrent operations to prevent resource exhaustion
    private let maxConcurrentOperations = 10
    
    /// Track and manage a task
    func track<T>(task: Task<T, Never>) {
        let voidTask = Task {
            _ = await task.value
        }
        activeTasks.insert(voidTask)
        
        // Clean up when task completes
        Task { [weak self] in
            _ = await task.value
            await self?.removeTask(voidTask)
        }
    }
    
    private func removeTask(_ task: Task<Void, Never>) {
        activeTasks.remove(task)
    }
    
    /// Cancel all tracked tasks
    func cancelAllTasks() {
        for task in activeTasks {
            task.cancel()
        }
        activeTasks.removeAll()
    }
    
    /// Start accessing a security-scoped resource
    func startAccessingSecurityScopedResource(_ url: URL) -> Bool {
        let success = url.startAccessingSecurityScopedResource()
        if success {
            securityScopedURLs.insert(url)
        }
        return success
    }
    
    /// Stop accessing a security-scoped resource
    func stopAccessingSecurityScopedResource(_ url: URL) {
        if securityScopedURLs.contains(url) {
            url.stopAccessingSecurityScopedResource()
            securityScopedURLs.remove(url)
        }
    }
    
    /// Stop accessing all security-scoped resources
    func stopAccessingAllSecurityScopedResources() {
        for url in securityScopedURLs {
            url.stopAccessingSecurityScopedResource()
        }
        securityScopedURLs.removeAll()
    }
    
    /// Open a file handle with tracking
    func openFileHandle(for url: URL) throws -> FileHandle {
        // Close existing handle if any
        if let existingHandle = fileHandles[url] {
            try? existingHandle.close()
        }
        
        let handle = try FileHandle(forReadingFrom: url)
        fileHandles[url] = handle
        return handle
    }
    
    /// Close a specific file handle
    func closeFileHandle(for url: URL) {
        if let handle = fileHandles[url] {
            try? handle.close()
            fileHandles.removeValue(forKey: url)
        }
    }
    
    /// Close all file handles
    func closeAllFileHandles() {
        for (_, handle) in fileHandles {
            try? handle.close()
        }
        fileHandles.removeAll()
    }
    
    /// Track a timer
    func track(timer: Timer) {
        // Note: Timer operations should be done on MainActor
        // For now, we'll skip timer tracking in the actor
    }
    
    /// Invalidate all timers
    func invalidateAllTimers() {
        for timer in timers {
            timer.invalidate()
        }
        timers.removeAll()
    }
    
    /// Check if we're approaching resource limits
    func checkResourceLimits() -> Bool {
        let taskCount = activeTasks.count
        let handleCount = fileHandles.count
        
        if taskCount > maxConcurrentOperations {
            print("⚠️ Resource warning: \(taskCount) active tasks (limit: \(maxConcurrentOperations))")
            return false
        }
        
        if handleCount > 100 {
            print("⚠️ Resource warning: \(handleCount) open file handles")
            return false
        }
        
        return true
    }
    
    /// Clean up all resources
    func cleanup() {
        print("🧹 Cleaning up resources...")
        
        // Cancel all tasks
        cancelAllTasks()
        
        // Close all file handles
        closeAllFileHandles()
        
        // Stop accessing security-scoped resources
        stopAccessingAllSecurityScopedResources()
        
        // Invalidate all timers
        invalidateAllTimers()
        
        print("✅ Resource cleanup complete")
    }
    
    deinit {
        // Note: Can't call async cleanup from deinit
        // Resources will be cleaned up by explicit cleanup() calls
    }
}

/// Extension for automatic resource management
extension ResourceManager {
    /// Execute a block with automatic resource cleanup
    func withResources<T>(operation: () async throws -> T) async rethrows -> T {
        defer { cleanup() }
        return try await operation()
    }
    
    /// Execute a file operation with automatic handle cleanup
    func withFileHandle<T>(
        for url: URL,
        operation: (FileHandle) async throws -> T
    ) async throws -> T {
        let handle = try openFileHandle(for: url)
        defer { closeFileHandle(for: url) }
        return try await operation(handle)
    }
    
    /// Execute with security-scoped resource access
    func withSecurityScopedAccess<T>(
        to url: URL,
        operation: () async throws -> T
    ) async rethrows -> T {
        let accessing = startAccessingSecurityScopedResource(url)
        defer {
            if accessing {
                stopAccessingSecurityScopedResource(url)
            }
        }
        return try await operation()
    }
}