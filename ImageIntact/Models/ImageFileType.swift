//
//  ImageFileType.swift
//  ImageIntact
//
//  Image file type definitions and recognition
//

import Foundation

enum ImageFileType: String, CaseIterable {
    // Standard image formats
    case jpeg = "JPEG"
    case tiff = "TIFF"
    case png = "PNG"
    case heic = "HEIC"
    case heif = "HEIF"
    case webp = "WebP"
    case bmp = "BMP"
    case gif = "GIF"
    
    // Video formats
    case mov = "MOV"
    case mp4 = "MP4"
    case avi = "AVI"
    case m4v = "M4V"
    case mpg = "MPG"
    case mts = "MTS"  // AVCHD
    case m2ts = "M2TS"  // AVCHD
    case wmv = "WMV"
    case flv = "FLV"
    case webm = "WebM"
    case mkv = "MKV"
    case mpeg = "MPEG"
    
    // Sidecar and metadata files
    case xmp = "XMP"  // Adobe sidecar
    case aae = "AAE"  // Apple sidecar
    case thm = "THM"  // Thumbnail file
    case dop = "DOP"  // DxO PhotoLab
    case cos = "COS"  // Capture One settings
    case pp3 = "PP3"  // RawTherapee
    case arp = "ARP"  // Adobe Camera Raw
    case lrcat = "LR Catalog"  // Lightroom catalog
    case lrdata = "LR Data"  // Lightroom data
    case cocatalog = "C1 Catalog"  // Capture One catalog
    case cocatalogdb = "C1 Database"  // Capture One catalog database
    
    // Adobe/Generic RAW
    case dng = "DNG"
    
    // Canon
    case cr2 = "CR2"
    case cr3 = "CR3"
    case crw = "CRW"
    
    // Nikon
    case nef = "NEF"
    case nrw = "NRW"
    
    // Sony
    case arw = "ARW"
    case srf = "SRF"
    case sr2 = "SR2"
    
    // Samsung
    case srw = "SRW"
    
    // Fujifilm
    case raf = "RAF"
    
    // Olympus
    case orf = "ORF"
    
    // Panasonic
    case rw2 = "RW2"
    case raw = "RAW"  // Panasonic/Leica
    
    // Pentax
    case pef = "PEF"
    case ptx = "PTX"  // Pentax
    
    // Leica
    case rwl = "RWL"
    
    // Hasselblad
    case fff = "FFF"
    case x3f = "X3F"  // Also Sigma
    
    // Phase One
    case iiq = "IIQ"
    
    // Other professional formats
    case mef = "MEF"  // Mamiya
    case mos = "MOS"  // Leaf
    case dcr = "DCR"  // Kodak
    case kdc = "KDC"  // Kodak
    case erf = "ERF"  // Epson
    case mrw = "MRW"  // Minolta
    
    var extensions: Set<String> {
        switch self {
        case .jpeg:
            return ["jpg", "jpeg", "jpe", "jfif"]
        case .tiff:
            return ["tif", "tiff"]
        case .png:
            return ["png"]
        case .heic:
            return ["heic"]
        case .heif:
            return ["heif"]
        case .webp:
            return ["webp"]
        case .bmp:
            return ["bmp"]
        case .gif:
            return ["gif"]
        // Video formats
        case .mov:
            return ["mov", "qt"]
        case .mp4:
            return ["mp4", "m4v", "mp4v"]
        case .avi:
            return ["avi"]
        case .m4v:
            return ["m4v"]
        case .mpg:
            return ["mpg", "mpeg", "mpe", "m2v"]
        case .mts:
            return ["mts", "m2t"]
        case .m2ts:
            return ["m2ts"]
        // Sidecar files
        case .xmp:
            return ["xmp"]
        case .dop:
            return ["dop"]
        case .cos:
            return ["cos", "cosessiondb"]
        case .pp3:
            return ["pp3"]
        case .arp:
            return ["arp"]
        case .lrcat:
            return ["lrcat", "lrcat-data"]
        case .lrdata:
            return ["lrdata"]
        case .cocatalog:
            return ["cocatalog"]
        case .cocatalogdb:
            return ["cocatalogdb"]
        // RAW formats
        case .dng:
            return ["dng"]
        case .ptx:
            return ["ptx"]
        case .cr2:
            return ["cr2"]
        case .cr3:
            return ["cr3"]
        case .crw:
            return ["crw"]
        case .nef:
            return ["nef"]
        case .nrw:
            return ["nrw"]
        case .arw:
            return ["arw"]
        case .srf:
            return ["srf"]
        case .sr2:
            return ["sr2"]
        case .raf:
            return ["raf"]
        case .orf:
            return ["orf"]
        case .rw2:
            return ["rw2"]
        case .raw:
            return ["raw"]
        case .pef:
            return ["pef"]
        case .rwl:
            return ["rwl"]
        case .fff:
            return ["fff"]
        case .x3f:
            return ["x3f"]
        case .iiq:
            return ["iiq"]
        case .mef:
            return ["mef"]
        case .mos:
            return ["mos"]
        case .dcr:
            return ["dcr"]
        case .kdc:
            return ["kdc"]
        case .erf:
            return ["erf"]
        case .mrw:
            return ["mrw"]
        case .srw:
            return ["srw"]
        case .wmv:
            return ["wmv"]
        case .flv:
            return ["flv", "f4v", "f4p"]
        case .webm:
            return ["webm"]
        case .mkv:
            return ["mkv"]
        case .mpeg:
            return ["mpeg", "mpg", "mpe"]
        case .aae:
            return ["aae"]
        case .thm:
            return ["thm"]
        }
    }
    
    var isRaw: Bool {
        switch self {
        case .jpeg, .tiff, .png, .heic, .heif, .webp, .bmp, .gif,
             .mov, .mp4, .avi, .m4v, .mpg, .mts, .m2ts, .wmv, .flv, .webm, .mkv, .mpeg,
             .xmp, .dop, .cos, .pp3, .arp, .aae, .thm, .lrcat, .lrdata, .cocatalog, .cocatalogdb:
            return false
        default:
            return true
        }
    }
    
    var isVideo: Bool {
        switch self {
        case .mov, .mp4, .avi, .m4v, .mpg, .mts, .m2ts, .wmv, .flv, .webm, .mkv, .mpeg:
            return true
        default:
            return false
        }
    }
    
    var isSidecar: Bool {
        switch self {
        case .xmp, .dop, .cos, .pp3, .arp, .aae, .thm, .lrcat, .lrdata, .cocatalog, .cocatalogdb:
            return true
        default:
            return false
        }
    }
    
    var displayName: String {
        if isRaw {
            return "RAW (\(rawValue))"
        } else if isVideo {
            return "Video (\(rawValue))"
        } else if isSidecar {
            return rawValue  // Keep simple for sidecars
        }
        return rawValue
    }
    
    var folderName: String {
        // For organizing into subfolders
        return rawValue
    }
    
    // Average file size in bytes (rough estimates for pre-backup calculation)
    var averageFileSize: Int {
        switch self {
        // RAW files are typically large
        case .dng, .cr2, .cr3, .nef, .arw, .orf, .rw2, .raf, .pef, .srw, .erf, .crw, .raw:
            return 25_000_000  // ~25 MB average for modern RAW files
        case .nrw, .rwl, .iiq, .mos, .dcr, .mef, .mrw, .kdc, .srf, .sr2, .ptx, .fff, .x3f:
            return 20_000_000  // ~20 MB for these RAW formats
            
        // Standard images
        case .jpeg:
            return 2_000_000   // ~2 MB for typical JPEG
        case .heic, .heif:
            return 1_500_000   // ~1.5 MB (more efficient than JPEG)
        case .tiff:
            return 10_000_000  // ~10 MB (varies widely)
        case .png:
            return 3_000_000   // ~3 MB
        case .webp:
            return 1_000_000   // ~1 MB
        case .bmp:
            return 5_000_000   // ~5 MB (uncompressed)
        case .gif:
            return 500_000     // ~500 KB
            
        // Video files (much more realistic sizes)
        case .mov, .mp4:
            return 50_000_000  // ~50 MB for typical video clips
        case .avi, .mpg, .mpeg:
            return 30_000_000  // ~30 MB
        case .mts, .m2ts:
            return 40_000_000  // ~40 MB (AVCHD)
        case .m4v, .wmv, .flv, .webm, .mkv:
            return 20_000_000  // ~20 MB
            
        // Sidecar files are small
        case .xmp, .aae, .dop, .cos, .pp3, .arp:
            return 50_000     // ~50 KB
        case .thm:
            return 100_000    // ~100 KB (thumbnail)
            
        // Catalog files can be large
        case .lrcat, .cocatalog:
            return 100_000_000 // ~100 MB
        case .lrdata, .cocatalogdb:
            return 500_000_000 // ~500 MB (can be huge)
        }
    }
    
    static func from(fileExtension ext: String) -> ImageFileType? {
        let lowercased = ext.lowercased()
        for type in ImageFileType.allCases {
            if type.extensions.contains(lowercased) {
                return type
            }
        }
        return nil
    }
    
    static func isSupportedFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return from(fileExtension: ext) != nil
    }
    
    // Keep for compatibility
    static func isImageFile(_ url: URL) -> Bool {
        return isSupportedFile(url)
    }
}

// File scanner for analyzing source folders
class ImageFileScanner {
    struct ScanInfo {
        let count: Int
        let totalBytes: Int64
    }
    
    typealias ScanResult = [ImageFileType: Int]
    typealias DetailedScanResult = (fileTypes: [ImageFileType: Int], totalBytes: Int64)
    typealias ScanProgress = (scanned: Int, total: Int?, currentPath: String)
    
    private var currentTask: Task<ScanResult, Error>?
    private var currentDetailedTask: Task<DetailedScanResult, Error>?
    
    func scan(directory: URL, 
              progress: @escaping (ScanProgress) -> Void) async throws -> ScanResult {
        // Cancel any existing scan
        currentTask?.cancel()
        
        let task = Task<ScanResult, Error> {
            var results = ScanResult()
            var scannedCount = 0
            
            let resourceKeys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .fileSizeKey]
            
            guard let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: resourceKeys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                throw NSError(domain: "ImageFileScanner", code: 1, 
                            userInfo: [NSLocalizedDescriptionKey: "Failed to create enumerator"])
            }
            
            while let element = enumerator.nextObject() {
                guard let url = element as? URL else { continue }
                
                try Task.checkCancellation()
                
                let resourceValues = try url.resourceValues(forKeys: Set(resourceKeys))
                
                guard resourceValues.isRegularFile == true else { continue }
                
                if let fileType = ImageFileType.from(fileExtension: url.pathExtension) {
                    results[fileType, default: 0] += 1
                }
                
                scannedCount += 1
                if scannedCount % 100 == 0 {
                    progress((scanned: scannedCount, total: nil, currentPath: url.lastPathComponent))
                }
            }
            
            return results
        }
        
        currentTask = task
        return try await task.value
    }
    
    func scanWithSize(directory: URL, 
                      progress: @escaping (ScanProgress) -> Void) async throws -> DetailedScanResult {
        // Cancel any existing scan
        currentTask?.cancel()
        
        var fileTypes = ScanResult()
        var totalBytes: Int64 = 0
        var scannedCount = 0
        
        let resourceKeys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .fileSizeKey]
        
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw NSError(domain: "ImageFileScanner", code: 1, 
                        userInfo: [NSLocalizedDescriptionKey: "Failed to create enumerator"])
        }
        
        while let element = enumerator.nextObject() {
            guard let url = element as? URL else { continue }
            
            try Task.checkCancellation()
            
            let resourceValues = try url.resourceValues(forKeys: Set(resourceKeys))
            
            guard resourceValues.isRegularFile == true else { continue }
            
            if let fileType = ImageFileType.from(fileExtension: url.pathExtension) {
                fileTypes[fileType, default: 0] += 1
                
                // Add file size to total
                if let fileSize = resourceValues.fileSize {
                    totalBytes += Int64(fileSize)
                }
            }
            
            scannedCount += 1
            if scannedCount % 100 == 0 {
                progress((scanned: scannedCount, total: nil, currentPath: url.lastPathComponent))
            }
        }
        
        return (fileTypes, totalBytes)
    }
    
    func cancel() {
        currentTask?.cancel()
        currentDetailedTask?.cancel()
    }
    
    // Helper to get a nice summary string
    static func formatScanResults(_ results: ScanResult, groupRaw: Bool = false) -> String {
        if results.isEmpty {
            return "No supported files found"
        }
        
        // Group counts by category
        var rawCount = 0
        var videoCount = 0
        var sidecarCount = 0
        var imageCount = 0
        var imageCounts: [(ImageFileType, Int)] = []
        
        for (type, count) in results {
            if type.isRaw {
                rawCount += count
            } else if type.isVideo {
                videoCount += count
            } else if type.isSidecar {
                sidecarCount += count
            } else {
                imageCount += count
                imageCounts.append((type, count))
            }
        }
        
        var parts: [String] = []
        
        // Add counts in priority order
        if rawCount > 0 {
            parts.append("\(rawCount.formatted()) RAW")
        }
        
        // Show top image formats
        for (type, count) in imageCounts.sorted(by: { $0.1 > $1.1 }).prefix(2) {
            parts.append("\(count.formatted()) \(type.rawValue)")
        }
        
        if videoCount > 0 {
            parts.append("\(videoCount.formatted()) Video")
        }
        
        if sidecarCount > 0 {
            parts.append("\(sidecarCount.formatted()) Sidecar")
        }
        
        // Limit to 5 parts total
        if parts.count > 5 {
            parts = Array(parts.prefix(4))
            parts.append("...")
        }
        
        return parts.joined(separator: " • ")
    }
}