import Foundation

// MARK: - Update Protocol Definitions

/// Represents an available update
struct AppUpdate {
    let version: String
    let releaseNotes: String
    let downloadURL: URL
    let publishedDate: Date
    let minimumOSVersion: String?
    let fileSize: Int64?
    
    /// Compare versions using semantic versioning
    func isNewerThan(_ currentVersion: String) -> Bool {
        return version.compare(currentVersion, options: .numeric) == .orderedDescending
    }
}

/// Protocol for update checking providers
protocol UpdateProvider {
    /// Check for available updates
    func checkForUpdates(currentVersion: String) async throws -> AppUpdate?
    
    /// Download an update
    func downloadUpdate(_ update: AppUpdate, progress: @escaping (Double) -> Void) async throws -> URL
    
    /// Get the provider name for UI/logging
    var providerName: String { get }
}

/// Errors that can occur during update checking
enum UpdateError: LocalizedError {
    case networkError(Error)
    case invalidResponse
    case noUpdatesAvailable
    case downloadFailed(Error)
    case installationFailed(Error)
    case unsupportedPlatform
    
    var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from update server"
        case .noUpdatesAvailable:
            return "No updates available"
        case .downloadFailed(let error):
            return "Download failed: \(error.localizedDescription)"
        case .installationFailed(let error):
            return "Installation failed: \(error.localizedDescription)"
        case .unsupportedPlatform:
            return "Updates not supported on this platform"
        }
    }
}

// MARK: - Update Settings

/// Settings for update behavior
struct UpdateSettings: Codable {
    var automaticallyCheckForUpdates: Bool = true
    var checkInterval: TimeInterval = 86400 // 24 hours
    var lastCheckDate: Date?
    var skippedVersions: Set<String> = []
    
    private static let settingsKey = "ImageIntactUpdateSettings"
    
    /// Load settings from UserDefaults
    static func load() -> UpdateSettings {
        guard let data = UserDefaults.standard.data(forKey: settingsKey),
              let settings = try? JSONDecoder().decode(UpdateSettings.self, from: data) else {
            return UpdateSettings()
        }
        return settings
    }
    
    /// Save settings to UserDefaults
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: UpdateSettings.settingsKey)
        }
    }
    
    /// Check if we should check for updates
    func shouldCheckForUpdates() -> Bool {
        guard automaticallyCheckForUpdates else { return false }
        
        guard let lastCheck = lastCheckDate else { return true }
        
        return Date().timeIntervalSince(lastCheck) >= checkInterval
    }
    
    /// Mark that we've checked for updates
    mutating func markUpdateCheck() {
        lastCheckDate = Date()
        save()
    }
    
    /// Check if a version is skipped
    func isVersionSkipped(_ version: String) -> Bool {
        return skippedVersions.contains(version)
    }
    
    /// Skip a version
    mutating func skipVersion(_ version: String) {
        skippedVersions.insert(version)
        save()
    }
}