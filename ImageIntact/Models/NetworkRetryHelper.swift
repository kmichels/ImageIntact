import Foundation

/// Helper for retrying operations that may fail due to transient network issues
struct NetworkRetryHelper {
    static let maxRetries = 3
    static let retryDelay: UInt64 = 1_000_000_000 // 1 second in nanoseconds
    
    /// Retry an async operation with exponential backoff
    static func retry<T>(
        maxAttempts: Int = maxRetries,
        operation: () async throws -> T,
        shouldRetry: (Error) -> Bool = { _ in true }
    ) async throws -> T {
        var lastError: Error?
        
        for attempt in 1...maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                
                // Check if we should retry this error
                guard shouldRetry(error) else {
                    throw error
                }
                
                // Don't retry on last attempt
                guard attempt < maxAttempts else {
                    break
                }
                
                // Exponential backoff: 1s, 2s, 4s
                let delay = retryDelay * UInt64(1 << (attempt - 1))
                print("⚠️ Operation failed (attempt \(attempt)/\(maxAttempts)), retrying in \(delay/1_000_000_000)s...")
                try? await Task.sleep(nanoseconds: delay)
            }
        }
        
        throw lastError ?? NSError(domain: "NetworkRetry", code: -1, userInfo: [NSLocalizedDescriptionKey: "Operation failed after \(maxAttempts) attempts"])
    }
    
    /// Check if an error is likely transient and worth retrying
    static func isTransientError(_ error: Error) -> Bool {
        let nsError = error as NSError
        
        // Network-related error codes that are worth retrying
        let retryableCodes = [
            NSURLErrorTimedOut,
            NSURLErrorCannotConnectToHost,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorNotConnectedToInternet,
            NSURLErrorDNSLookupFailed,
            NSURLErrorResourceUnavailable,
            NSURLErrorInternationalRoamingOff,
            NSURLErrorCallIsActive,
            NSURLErrorDataNotAllowed
        ]
        
        if retryableCodes.contains(nsError.code) {
            return true
        }
        
        // POSIX errors worth retrying
        if nsError.domain == NSPOSIXErrorDomain {
            let retryablePOSIXCodes = [
                35, // EAGAIN - Resource temporarily unavailable
                60, // ETIMEDOUT - Operation timed out
                61, // ECONNREFUSED - Connection refused
                64, // EHOSTDOWN - Host is down
                65  // EHOSTUNREACH - No route to host
            ]
            return retryablePOSIXCodes.contains(Int(nsError.code))
        }
        
        // File system errors on network volumes
        if nsError.domain == NSCocoaErrorDomain {
            let retryableCocoaCodes = [
                NSFileReadNoSuchFileError,     // File disappeared (network hiccup)
                NSFileReadUnknownError,         // Generic read error
                NSFileWriteUnknownError,        // Generic write error
                NSFileWriteNoPermissionError    // Sometimes transient on network volumes
            ]
            return retryableCocoaCodes.contains(nsError.code)
        }
        
        return false
    }
}