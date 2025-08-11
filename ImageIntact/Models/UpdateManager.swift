import SwiftUI

@Observable
class UpdateManager {
    // MARK: - Published Properties
    var showUpdateAlert = false
    var availableUpdate: UpdateInfo?
    var isDownloadingUpdate = false
    var downloadProgress: Double = 0.0
    var downloadedUpdatePath: URL?
    
    // MARK: - Data Structures
    struct UpdateInfo {
        let version: String
        let releaseNotes: String
        let downloadURL: String
        let fileName: String
        let fileSize: Int64
        let publishedAt: Date
    }
    
    // MARK: - Public Methods
    func checkForUpdates() {
        // Check if user has disabled updates
        guard !UserDefaults.standard.bool(forKey: "updatesDisabled") else {
            print("🔄 Update checks disabled by user")
            return
        }
        
        // Check if we should check for updates (on launch + monthly)
        let lastUpdateCheck = UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Date ?? Date.distantPast
        let monthAgo = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date.distantPast
        
        guard lastUpdateCheck < monthAgo else {
            print("🔄 Update check not needed (checked recently)")
            return
        }
        
        print("🔄 Checking for updates...")
        
        Task {
            await performUpdateCheck()
        }
    }
    
    @MainActor
    func performUpdateCheck() async {
        do {
            // Get current version from bundle
            guard let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
                print("❌ Could not determine current version")
                return
            }
            
            print("🔄 Current version: \(currentVersion)")
            
            // Fetch latest release from GitHub
            guard let url = URL(string: "https://api.github.com/repos/kmichels/ImageIntact/releases/latest") else {
                print("❌ Invalid GitHub API URL")
                return
            }
            
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                print("❌ GitHub API request failed")
                return
            }
            
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String,
                  let publishedAtString = json["published_at"] as? String,
                  let assets = json["assets"] as? [[String: Any]],
                  let firstAsset = assets.first,
                  let downloadURL = firstAsset["browser_download_url"] as? String,
                  let fileName = firstAsset["name"] as? String,
                  let fileSize = firstAsset["size"] as? Int64 else {
                print("❌ Could not parse GitHub API response or find downloadable asset")
                return
            }
            
            // Parse published date
            let dateFormatter = ISO8601DateFormatter()
            let publishedAt = dateFormatter.date(from: publishedAtString) ?? Date()
            
            // Extract version number (remove 'v' prefix if present)
            let latestVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
            
            print("🔄 Latest version: \(latestVersion)")
            
            // Check if this version was skipped
            let skippedVersion = UserDefaults.standard.string(forKey: "skippedVersion")
            if skippedVersion == latestVersion {
                print("🔄 Version \(latestVersion) was skipped by user")
                UserDefaults.standard.set(Date(), forKey: "lastUpdateCheck")
                return
            }
            
            // Compare versions (simple string comparison should work for semantic versions)
            if latestVersion.compare(currentVersion, options: .numeric) == .orderedDescending {
                print("🎉 Update available: \(currentVersion) -> \(latestVersion)")
                
                // Get release notes
                let releaseNotes = (json["body"] as? String)?.prefix(200) ?? "Check the release notes for more details."
                
                let updateInfo = UpdateInfo(
                    version: latestVersion,
                    releaseNotes: String(releaseNotes),
                    downloadURL: downloadURL,
                    fileName: fileName,
                    fileSize: fileSize,
                    publishedAt: publishedAt
                )
                
                self.availableUpdate = updateInfo
                self.showUpdateAlert = true
            } else {
                print("✅ App is up to date")
            }
            
            // Update last check time
            UserDefaults.standard.set(Date(), forKey: "lastUpdateCheck")
            
        } catch {
            print("❌ Update check failed: \(error.localizedDescription)")
        }
    }
    
    @MainActor
    func downloadUpdate(_ update: UpdateInfo) async {
        isDownloadingUpdate = true
        downloadProgress = 0.0
        
        do {
            guard let url = URL(string: update.downloadURL) else {
                print("❌ Invalid download URL: \(update.downloadURL)")
                isDownloadingUpdate = false
                return
            }
            
            print("🔍 Download URL: \(url)")
            
            // Create download destination in Downloads folder
            let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
            let destinationURL = downloadsURL.appendingPathComponent(update.fileName)
            
            print("🎯 Destination: \(destinationURL.path)")
            
            // Remove existing file if it exists
            try? FileManager.default.removeItem(at: destinationURL)
            
            print("📥 Starting download...")
            
            // Simulate progress for user feedback (since real progress tracking requires URLSessionDownloadDelegate)
            let progressTask = Task {
                for i in 1...10 {
                    guard !Task.isCancelled else { break }
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds for slower progress
                    await MainActor.run {
                        self.downloadProgress = Double(i) / 10.0
                    }
                }
            }
            
            let (tempURL, _) = try await URLSession.shared.download(from: url)
            
            // Cancel progress simulation
            progressTask.cancel()
            await MainActor.run {
                self.downloadProgress = 1.0
            }
            
            print("✅ Downloaded to temp location: \(tempURL.path)")
            
            // Check if temp file exists and has content
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? Int64) ?? 0
            print("📦 Downloaded file size: \(fileSize) bytes")
            
            // Move from temp location to Downloads
            try FileManager.default.moveItem(at: tempURL, to: destinationURL)
            
            print("✅ Download completed: \(destinationURL.path)")
            
            // Verify the file exists at destination
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                print("✅ File confirmed at destination")
            } else {
                print("❌ File not found at destination!")
            }
            
            // Store the downloaded file path
            downloadedUpdatePath = destinationURL
            
            // Reset download state
            isDownloadingUpdate = false
            showUpdateAlert = false
            
            // Show install prompt
            showInstallPrompt(for: destinationURL, version: update.version)
            
        } catch {
            print("❌ Download failed with error: \(error)")
            print("❌ Error details: \(error.localizedDescription)")
            isDownloadingUpdate = false
            
            // Show error alert
            let alert = NSAlert()
            alert.messageText = "Download Failed"
            alert.informativeText = "Could not download the update: \(error.localizedDescription)\n\nURL: \(update.downloadURL)"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
    
    func cancelDownload() {
        // TODO: Implement download cancellation if needed
        isDownloadingUpdate = false
        showUpdateAlert = false
    }
    
    func skipVersion(_ version: String) {
        UserDefaults.standard.set(version, forKey: "skippedVersion")
    }
    
    // MARK: - Private Methods
    private func showInstallPrompt(for fileURL: URL, version: String) {
        let alert = NSAlert()
        alert.messageText = "Update Downloaded"
        alert.informativeText = """
        ImageIntact \(version) has been downloaded to your Downloads folder.
        
        To install:
        1. Quit ImageIntact
        2. Open the downloaded file: \(fileURL.lastPathComponent)
        3. Follow the installation instructions
        
        Would you like to show the file in Finder now?
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Show in Finder")
        alert.addButton(withTitle: "Later")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.selectFile(fileURL.path, inFileViewerRootedAtPath: fileURL.deletingLastPathComponent().path)
        }
    }
}