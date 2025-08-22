//
//  PreferencesTests.swift
//  ImageIntactTests
//
//  Tests for Preferences functionality
//

import XCTest
@testable import ImageIntact

final class PreferencesTests: XCTestCase {
    
    var preferencesManager: PreferencesManager!
    
    override func setUp() {
        super.setUp()
        preferencesManager = PreferencesManager.shared
        // Reset to defaults for consistent testing
        preferencesManager.resetToDefaults()
    }
    
    override func tearDown() {
        // Reset to defaults after testing
        preferencesManager.resetToDefaults()
        super.tearDown()
    }
    
    // MARK: - General Preferences Tests
    
    func testDefaultSourcePathPersistence() {
        let testPath = "/Users/test/Pictures"
        preferencesManager.defaultSourcePath = testPath
        XCTAssertEqual(preferencesManager.defaultSourcePath, testPath)
    }
    
    func testDefaultDestinationPathPersistence() {
        let testPath = "/Volumes/Backup/Photos"
        preferencesManager.defaultDestinationPath = testPath
        XCTAssertEqual(preferencesManager.defaultDestinationPath, testPath)
    }
    
    func testRestoreLastSessionDefault() {
        XCTAssertTrue(preferencesManager.restoreLastSession, "Should default to true")
        preferencesManager.restoreLastSession = false
        XCTAssertFalse(preferencesManager.restoreLastSession)
    }
    
    // MARK: - File Handling Tests
    
    func testExcludeCacheFilesDefault() {
        XCTAssertTrue(preferencesManager.excludeCacheFiles, "Should default to true")
    }
    
    func testSkipHiddenFilesDefault() {
        XCTAssertTrue(preferencesManager.skipHiddenFiles, "Should default to true")
    }
    
    func testDefaultFileTypeFilterPersistence() {
        preferencesManager.defaultFileTypeFilter = "photos"
        XCTAssertEqual(preferencesManager.defaultFileTypeFilter, "photos")
        
        preferencesManager.defaultFileTypeFilter = "raw"
        XCTAssertEqual(preferencesManager.defaultFileTypeFilter, "raw")
        
        preferencesManager.defaultFileTypeFilter = "videos"
        XCTAssertEqual(preferencesManager.defaultFileTypeFilter, "videos")
        
        preferencesManager.defaultFileTypeFilter = "all"
        XCTAssertEqual(preferencesManager.defaultFileTypeFilter, "all")
    }
    
    func testGetDefaultFileTypeFilter() {
        preferencesManager.defaultFileTypeFilter = "photos"
        let filter = preferencesManager.getDefaultFileTypeFilter()
        XCTAssertTrue(filter.isPhotosOnly)
        
        preferencesManager.defaultFileTypeFilter = "raw"
        let rawFilter = preferencesManager.getDefaultFileTypeFilter()
        XCTAssertTrue(rawFilter.isRawOnly)
        
        preferencesManager.defaultFileTypeFilter = "videos"
        let videoFilter = preferencesManager.getDefaultFileTypeFilter()
        XCTAssertTrue(videoFilter.isVideosOnly)
        
        preferencesManager.defaultFileTypeFilter = "all"
        let allFilter = preferencesManager.getDefaultFileTypeFilter()
        XCTAssertTrue(allFilter.includedExtensions.isEmpty)
    }
    
    // MARK: - Backup Confirmations Tests
    
    func testLargeBackupConfirmationDefaults() {
        XCTAssertTrue(preferencesManager.confirmLargeBackups, "Should default to true")
        XCTAssertEqual(preferencesManager.largeBackupFileThreshold, 1000)
        XCTAssertEqual(preferencesManager.largeBackupSizeThresholdGB, 10.0)
        XCTAssertFalse(preferencesManager.skipLargeBackupWarning, "Should default to false")
    }
    
    func testLargeBackupThresholdPersistence() {
        preferencesManager.largeBackupFileThreshold = 500
        XCTAssertEqual(preferencesManager.largeBackupFileThreshold, 500)
        
        preferencesManager.largeBackupSizeThresholdGB = 5.0
        XCTAssertEqual(preferencesManager.largeBackupSizeThresholdGB, 5.0)
    }
    
    // MARK: - Performance Tests
    
    func testPreventSleepDefault() {
        XCTAssertTrue(preferencesManager.preventSleepDuringBackup, "Should default to true")
    }
    
    func testShowNotificationDefault() {
        XCTAssertTrue(preferencesManager.showNotificationOnComplete, "Should default to true")
    }
    
    func testVisionFrameworkDefault() {
        // Should be based on CPU type
        let expected = SystemCapabilities.shared.isAppleSilicon
        XCTAssertEqual(preferencesManager.enableVisionFramework, expected)
    }
    
    // MARK: - Logging & Privacy Tests
    
    func testAnonymizePathsDefault() {
        XCTAssertTrue(preferencesManager.anonymizePathsInExport, "Should default to true for privacy")
    }
    
    func testMinimumLogLevelDefault() {
        XCTAssertEqual(preferencesManager.minimumLogLevel, 1, "Should default to info level")
    }
    
    func testOperationalLogRetentionDefault() {
        XCTAssertEqual(preferencesManager.operationalLogRetention, 30, "Should default to 30 days")
    }
    
    // MARK: - Advanced Tests
    
    func testShowPreflightSummaryDefault() {
        XCTAssertFalse(preferencesManager.showPreflightSummary, "Should default to false")
    }
    
    // MARK: - Reset Tests
    
    func testResetToDefaults() {
        // Change a bunch of settings
        preferencesManager.defaultSourcePath = "/test/path"
        preferencesManager.defaultDestinationPath = "/test/dest"
        preferencesManager.restoreLastSession = false
        preferencesManager.excludeCacheFiles = false
        preferencesManager.skipHiddenFiles = false
        preferencesManager.defaultFileTypeFilter = "raw"
        preferencesManager.confirmLargeBackups = false
        preferencesManager.largeBackupFileThreshold = 500
        preferencesManager.preventSleepDuringBackup = false
        preferencesManager.showNotificationOnComplete = false
        preferencesManager.anonymizePathsInExport = false
        
        // Reset
        preferencesManager.resetToDefaults()
        
        // Verify all settings are back to defaults
        XCTAssertEqual(preferencesManager.defaultSourcePath, "")
        XCTAssertEqual(preferencesManager.defaultDestinationPath, "")
        XCTAssertTrue(preferencesManager.restoreLastSession)
        XCTAssertTrue(preferencesManager.excludeCacheFiles)
        XCTAssertTrue(preferencesManager.skipHiddenFiles)
        XCTAssertEqual(preferencesManager.defaultFileTypeFilter, "all")
        XCTAssertTrue(preferencesManager.confirmLargeBackups)
        XCTAssertEqual(preferencesManager.largeBackupFileThreshold, 1000)
        XCTAssertTrue(preferencesManager.preventSleepDuringBackup)
        XCTAssertTrue(preferencesManager.showNotificationOnComplete)
        XCTAssertTrue(preferencesManager.anonymizePathsInExport)
    }
    
    // MARK: - Cache Exclusion Paths Tests
    
    func testGetCacheExclusionPaths() {
        preferencesManager.excludeCacheFiles = true
        let paths = preferencesManager.getCacheExclusionPaths()
        
        XCTAssertTrue(paths.contains("Lightroom Catalog Previews.lrdata"))
        XCTAssertTrue(paths.contains("CaptureOne"))
        XCTAssertTrue(paths.contains(".BridgeCache"))
        
        preferencesManager.excludeCacheFiles = false
        let emptyPaths = preferencesManager.getCacheExclusionPaths()
        XCTAssertTrue(emptyPaths.isEmpty)
    }
    
    func testGetHiddenFilePatterns() {
        preferencesManager.skipHiddenFiles = true
        let patterns = preferencesManager.getHiddenFilePatterns()
        
        XCTAssertTrue(patterns.contains("._*"))
        XCTAssertTrue(patterns.contains(".DS_Store"))
        XCTAssertTrue(patterns.contains("Thumbs.db"))
        
        preferencesManager.skipHiddenFiles = false
        let emptyPatterns = preferencesManager.getHiddenFilePatterns()
        XCTAssertTrue(emptyPatterns.isEmpty)
    }
}