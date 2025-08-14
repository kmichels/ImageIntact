import Foundation

/// Generates deterministic test data for backup testing
class TestDataGenerator {
    
    /// Creates a temporary directory structure with test files
    static func createTestEnvironment(fileCount: Int = 5, fileSize: Int = 1024) throws -> TestEnvironment {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageIntactTest_\(UUID().uuidString)")
        
        let sourceDir = tempDir.appendingPathComponent("Source")
        let destDir1 = tempDir.appendingPathComponent("Dest1")
        let destDir2 = tempDir.appendingPathComponent("Dest2")
        
        // Create directories
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destDir1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destDir2, withIntermediateDirectories: true)
        
        // Create test files with deterministic content
        var files: [TestFile] = []
        for i in 0..<fileCount {
            let fileName = String(format: "IMG_%04d.DNG", i)
            let fileURL = sourceDir.appendingPathComponent(fileName)
            
            // Create deterministic data based on index
            let data = createDeterministicData(index: i, size: fileSize)
            try data.write(to: fileURL)
            
            // Calculate checksum
            let checksum = try calculateSHA256(for: fileURL)
            
            files.append(TestFile(
                url: fileURL,
                name: fileName,
                size: fileSize,
                checksum: checksum
            ))
        }
        
        return TestEnvironment(
            tempDirectory: tempDir,
            sourceDirectory: sourceDir,
            destinationDirectories: [destDir1, destDir2],
            testFiles: files
        )
    }
    
    /// Creates deterministic data for a file
    private static func createDeterministicData(index: Int, size: Int) -> Data {
        var data = Data(capacity: size)
        
        // Fill with repeating pattern based on index
        let pattern = "TestFile\(index)_".data(using: .utf8)!
        while data.count < size {
            data.append(pattern)
        }
        
        // Trim to exact size
        return data.prefix(size)
    }
    
    /// Calculate SHA-256 checksum
    private static func calculateSHA256(for url: URL) throws -> String {
        // Use the same checksum method as BackupManager
        let task = Process()
        task.launchPath = "/usr/bin/shasum"
        task.arguments = ["-a", "256", url.path]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.launch()
        task.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            throw TestError.checksumFailed
        }
        
        return String(output.prefix(64))
    }
    
    /// Cleanup test environment
    static func cleanup(_ environment: TestEnvironment) {
        try? FileManager.default.removeItem(at: environment.tempDirectory)
    }
}

/// Test environment containing all test resources
struct TestEnvironment {
    let tempDirectory: URL
    let sourceDirectory: URL
    let destinationDirectories: [URL]
    let testFiles: [TestFile]
    
    func cleanup() {
        TestDataGenerator.cleanup(self)
    }
}

/// Represents a test file
struct TestFile {
    let url: URL
    let name: String
    let size: Int
    let checksum: String
}

enum TestError: Error {
    case checksumFailed
    case fileCreationFailed
}