//
//  ImageFileType.swift
//  ImageIntact
//
//  Image file type definitions and recognition
//

import Foundation

enum ImageFileType: String, CaseIterable {
    // Standard formats
    case jpeg = "JPEG"
    case tiff = "TIFF"
    case png = "PNG"
    case heic = "HEIC"
    case heif = "HEIF"
    case webp = "WebP"
    case bmp = "BMP"
    case gif = "GIF"
    
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
    
    // Fujifilm
    case raf = "RAF"
    
    // Olympus
    case orf = "ORF"
    
    // Panasonic
    case rw2 = "RW2"
    case raw = "RAW"  // Panasonic/Leica
    
    // Pentax
    case pef = "PEF"
    case dng_pentax = "PTX"
    
    // Leica
    case rwl = "RWL"
    case dng_leica = "DNG"
    
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
        case .dng, .dng_pentax, .dng_leica:
            return ["dng"]
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
        }
    }
    
    var isRaw: Bool {
        switch self {
        case .jpeg, .tiff, .png, .heic, .heif, .webp, .bmp, .gif:
            return false
        default:
            return true
        }
    }
    
    var displayName: String {
        if isRaw {
            return "RAW (\(rawValue))"
        }
        return rawValue
    }
    
    var folderName: String {
        // For organizing into subfolders
        return rawValue
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
    
    static func isImageFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return from(fileExtension: ext) != nil
    }
}

// File scanner for analyzing source folders
class ImageFileScanner {
    typealias ScanResult = [ImageFileType: Int]
    typealias ScanProgress = (scanned: Int, total: Int?, currentPath: String)
    
    private var currentTask: Task<ScanResult, Error>?
    
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
            
            for case let url as URL in enumerator {
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
    
    func cancel() {
        currentTask?.cancel()
    }
    
    // Helper to get a nice summary string
    static func formatScanResults(_ results: ScanResult, groupRaw: Bool = false) -> String {
        if results.isEmpty {
            return "No image files found"
        }
        
        if groupRaw {
            var rawCount = 0
            var otherCounts: [(String, Int)] = []
            
            for (type, count) in results.sorted(by: { $0.value > $1.value }) {
                if type.isRaw {
                    rawCount += count
                } else {
                    otherCounts.append((type.rawValue, count))
                }
            }
            
            var parts: [String] = []
            if rawCount > 0 {
                parts.append("\(rawCount.formatted()) RAW")
            }
            for (type, count) in otherCounts.prefix(3) {
                parts.append("\(count.formatted()) \(type)")
            }
            if otherCounts.count > 3 {
                parts.append("...")
            }
            
            return parts.joined(separator: " • ")
        } else {
            let sorted = results.sorted(by: { $0.value > $1.value })
            let displayed = sorted.prefix(4)
            
            var parts = displayed.map { type, count in
                "\(count.formatted()) \(type.displayName)"
            }
            
            if sorted.count > 4 {
                parts.append("...")
            }
            
            return parts.joined(separator: " • ")
        }
    }
}