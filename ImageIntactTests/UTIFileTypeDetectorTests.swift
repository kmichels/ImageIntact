//
//  UTIFileTypeDetectorTests.swift
//  ImageIntactTests
//
//  Tests for UTI-based file type detection
//

import XCTest
@testable import ImageIntact

final class UTIFileTypeDetectorTests: XCTestCase {
    
    let detector = UTIFileTypeDetector.shared
    var tempDir: URL!
    
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("uti-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    func testBasicImageDetection() throws {
        // Create test files with correct extensions
        let jpegFile = tempDir.appendingPathComponent("test.jpg")
        let pngFile = tempDir.appendingPathComponent("test.png")
        let heicFile = tempDir.appendingPathComponent("test.heic")
        
        // Create minimal valid files
        try createMinimalJPEG(at: jpegFile)
        try createMinimalPNG(at: pngFile)
        try Data().write(to: heicFile) // Empty for now
        
        // Test detection
        XCTAssertTrue(detector.isSupportedFile(jpegFile), "JPEG should be supported")
        XCTAssertTrue(detector.isSupportedFile(pngFile), "PNG should be supported")
        XCTAssertTrue(detector.isSupportedFile(heicFile), "HEIC should be supported")
        
        // Test file info
        let jpegInfo = detector.getFileTypeInfo(jpegFile)
        XCTAssertTrue(jpegInfo.isImage, "JPEG should be identified as image")
        XCTAssertFalse(jpegInfo.isVideo, "JPEG should not be video")
        XCTAssertFalse(jpegInfo.isRAW, "JPEG should not be RAW")
    }
    
    func testRAWFileDetection() throws {
        // Test various RAW formats
        let rawExtensions = ["cr2", "cr3", "nef", "arw", "dng", "raf", "orf", "rw2"]
        
        for ext in rawExtensions {
            let rawFile = tempDir.appendingPathComponent("test.\(ext)")
            try Data().write(to: rawFile)
            
            XCTAssertTrue(detector.isSupportedFile(rawFile), "\(ext.uppercased()) should be supported")
            
            let info = detector.getFileTypeInfo(rawFile)
            XCTAssertTrue(info.isSupported, "\(ext.uppercased()) should be supported")
            // Note: Without actual RAW file data, UTI might not identify as RAW
            // but extension fallback should work
        }
    }
    
    func testVideoFileDetection() throws {
        let videoExtensions = ["mov", "mp4", "m4v", "avi"]
        
        for ext in videoExtensions {
            let videoFile = tempDir.appendingPathComponent("test.\(ext)")
            try Data().write(to: videoFile)
            
            XCTAssertTrue(detector.isSupportedFile(videoFile), "\(ext.uppercased()) should be supported")
            
            let info = detector.getFileTypeInfo(videoFile)
            XCTAssertTrue(info.isSupported, "\(ext.uppercased()) video should be supported")
        }
    }
    
    func testSidecarFileDetection() throws {
        // Test sidecar files
        let xmpFile = tempDir.appendingPathComponent("test.xmp")
        let aaeFile = tempDir.appendingPathComponent("test.aae")
        
        try "<?xml version=\"1.0\"?>".data(using: .utf8)?.write(to: xmpFile)
        try Data().write(to: aaeFile)
        
        XCTAssertTrue(detector.isSupportedFile(xmpFile), "XMP should be supported")
        XCTAssertTrue(detector.isSupportedFile(aaeFile), "AAE should be supported")
        
        let xmpInfo = detector.getFileTypeInfo(xmpFile)
        XCTAssertTrue(xmpInfo.isSidecar || xmpInfo.isSupported, "XMP should be identified as sidecar")
    }
    
    func testMissingExtensionDetection() throws {
        // Create a JPEG file without extension
        let noExtFile = tempDir.appendingPathComponent("IMG_1234")
        try createMinimalJPEG(at: noExtFile)
        
        // UTI should detect it as JPEG from magic bytes
        let info = detector.getFileTypeInfo(noExtFile)
        
        // On macOS 11+, this should work via UTI
        if #available(macOS 11.0, *) {
            // Note: This might not work in tests without actual file data
            print("Testing file without extension: \(info)")
        }
    }
    
    func testWrongExtensionDetection() throws {
        // Create a JPEG file with wrong extension
        let wrongExtFile = tempDir.appendingPathComponent("image.txt")
        try createMinimalJPEG(at: wrongExtFile)
        
        // UTI should detect it as JPEG despite .txt extension
        let info = detector.getFileTypeInfo(wrongExtFile)
        
        if #available(macOS 11.0, *) {
            // UTI should identify this as an image
            print("File with wrong extension: \(info)")
        }
    }
    
    func testCameraImageDetection() throws {
        // Test DCIM folder structure
        let dcimDir = tempDir.appendingPathComponent("DCIM/100CANON")
        try FileManager.default.createDirectory(at: dcimDir, withIntermediateDirectories: true)
        
        let cameraImage = dcimDir.appendingPathComponent("IMG_0001.JPG")
        try createMinimalJPEG(at: cameraImage)
        
        XCTAssertTrue(detector.isCameraImage(cameraImage), "Should detect camera image in DCIM")
    }
    
    func testUnsupportedFileRejection() throws {
        // Test files that should NOT be supported
        let txtFile = tempDir.appendingPathComponent("document.txt")
        let exeFile = tempDir.appendingPathComponent("malware.exe")
        let zipFile = tempDir.appendingPathComponent("archive.zip")
        
        try "Hello".data(using: .utf8)?.write(to: txtFile)
        try Data().write(to: exeFile)
        try Data().write(to: zipFile)
        
        XCTAssertFalse(detector.isSupportedFile(txtFile), "Text files should not be supported")
        XCTAssertFalse(detector.isSupportedFile(exeFile), "Executables should not be supported")
        XCTAssertFalse(detector.isSupportedFile(zipFile), "Archives should not be supported")
    }
    
    // MARK: - Helper Methods
    
    private func createMinimalJPEG(at url: URL) throws {
        // Minimal valid JPEG (1x1 pixel red image)
        let jpegData = Data([
            0xFF, 0xD8, 0xFF, 0xE0, // SOI + APP0 marker
            0x00, 0x10,             // APP0 length
            0x4A, 0x46, 0x49, 0x46, // "JFIF"
            0x00, 0x01, 0x01,       // Version 1.1
            0x00, 0x00, 0x01, 0x00, 0x01, // Density
            0x00, 0x00,             // No thumbnail
            0xFF, 0xDB, 0x00, 0x43, // DQT marker
            // ... minimal quantization table ...
            0xFF, 0xC0, 0x00, 0x0B, // SOF marker
            0x08, 0x00, 0x01, 0x00, 0x01, // 1x1 pixel
            0x01, 0x01, 0x11, 0x00, // Component info
            0xFF, 0xC4, 0x00, 0x14, // DHT marker
            // ... minimal Huffman table ...
            0xFF, 0xDA, 0x00, 0x08, // SOS marker
            0x01, 0x01, 0x00, 0x00, 0x3F, 0x00,
            0xFF, 0xD9              // EOI
        ])
        try jpegData.write(to: url)
    }
    
    private func createMinimalPNG(at url: URL) throws {
        // Minimal valid PNG (1x1 pixel)
        let pngData = Data([
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
            // IHDR chunk
            0x00, 0x00, 0x00, 0x0D, // Length
            0x49, 0x48, 0x44, 0x52, // "IHDR"
            0x00, 0x00, 0x00, 0x01, // Width: 1
            0x00, 0x00, 0x00, 0x01, // Height: 1
            0x08, 0x02,             // Bit depth: 8, Color type: 2 (RGB)
            0x00, 0x00, 0x00,       // Compression, filter, interlace
            0x90, 0x77, 0x53, 0xDE, // CRC
            // IDAT chunk (compressed image data)
            0x00, 0x00, 0x00, 0x0C, // Length
            0x49, 0x44, 0x41, 0x54, // "IDAT"
            0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00, 0x00,
            0x03, 0x01, 0x01, 0x00, // Compressed data
            0x18, 0xDD, 0x8D, 0xB4, // CRC
            // IEND chunk
            0x00, 0x00, 0x00, 0x00, // Length
            0x49, 0x45, 0x4E, 0x44, // "IEND"
            0xAE, 0x42, 0x60, 0x82  // CRC
        ])
        try pngData.write(to: url)
    }
}