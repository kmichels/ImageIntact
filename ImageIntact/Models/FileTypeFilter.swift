//
//  FileTypeFilter.swift
//  ImageIntact
//
//  Manages file type filtering for selective backups
//

import Foundation

/// Represents the user's file type selection for backup filtering
public struct FileTypeFilter: Codable, Equatable {
    /// Set of file extensions to include (e.g., "nef", "jpg", "mov")
    /// Empty set means include all types (no filtering)
    public var includedExtensions: Set<String>
    
    /// Human-readable description of the filter
    public var description: String {
        if includedExtensions.isEmpty {
            return "All Files"
        } else if isRawOnly {
            return "RAW Only"
        } else if isPhotosOnly {
            return "Photos Only"
        } else if isVideosOnly {
            return "Videos Only"
        } else {
            return "Custom"
        }
    }
    
    /// Initialize with no filter (all files)
    public init() {
        self.includedExtensions = []
    }
    
    /// Initialize with specific extensions
    public init(extensions: Set<String>) {
        self.includedExtensions = Set(extensions.map { $0.lowercased() })
    }
    
    /// Check if a file should be included based on its extension
    public func shouldInclude(fileURL: URL) -> Bool {
        // Empty set means include everything
        guard !includedExtensions.isEmpty else { return true }
        
        let fileExtension = fileURL.pathExtension.lowercased()
        return includedExtensions.contains(fileExtension)
    }
    
    /// Check if a file type should be included
    func shouldInclude(fileType: ImageFileType) -> Bool {
        // Empty set means include everything
        guard !includedExtensions.isEmpty else { return true }
        
        // Check if any of the type's extensions are included
        for ext in fileType.extensions {
            if includedExtensions.contains(ext.lowercased()) {
                return true
            }
        }
        return false
    }
    
    // MARK: - Preset Filters
    
    /// No filtering - include all files
    public static let allFiles = FileTypeFilter()
    
    /// RAW files only
    public static let rawOnly = FileTypeFilter(extensions: [
        "nef", "cr2", "cr3", "arw", "orf", "rw2", "dng", "raf", "raw", "rwl", "srw", "x3f"
    ])
    
    /// All photo types (RAW + processed)
    public static let photosOnly = FileTypeFilter(extensions: [
        // RAW formats
        "nef", "cr2", "cr3", "arw", "orf", "rw2", "dng", "raf", "raw", "rwl", "srw", "x3f",
        // Processed formats
        "jpg", "jpeg", "heic", "heif", "png", "tiff", "tif", "bmp", "webp"
    ])
    
    /// Video files only
    public static let videosOnly = FileTypeFilter(extensions: [
        "mov", "mp4", "avi", "mkv", "m4v", "mpg", "mpeg", "wmv", "flv", "webm", "mts", "m2ts"
    ])
    
    // MARK: - Helper Properties
    
    var isRawOnly: Bool {
        // Check if we only have RAW extensions
        !includedExtensions.isEmpty && 
        includedExtensions.isSubset(of: Self.rawOnly.includedExtensions)
    }
    
    var isPhotosOnly: Bool {
        !includedExtensions.isEmpty &&
        includedExtensions.isSubset(of: Self.photosOnly.includedExtensions) &&
        !isVideosOnly
    }
    
    var isVideosOnly: Bool {
        !includedExtensions.isEmpty &&
        includedExtensions.isSubset(of: Self.videosOnly.includedExtensions)
    }
    
    // MARK: - Filter Creation from Scan Results
    
    /// Create a filter from scan results with specific types selected
    static func from(scanResults: [ImageFileType: Int], selectedTypes: Set<ImageFileType>) -> FileTypeFilter {
        if selectedTypes.isEmpty {
            return .allFiles
        }
        
        // Collect all extensions from selected types
        var extensions = Set<String>()
        for type in selectedTypes {
            extensions.formUnion(type.extensions)
        }
        return FileTypeFilter(extensions: extensions)
    }
    
    /// Create a filter including all types from scan results (default behavior)
    static func allFrom(scanResults: [ImageFileType: Int]) -> FileTypeFilter {
        // Empty filter means include all
        return .allFiles
    }
}