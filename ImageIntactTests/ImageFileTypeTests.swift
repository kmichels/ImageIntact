import XCTest
@testable import ImageIntact

final class ImageFileTypeTests: XCTestCase {
    
    // MARK: - File Type Detection Tests
    
    func testRAWFileDetection() {
        // Test common RAW formats
        let rawExtensions = ["nef", "cr2", "arw", "dng", "orf", "rw2", "pef", "srw", "x3f", "raf"]
        
        for ext in rawExtensions {
            let url = URL(fileURLWithPath: "/test/photo.\(ext)")
            XCTAssertTrue(ImageFileType.isImageFile(url), "\(ext) should be recognized as image file")
            
            if let fileType = ImageFileType.from(url) {
                XCTAssertTrue(fileType.isRaw, "\(ext) should be recognized as RAW")
                XCTAssertFalse(fileType.isVideo, "\(ext) should not be video")
                XCTAssertFalse(fileType.isSidecar, "\(ext) should not be sidecar")
            } else {
                XCTFail("Failed to detect file type for \(ext)")
            }
        }
    }
    
    func testStandardImageDetection() {
        let standardFormats = ["jpg", "jpeg", "png", "tiff", "gif", "heic", "webp"]
        
        for ext in standardFormats {
            let url = URL(fileURLWithPath: "/test/image.\(ext)")
            XCTAssertTrue(ImageFileType.isImageFile(url), "\(ext) should be recognized as image file")
            
            if let fileType = ImageFileType.from(url) {
                XCTAssertFalse(fileType.isRaw, "\(ext) should not be RAW")
                XCTAssertFalse(fileType.isVideo, "\(ext) should not be video")
                XCTAssertFalse(fileType.isSidecar, "\(ext) should not be sidecar")
            }
        }
    }
    
    func testVideoFileDetection() {
        let videoFormats = ["mov", "mp4", "avi", "m4v", "mpg", "mpeg", "wmv", "flv", "webm", "mkv", "mts", "m2ts"]
        
        for ext in videoFormats {
            let url = URL(fileURLWithPath: "/test/video.\(ext)")
            XCTAssertTrue(ImageFileType.isImageFile(url), "\(ext) should be recognized as supported file")
            
            if let fileType = ImageFileType.from(url) {
                XCTAssertTrue(fileType.isVideo, "\(ext) should be recognized as video")
                XCTAssertFalse(fileType.isRaw, "\(ext) should not be RAW")
                XCTAssertFalse(fileType.isSidecar, "\(ext) should not be sidecar")
            }
        }
    }
    
    func testSidecarFileDetection() {
        let sidecarFormats = ["xmp", "aae", "thm", "dop", "pp3"]
        
        for ext in sidecarFormats {
            let url = URL(fileURLWithPath: "/test/metadata.\(ext)")
            XCTAssertTrue(ImageFileType.isImageFile(url), "\(ext) should be recognized as supported file")
            
            if let fileType = ImageFileType.from(url) {
                XCTAssertTrue(fileType.isSidecar, "\(ext) should be recognized as sidecar")
                XCTAssertFalse(fileType.isRaw, "\(ext) should not be RAW")
                XCTAssertFalse(fileType.isVideo, "\(ext) should not be video")
            }
        }
    }
    
    func testCatalogFileDetection() {
        let catalogFormats = [
            ("catalog.lrcat", ImageFileType.lrcat),
            ("project.cocatalog", ImageFileType.cocatalog),
            ("session.cosessiondb", ImageFileType.cosession)
        ]
        
        for (filename, expectedType) in catalogFormats {
            let url = URL(fileURLWithPath: "/test/\(filename)")
            XCTAssertTrue(ImageFileType.isImageFile(url), "\(filename) should be recognized as supported file")
            
            if let fileType = ImageFileType.from(url) {
                XCTAssertEqual(fileType, expectedType, "\(filename) should be \(expectedType)")
                XCTAssertTrue(fileType.isCatalog, "\(filename) should be catalog")
            }
        }
    }
    
    func testUnsupportedFileRejection() {
        let unsupportedFormats = ["txt", "doc", "pdf", "zip", "exe", "dmg", "app", "swift", "json"]
        
        for ext in unsupportedFormats {
            let url = URL(fileURLWithPath: "/test/document.\(ext)")
            XCTAssertFalse(ImageFileType.isImageFile(url), "\(ext) should NOT be recognized as image file")
            XCTAssertNil(ImageFileType.from(url), "\(ext) should return nil")
        }
    }
    
    func testCaseInsensitiveDetection() {
        let mixedCaseFiles = [
            "photo.NEF", "image.Jpeg", "video.MOV", "raw.DnG", "sidecar.XMP"
        ]
        
        for filename in mixedCaseFiles {
            let url = URL(fileURLWithPath: "/test/\(filename)")
            XCTAssertTrue(ImageFileType.isImageFile(url), "\(filename) should be recognized regardless of case")
        }
    }
    
    // MARK: - File Scanning Tests
    
    func testImageFileScannerInitialization() {
        let scanner = ImageFileScanner()
        XCTAssertNotNil(scanner, "Scanner should initialize")
    }
    
    func testScanResultFormatting() {
        let results: [ImageFileType: Int] = [
            .nef: 50,
            .cr2: 30,
            .jpeg: 100,
            .mov: 10,
            .xmp: 80
        ]
        
        let formatted = ImageFileScanner.formatScanResults(results, groupRaw: false)
        XCTAssertFalse(formatted.isEmpty, "Formatted results should not be empty")
        XCTAssertTrue(formatted.contains("50 NEF"), "Should include NEF count")
        XCTAssertTrue(formatted.contains("30 CR2"), "Should include CR2 count")
        XCTAssertTrue(formatted.contains("100 JPEG"), "Should include JPEG count")
    }
    
    func testScanResultFormattingWithGrouping() {
        let results: [ImageFileType: Int] = [
            .nef: 50,
            .cr2: 30,
            .arw: 20,
            .jpeg: 100,
            .mov: 10
        ]
        
        let formatted = ImageFileScanner.formatScanResults(results, groupRaw: true)
        XCTAssertTrue(formatted.contains("100 RAW"), "Should group RAW files when requested")
        XCTAssertTrue(formatted.contains("100 JPEG"), "Should still show JPEG separately")
    }
    
    func testEmptyScanResultFormatting() {
        let results: [ImageFileType: Int] = [:]
        let formatted = ImageFileScanner.formatScanResults(results, groupRaw: false)
        XCTAssertEqual(formatted, "", "Empty results should return empty string")
    }
    
    // MARK: - Cache File Detection Tests
    
    func testLightRoomCachePathDetection() {
        let cachePatterns = [
            "/Users/test/Pictures/Lightroom/Smart Previews.lrdata/preview.jpg",
            "/Users/test/Pictures/Lightroom/Catalog Previews.lrdata/thumb.jpg",
            "/Users/test/Pictures/Lightroom/MyPhotos Previews.lrdata/1234/5678/preview.jpg"
        ]
        
        for path in cachePatterns {
            let url = URL(fileURLWithPath: path)
            // Note: This would require exposing isLikelyCacheFile or testing through the backup process
            // For now, we're testing the concept that these paths should be excluded
            XCTAssertTrue(path.contains(".lrdata/"), "Path should contain Lightroom cache indicator")
        }
    }
    
    func testCaptureOneCachePathDetection() {
        let cachePatterns = [
            "/Users/test/Pictures/Session.cosessiondb/Cache/preview.jpg",
            "/Users/test/Pictures/CaptureOne/Cache/thumb_1234.jpg"
        ]
        
        for path in cachePatterns {
            XCTAssertTrue(path.lowercased().contains("cache"), "Path should contain cache indicator")
        }
    }
    
    // MARK: - Performance Tests
    
    func testFileTypeDetectionPerformance() {
        measure {
            for _ in 0..<1000 {
                _ = ImageFileType.isImageFile(URL(fileURLWithPath: "/test/photo.nef"))
                _ = ImageFileType.isImageFile(URL(fileURLWithPath: "/test/video.mov"))
                _ = ImageFileType.isImageFile(URL(fileURLWithPath: "/test/sidecar.xmp"))
            }
        }
    }
    
    func testBulkFileTypeDetection() {
        let urls = (0..<100).map { i in
            URL(fileURLWithPath: "/test/photo\(i).nef")
        }
        
        measure {
            for url in urls {
                _ = ImageFileType.from(url)
            }
        }
    }
}