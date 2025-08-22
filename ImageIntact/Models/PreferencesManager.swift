//
//  PreferencesManager.swift
//  ImageIntact
//
//  Manages application preferences and settings
//

import Foundation
import SwiftUI

class PreferencesManager: ObservableObject {
    static let shared = PreferencesManager()
    
    // MARK: - General Preferences
    
    @AppStorage("defaultSourcePath") var defaultSourcePath: String = ""
    @AppStorage("defaultDestinationPath") var defaultDestinationPath: String = ""
    @AppStorage("restoreLastSession") var restoreLastSession: Bool = true
    @AppStorage("showWelcomeOnLaunch") var showWelcomeOnLaunch: Bool = true
    
    // MARK: - File Handling
    
    @AppStorage("excludeCacheFiles") var excludeCacheFiles: Bool = true
    @AppStorage("skipHiddenFiles") var skipHiddenFiles: Bool = true
    @AppStorage("defaultFileTypeFilter") var defaultFileTypeFilter: String = "all" // all, photos, raw, videos
    
    // MARK: - Backup Confirmations
    
    @AppStorage("confirmLargeBackups") var confirmLargeBackups: Bool = true
    @AppStorage("largeBackupFileThreshold") var largeBackupFileThreshold: Int = 1000 // files
    @AppStorage("largeBackupSizeThresholdGB") var largeBackupSizeThresholdGB: Double = 10.0 // GB
    @AppStorage("skipLargeBackupWarning") var skipLargeBackupWarning: Bool = false
    
    // MARK: - Performance
    
    @AppStorage("enableVisionFramework") private var enableVisionFrameworkStorage: Bool?
    
    var enableVisionFramework: Bool {
        get {
            // If user hasn't set preference, use smart default based on CPU
            if let userChoice = enableVisionFrameworkStorage {
                return userChoice
            }
            // Default: enabled for Apple Silicon, disabled for Intel
            return SystemCapabilities.shared.isAppleSilicon
        }
        set {
            enableVisionFrameworkStorage = newValue
        }
    }
    
    @AppStorage("visionProcessingPriority") var visionProcessingPriority: String = "normal" // low, normal, high
    @AppStorage("preventSleepDuringBackup") var preventSleepDuringBackup: Bool = true
    @AppStorage("showNotificationOnComplete") var showNotificationOnComplete: Bool = true
    
    // MARK: - Logging & Privacy
    
    @AppStorage("minimumLogLevel") var minimumLogLevel: Int = 1 // Maps to LogLevel.info
    @AppStorage("enableConsoleLogging") var enableConsoleLogging: Bool = true
    @AppStorage("enableDebugMenu") var enableDebugMenu: Bool = false
    @AppStorage("operationalLogRetention") var operationalLogRetention: Int = 30 // days
    @AppStorage("anonymizePathsInExport") var anonymizePathsInExport: Bool = true
    
    // MARK: - Advanced
    
    @AppStorage("enableSmartDuplicateDetection") var enableSmartDuplicateDetection: Bool = false
    @AppStorage("showTechnicalDetails") var showTechnicalDetails: Bool = false
    @AppStorage("showPreflightSummary") var showPreflightSummary: Bool = false
    
    // MARK: - Helper Methods
    
    func resetToDefaults() {
        // General
        defaultSourcePath = ""
        defaultDestinationPath = ""
        restoreLastSession = true
        showWelcomeOnLaunch = true
        
        // File Handling
        excludeCacheFiles = true
        skipHiddenFiles = true
        defaultFileTypeFilter = "all"
        
        // Performance
        enableVisionFrameworkStorage = nil // Reset to CPU-based default
        visionProcessingPriority = "normal"
        preventSleepDuringBackup = true
        showNotificationOnComplete = true
        
        // Logging
        minimumLogLevel = 1
        enableConsoleLogging = true
        enableDebugMenu = false
        operationalLogRetention = 30
        anonymizePathsInExport = true
        
        // Advanced
        enableSmartDuplicateDetection = false
        showTechnicalDetails = false
        showPreflightSummary = false
        
        // Backup Confirmations
        confirmLargeBackups = true
        largeBackupFileThreshold = 1000
        largeBackupSizeThresholdGB = 10.0
        skipLargeBackupWarning = false
    }
    
    func getDefaultFileTypeFilter() -> FileTypeFilter {
        switch defaultFileTypeFilter {
        case "photos":
            return .photosOnly
        case "raw":
            return .rawOnly
        case "videos":
            return .videosOnly
        default:
            return .allFiles
        }
    }
    
    func shouldWarnAboutVisionPerformance() -> Bool {
        // Warn Intel users about enabling Vision
        if !SystemCapabilities.shared.isAppleSilicon && enableVisionFramework {
            return true
        }
        return false
    }
    
    func getCacheExclusionPaths() -> [String] {
        guard excludeCacheFiles else { return [] }
        
        return [
            // Lightroom
            "Lightroom Catalog Previews.lrdata",
            "Lightroom Catalog Smart Previews.lrdata",
            // Capture One
            "CaptureOne",
            "Capture One Catalog.cocatalogdb",
            // Photo Mechanic
            ".pmarker",
            // DxO
            "DxO PhotoLab",
            // Apple Photos
            "Photos Library.photoslibrary",
            // Bridge
            ".BridgeCache",
            ".BridgeCacheT"
        ]
    }
    
    func getHiddenFilePatterns() -> [String] {
        guard skipHiddenFiles else { return [] }
        
        return [
            "._*",      // macOS resource forks
            ".DS_Store", // macOS folder metadata
            "Thumbs.db", // Windows thumbnails
            ".Spotlight-V100",
            ".Trashes",
            ".fseventsd",
            ".TemporaryItems"
        ]
    }
}