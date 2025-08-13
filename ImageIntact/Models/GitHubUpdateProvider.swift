import Foundation

/// GitHub-based update provider that checks releases via GitHub API
class GitHubUpdateProvider: UpdateProvider {
    private let owner = "kmichels"
    private let repo = "ImageIntact"
    private let session = URLSession.shared
    
    var providerName: String {
        return "GitHub Releases"
    }
    
    /// Check for updates via GitHub API
    func checkForUpdates(currentVersion: String) async throws -> AppUpdate? {
        // GitHub API endpoint for latest release
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
        
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw UpdateError.invalidResponse
            }
            
            // Handle 404 (no releases yet)
            if httpResponse.statusCode == 404 {
                print("No releases found on GitHub")
                return nil
            }
            
            guard httpResponse.statusCode == 200 else {
                throw UpdateError.invalidResponse
            }
            
            // Parse GitHub release JSON
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw UpdateError.invalidResponse
            }
            
            // Extract version (remove 'v' prefix if present)
            guard let tagName = json["tag_name"] as? String else {
                throw UpdateError.invalidResponse
            }
            let version = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
            
            // Check if update is newer (latest must be greater than current)
            let comparison = version.compare(currentVersion, options: .numeric)
            if comparison != .orderedDescending {
                print("No update needed: current v\(currentVersion) >= latest v\(version)")
                return nil
            }
            print("Update available: v\(currentVersion) -> v\(version)")
            
            // Extract release notes
            let releaseNotes = json["body"] as? String ?? "No release notes available"
            
            // Find macOS .dmg asset
            guard let assets = json["assets"] as? [[String: Any]],
                  let dmgAsset = assets.first(where: { asset in
                      guard let name = asset["name"] as? String else { return false }
                      return name.hasSuffix(".dmg") && name.contains("macOS")
                  }) else {
                print("No macOS DMG found in release assets")
                throw UpdateError.invalidResponse
            }
            
            guard let downloadURLString = dmgAsset["browser_download_url"] as? String,
                  let downloadURL = URL(string: downloadURLString) else {
                throw UpdateError.invalidResponse
            }
            
            // Parse published date
            let publishedDate: Date
            if let publishedString = json["published_at"] as? String {
                let formatter = ISO8601DateFormatter()
                publishedDate = formatter.date(from: publishedString) ?? Date()
            } else {
                publishedDate = Date()
            }
            
            // Get file size if available
            let fileSize = dmgAsset["size"] as? Int64
            
            // Extract minimum OS version from release notes (if specified)
            let minimumOSVersion = extractMinimumOSVersion(from: releaseNotes)
            
            return AppUpdate(
                version: version,
                releaseNotes: releaseNotes,
                downloadURL: downloadURL,
                publishedDate: publishedDate,
                minimumOSVersion: minimumOSVersion,
                fileSize: fileSize
            )
            
        } catch {
            throw UpdateError.networkError(error)
        }
    }
    
    /// Download an update with progress tracking
    func downloadUpdate(_ update: AppUpdate, progress: @escaping (Double) -> Void) async throws -> URL {
        let request = URLRequest(url: update.downloadURL)
        
        // Create download task
        let (localURL, response) = try await session.download(for: request) { bytesWritten, totalBytes in
            if totalBytes > 0 {
                let progressValue = Double(bytesWritten) / Double(totalBytes)
                Task { @MainActor in
                    progress(progressValue)
                }
            }
        }
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw UpdateError.downloadFailed(UpdateError.invalidResponse)
        }
        
        // Move to Downloads folder
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let fileName = update.downloadURL.lastPathComponent
        let destinationURL = downloadsURL.appendingPathComponent(fileName)
        
        // Remove existing file if present
        try? FileManager.default.removeItem(at: destinationURL)
        
        // Move downloaded file
        try FileManager.default.moveItem(at: localURL, to: destinationURL)
        
        return destinationURL
    }
    
    // MARK: - Helper Methods
    
    /// Extract minimum OS version from release notes
    private func extractMinimumOSVersion(from releaseNotes: String) -> String? {
        // Look for patterns like "Requires macOS 13.0" or "Minimum: macOS 14.0"
        let patterns = [
            "Requires macOS ([0-9]+(?:\\.[0-9]+)?)",
            "Minimum: macOS ([0-9]+(?:\\.[0-9]+)?)",
            "macOS ([0-9]+(?:\\.[0-9]+)?) or later"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: releaseNotes, range: NSRange(releaseNotes.startIndex..., in: releaseNotes)),
               match.numberOfRanges > 1 {
                let versionRange = match.range(at: 1)
                if let range = Range(versionRange, in: releaseNotes) {
                    return String(releaseNotes[range])
                }
            }
        }
        
        return nil
    }
}

// MARK: - URLSession Extension for Download Progress

extension URLSession {
    /// Download with progress tracking
    func download(for request: URLRequest, progress: @escaping (Int64, Int64) -> Void) async throws -> (URL, URLResponse) {
        let delegate = DownloadDelegate(progressHandler: progress)
        return try await withCheckedThrowingContinuation { continuation in
            let task = self.downloadTask(with: request) { url, response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let url = url, let response = response {
                    continuation.resume(returning: (url, response))
                } else {
                    continuation.resume(throwing: UpdateError.invalidResponse)
                }
            }
            delegate.task = task
            task.resume()
        }
    }
}

/// Download delegate for progress tracking
private class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let progressHandler: (Int64, Int64) -> Void
    weak var task: URLSessionDownloadTask?
    
    init(progressHandler: @escaping (Int64, Int64) -> Void) {
        self.progressHandler = progressHandler
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        progressHandler(totalBytesWritten, totalBytesExpectedToWrite)
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Handled in completion handler
    }
}