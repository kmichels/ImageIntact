//
//  UTIFileTypeDetector.swift
//  ImageIntact
//
//  Robust file type detection using Uniform Type Identifiers
//

import Foundation
import UniformTypeIdentifiers
import CoreServices

/// Modern file type detection using macOS Uniform Type Identifiers
class UTIFileTypeDetector {
    
    static let shared = UTIFileTypeDetector()
    
    private init() {}
    
    // MARK: - Public API
    
    /// Check if a file is supported by ImageIntact using UTI detection
    /// Falls back to extension checking for compatibility
    func isSupportedFile(_ url: URL) -> Bool {
        // Try UTI detection first (most reliable)
        if #available(macOS 11.0, *) {
            if let type = getUTType(for: url) {
                return isSupportedUTType(type)
            }
        } else {
            // For older macOS, try legacy UTI detection
            if let type = getLegacyUTI(for: url) {
                return isSupportedLegacyUTI(type)
            }
        }
        
        // Fallback to extension-based detection
        return ImageFileType.isSupportedFile(url)
    }
    
    /// Get detailed file type information
    func getFileTypeInfo(_ url: URL) -> FileTypeInfo {
        var info = FileTypeInfo(url: url)
        
        // Get UTI information
        if #available(macOS 11.0, *) {
            if let type = getUTType(for: url) {
                info.uti = type.identifier
                info.isImage = type.conforms(to: .image) || type.conforms(to: .rawImage)
                info.isVideo = type.conforms(to: .movie) || type.conforms(to: .video)
                info.isRAW = type.conforms(to: .rawImage)
                info.conformsToImageIntact = isSupportedUTType(type)
                
                // Get MIME type
                info.mimeType = type.preferredMIMEType
                
                // Check for specific types
                info.isDNG = type.conforms(to: UTType("com.adobe.dng") ?? .image)
                info.isHEIC = type.conforms(to: .heic) || type.conforms(to: .heif)
                
                // Check if it's a sidecar/metadata file
                info.isSidecar = isSidecarUTType(type)
            }
        }
        
        // Add extension-based info as backup
        if let fileType = ImageFileType.from(fileExtension: url.pathExtension.lowercased()) {
            info.legacyType = fileType
            info.isRAW = info.isRAW || fileType.isRaw
            info.isVideo = info.isVideo || fileType.isVideo
            info.isSidecar = info.isSidecar || fileType.isSidecar
        }
        
        return info
    }
    
    /// Check if file is a camera card image (from DCIM folder)
    func isCameraImage(_ url: URL) -> Bool {
        // Check if path contains DCIM
        if url.path.contains("/DCIM/") {
            return isSupportedFile(url)
        }
        
        // Check for camera-specific folder structures
        let cameraFolders = ["100CANON", "100NIKON", "100MSDCF", "100OLYMP", "100APPLE"]
        for folder in cameraFolders {
            if url.path.contains("/\(folder)/") {
                return isSupportedFile(url)
            }
        }
        
        return false
    }
    
    // MARK: - UTI Detection (macOS 11+)
    
    @available(macOS 11.0, *)
    private func getUTType(for url: URL) -> UTType? {
        do {
            // Try to get the UTI from file metadata (most accurate)
            let resourceValues = try url.resourceValues(forKeys: [.contentTypeKey])
            if let type = resourceValues.contentType {
                return type
            }
        } catch {
            // File might not exist or be inaccessible
            print("⚠️ Could not get UTI for \(url.lastPathComponent): \(error)")
        }
        
        // Fallback: Try to determine from extension
        if let type = UTType(filenameExtension: url.pathExtension) {
            return type
        }
        
        return nil
    }
    
    @available(macOS 11.0, *)
    private func isSupportedUTType(_ type: UTType) -> Bool {
        // Check for image types
        if type.conforms(to: .image) || type.conforms(to: .rawImage) {
            return true
        }
        
        // Check for video types
        if type.conforms(to: .movie) || type.conforms(to: .video) {
            return true
        }
        
        // Check for specific RAW formats that might not conform to .rawImage
        let rawUTIs = [
            "com.adobe.dng",                    // DNG
            "com.canon.cr2-raw",                 // Canon CR2
            "com.canon.cr3-raw",                 // Canon CR3
            "com.canon.crw-raw",                 // Canon CRW
            "com.nikon.nef-raw",                 // Nikon NEF
            "com.nikon.nrw-raw",                 // Nikon NRW
            "com.sony.arw-raw",                  // Sony ARW
            "com.sony.sr2-raw",                  // Sony SR2
            "com.fuji.raf-raw",                  // Fujifilm RAF
            "com.olympus.orf-raw",               // Olympus ORF
            "com.panasonic.rw2-raw",             // Panasonic RW2
            "com.pentax.pef-raw",                // Pentax PEF
            "com.hasselblad.fff-raw",            // Hasselblad FFF
            "com.phaseone.iiq-raw",              // Phase One IIQ
            "com.leica.rwl-raw",                 // Leica RWL
            "com.samsung.srw-raw"                // Samsung SRW
        ]
        
        for rawUTI in rawUTIs {
            if let rawType = UTType(rawUTI), type.conforms(to: rawType) {
                return true
            }
        }
        
        // Check for sidecar files we want to backup
        if isSidecarUTType(type) {
            return true
        }
        
        return false
    }
    
    @available(macOS 11.0, *)
    private func isSidecarUTType(_ type: UTType) -> Bool {
        // XMP sidecar files
        if type.conforms(to: UTType("com.adobe.xmp") ?? .xml) {
            return true
        }
        
        // Check for known sidecar extensions via identifier
        let sidecarIdentifiers = [
            "com.adobe.xmp",           // XMP
            "com.apple.aae",           // AAE
            "dyn.ah62d4rv4ge80s5pe",   // DOP (DxO)
            "com.captureone.cos",      // Capture One
            "com.rawtherapee.pp3"      // RawTherapee
        ]
        
        return sidecarIdentifiers.contains(type.identifier)
    }
    
    // MARK: - Legacy UTI Detection (macOS 10.x)
    
    private func getLegacyUTI(for url: URL) -> String? {
        // Use older Core Services API
        let unmanagedUTI = UTTypeCreatePreferredIdentifierForTag(
            kUTTagClassFilenameExtension,
            url.pathExtension as CFString,
            nil
        )
        
        if let uti = unmanagedUTI?.takeRetainedValue() as String? {
            return uti
        }
        
        return nil
    }
    
    private func isSupportedLegacyUTI(_ uti: String) -> Bool {
        // Check against known UTI strings
        let supportedUTIs = [
            kUTTypeImage as String,
            kUTTypeMovie as String,
            kUTTypeVideo as String,
            kUTTypeRawImage as String,
            "public.jpeg",
            "public.tiff",
            "public.png",
            "public.heic",
            "public.heif",
            "com.adobe.dng",
            "com.canon.cr2-raw",
            "com.canon.cr3-raw",
            "com.nikon.nef-raw",
            "com.sony.arw-raw",
            "com.fuji.raf-raw",
            "com.adobe.xmp"
        ]
        
        // Check if UTI conforms to any supported type
        for supportedUTI in supportedUTIs {
            if UTTypeConformsTo(uti as CFString, supportedUTI as CFString) {
                return true
            }
        }
        
        return false
    }
}

// MARK: - File Type Info Structure

struct FileTypeInfo {
    let url: URL
    var uti: String?
    var mimeType: String?
    var isImage: Bool = false
    var isVideo: Bool = false
    var isRAW: Bool = false
    var isDNG: Bool = false
    var isHEIC: Bool = false
    var isSidecar: Bool = false
    var conformsToImageIntact: Bool = false
    var legacyType: ImageFileType?
    var isCameraFile: Bool = false
    
    var displayName: String {
        if isRAW {
            return "RAW Image"
        } else if isVideo {
            return "Video"
        } else if isSidecar {
            return "Metadata"
        } else if isImage {
            return "Image"
        }
        return "File"
    }
    
    var isSupported: Bool {
        return conformsToImageIntact || legacyType != nil
    }
}