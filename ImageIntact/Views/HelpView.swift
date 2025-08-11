import SwiftUI

// Help view
struct HelpView: View {
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("ImageIntact Help")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button("Close") {
                    isPresented = false
                }
                .keyboardShortcut(.escape)
            }
            .padding(20)
            
            Divider()
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Getting Started
                    HelpSection(title: "Getting Started") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("ImageIntact is designed to safely backup your photos to multiple destinations with verification.")
                            
                            Text("**Basic workflow:**")
                                .fontWeight(.medium)
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text("1. **Select Source**: Choose the folder containing your photos")
                                Text("2. **Add Destinations**: Select up to 4 backup locations")
                                Text("3. **Run Backup**: Click the backup button to start")
                                Text("4. **Monitor Progress**: Watch real-time progress for each destination")
                            }
                            .font(.subheadline)
                        }
                    }
                    
                    // Safety Features
                    HelpSection(title: "Safety Features") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("ImageIntact prioritizes data safety above all else:")
                            
                            VStack(alignment: .leading, spacing: 8) {
                                HelpPoint(title: "Never Deletes Files", 
                                         description: "Files are never deleted from any destination")
                                
                                HelpPoint(title: "Checksum Verification", 
                                         description: "Every file is verified with SHA-256 checksums to ensure perfect copies")
                                
                                HelpPoint(title: "Smart Quarantine", 
                                         description: "If a file exists with different content, it's moved to a quarantine folder before copying the new version")
                                
                                HelpPoint(title: "Source Protection", 
                                         description: "Source folders are tagged to prevent accidental selection as destinations")
                            }
                        }
                    }
                    
                    // File Type Support
                    HelpSection(title: "File Type Support") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("ImageIntact intelligently filters and backs up photography-related files:")
                            
                            VStack(alignment: .leading, spacing: 8) {
                                HelpPoint(title: "30+ RAW Formats", 
                                         description: "Supports RAW files from all major camera manufacturers")
                                
                                HelpPoint(title: "Video Files", 
                                         description: "Backs up MOV, MP4, AVI and other video formats")
                                
                                HelpPoint(title: "Sidecar Files", 
                                         description: "Preserves XMP, AAE and other metadata sidecar files")
                                
                                HelpPoint(title: "Smart Cache Exclusion", 
                                         description: "Automatically skips Lightroom and Capture One preview caches")
                            }
                        }
                    }
                    
                    // Performance
                    HelpSection(title: "Performance") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("ImageIntact automatically optimizes performance based on your destinations:")
                            
                            VStack(alignment: .leading, spacing: 8) {
                                HelpPoint(title: "SHA-256 Checksums", 
                                         description: "Uses cryptographically secure SHA-256 checksums for reliable verification")
                                
                                HelpPoint(title: "Phase-Based Architecture", 
                                         description: "Optimized workflow: analyze → manifest → copy → verify")
                                
                                HelpPoint(title: "Smart Concurrency", 
                                         description: "Up to 8 parallel operations for modern SSDs")
                                
                                HelpPoint(title: "Progress Monitoring", 
                                         description: "Real-time progress tracking with phase indicators")
                            }
                        }
                    }
                    
                    // Keyboard Shortcuts
                    HelpSection(title: "Keyboard Shortcuts") {
                        VStack(alignment: .leading, spacing: 8) {
                            HelpShortcut(key: "⌘1", action: "Select source folder")
                            HelpShortcut(key: "⌘2", action: "Select first destination")
                            HelpShortcut(key: "⌘+", action: "Add destination")
                            HelpShortcut(key: "⌘R", action: "Run backup")
                            HelpShortcut(key: "⌘K", action: "Clear all selections")
                        }
                    }
                    
                    // Troubleshooting
                    HelpSection(title: "Troubleshooting") {
                        VStack(alignment: .leading, spacing: 12) {
                            HelpPoint(title: "Network Timeouts", 
                                     description: "Network destinations have special handling - be patient with SMB/AFP volumes")
                            
                            HelpPoint(title: "Debug Information", 
                                     description: "Use ImageIntact menu → Show Debug Log for detailed operation logs")
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 600, height: 700)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// Help section container
struct HelpSection<Content: View>: View {
    let title: String
    let content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            content
        }
    }
}

// Help point for features
struct HelpPoint: View {
    let title: String
    let description: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
            
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// Help shortcut row
struct HelpShortcut: View {
    let key: String
    let action: String
    
    var body: some View {
        HStack {
            Text(key)
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(4)
            
            Text(action)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
        }
    }
}