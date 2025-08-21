//
//  PathAnonymizer.swift
//  ImageIntact
//
//  Anonymizes file paths for privacy-safe log sharing
//

import Foundation

/// Anonymizes file paths to protect user privacy when exporting logs
class PathAnonymizer {
    
    /// Anonymization options
    struct Options {
        var anonymizeUsernames: Bool = true
        var anonymizeVolumeNames: Bool = true
        var anonymizeFileNames: Bool = false  // Usually want to keep filenames for debugging
        var preserveExtensions: Bool = true   // Keep file extensions for debugging
        var preserveSystemPaths: Bool = true  // Keep /System, /Library, etc.
    }
    
    // Common patterns to anonymize
    private static let homeDirectoryPattern = #"/Users/([^/]+)"#
    private static let volumePattern = #"/Volumes/([^/]+)"#
    private static let iCloudPattern = #"/Users/([^/]+)/Library/Mobile Documents/([^/]+)"#
    
    // System paths that are safe to keep (not user-specific)
    private static let systemPaths = [
        "/System",
        "/Library",
        "/Applications",
        "/usr",
        "/bin",
        "/sbin",
        "/opt",
        "/var",
        "/tmp",
        "/private/tmp",
        "/private/var"
    ]
    
    /// Anonymize a single path
    /// - Parameters:
    ///   - path: The path to anonymize
    ///   - options: Anonymization options
    /// - Returns: The anonymized path
    static func anonymize(_ path: String, options: Options = Options()) -> String {
        var result = path
        
        // Skip system paths if requested
        if options.preserveSystemPaths {
            for systemPath in systemPaths {
                if path.hasPrefix(systemPath + "/") || path == systemPath {
                    // This is a system path, only anonymize user-specific parts if they appear later
                    break
                }
            }
        }
        
        // Anonymize usernames in home directories
        if options.anonymizeUsernames {
            // Handle regular home directories
            result = result.replacingOccurrences(
                of: homeDirectoryPattern,
                with: "/Users/[USER]",
                options: .regularExpression
            )
            
            // Handle iCloud Drive paths
            result = result.replacingOccurrences(
                of: iCloudPattern,
                with: "/Users/[USER]/Library/Mobile Documents/[ICLOUD]",
                options: .regularExpression
            )
            
            // Handle user-specific Library paths
            result = result.replacingOccurrences(
                of: #"~/Library"#,
                with: "[HOME]/Library"
            )
            
            // Handle tilde expansion
            if result.hasPrefix("~/") {
                result = "[HOME]" + String(result.dropFirst(1))
            }
        }
        
        // Anonymize volume names
        if options.anonymizeVolumeNames {
            result = result.replacingOccurrences(
                of: volumePattern,
                with: "/Volumes/[VOLUME]",
                options: .regularExpression
            )
        }
        
        // Anonymize file names if requested (but keep structure)
        if options.anonymizeFileNames {
            let components = result.components(separatedBy: "/")
            var anonymizedComponents: [String] = []
            
            for (index, component) in components.enumerated() {
                // Skip empty components and already anonymized parts
                if component.isEmpty || component.hasPrefix("[") && component.hasSuffix("]") {
                    anonymizedComponents.append(component)
                    continue
                }
                
                // Keep system directories and special folders
                if index < 3 || systemPaths.contains("/" + components[1...index].joined(separator: "/")) {
                    anonymizedComponents.append(component)
                    continue
                }
                
                // Anonymize the filename but preserve extension if requested
                if options.preserveExtensions, let ext = component.split(separator: ".").last, 
                   component.contains(".") && !component.hasPrefix(".") {
                    anonymizedComponents.append("[FILE].\(ext)")
                } else if component.hasPrefix(".") {
                    // Hidden file
                    anonymizedComponents.append("[HIDDEN]")
                } else {
                    anonymizedComponents.append("[FILE]")
                }
            }
            
            result = anonymizedComponents.joined(separator: "/")
        }
        
        return result
    }
    
    /// Anonymize multiple paths
    /// - Parameters:
    ///   - paths: Array of paths to anonymize
    ///   - options: Anonymization options
    /// - Returns: Array of anonymized paths
    static func anonymizeMultiple(_ paths: [String], options: Options = Options()) -> [String] {
        return paths.map { anonymize($0, options: options) }
    }
    
    /// Anonymize paths in a log text
    /// - Parameters:
    ///   - logText: The log text containing paths
    ///   - options: Anonymization options
    /// - Returns: The log text with anonymized paths
    static func anonymizeInText(_ logText: String, options: Options = Options()) -> String {
        var result = logText
        
        // First, find and replace obvious paths
        let pathPattern = #"(/Users/[^\s\"'\]]+|/Volumes/[^\s\"'\]]+|~/[^\s\"'\]]+)"#
        
        do {
            let regex = try NSRegularExpression(pattern: pathPattern, options: [])
            let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count))
            
            // Process matches in reverse order to maintain string indices
            for match in matches.reversed() {
                if let range = Range(match.range, in: result) {
                    let path = String(result[range])
                    let anonymized = anonymize(path, options: options)
                    result.replaceSubrange(range, with: anonymized)
                }
            }
        } catch {
            logError("Failed to create regex for path anonymization: \(error)")
        }
        
        // Also handle quoted paths
        let quotedPathPattern = #"\"(/[^\"]+)\""#
        do {
            let regex = try NSRegularExpression(pattern: quotedPathPattern, options: [])
            let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count))
            
            for match in matches.reversed() {
                if let range = Range(match.range(at: 1), in: result) {
                    let path = String(result[range])
                    let anonymized = anonymize(path, options: options)
                    result.replaceSubrange(range, with: anonymized)
                }
            }
        } catch {
            logError("Failed to create regex for quoted path anonymization: \(error)")
        }
        
        return result
    }
    
    /// Create a summary of what will be anonymized
    /// - Parameter options: The anonymization options
    /// - Returns: A user-friendly description
    static func describeAnonymization(options: Options = Options()) -> String {
        var descriptions: [String] = []
        
        if options.anonymizeUsernames {
            descriptions.append("• Your username will be replaced with [USER]")
        }
        
        if options.anonymizeVolumeNames {
            descriptions.append("• External drive names will be replaced with [VOLUME]")
        }
        
        if options.anonymizeFileNames {
            if options.preserveExtensions {
                descriptions.append("• File names will be replaced with [FILE] (keeping extensions)")
            } else {
                descriptions.append("• File names will be replaced with [FILE]")
            }
        }
        
        if options.preserveSystemPaths {
            descriptions.append("• System paths will be preserved for debugging")
        }
        
        return descriptions.joined(separator: "\n")
    }
    
    /// Example demonstration for user education
    static func demonstrateAnonymization() -> (original: String, anonymized: String) {
        let original = "/Users/johndoe/Pictures/Vacation/IMG_1234.jpg"
        let anonymized = anonymize(original)
        return (original, anonymized)
    }
}