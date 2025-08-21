import SwiftUI

// Help view
struct HelpView: View {
    @Binding var isPresented: Bool
    var scrollToSection: String? = nil
    
    init(isPresented: Binding<Bool> = .constant(true), scrollToSection: String? = nil) {
        self._isPresented = isPresented
        self.scrollToSection = scrollToSection
    }
    
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
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                    // What's New
                    HelpSection(title: "What's New in v1.2") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("• **Independent destinations** - Each runs at full speed")
                            Text("• **Real-time ETA** - See time remaining per destination")
                            Text("• **Automatic updates** - Daily checks for new versions")
                            Text("• **Better progress** - Per-destination tracking")
                            Text("• **Adaptive performance** - 1-8 workers per destination")
                        }
                        .font(.subheadline)
                    }
                    
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
                    
                    // Privacy and Security
                    HelpSection(title: "Privacy & Security", id: "privacy") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("ImageIntact protects your privacy and data:")
                            
                            VStack(alignment: .leading, spacing: 8) {
                                HelpPoint(title: "Path Anonymization", 
                                         description: "Automatically removes personal information from exported logs")
                                
                                HelpPoint(title: "Local Processing Only", 
                                         description: "All operations happen on your Mac - no cloud services or internet required")
                                
                                HelpPoint(title: "Backup History", 
                                         description: "Your backup records stay on your Mac and are never shared")
                                
                                HelpPoint(title: "Secure Verification", 
                                         description: "Uses SHA-256 checksums to ensure data integrity")
                            }
                            
                            GroupBox {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("About Path Anonymization")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                    
                                    Text("When you export diagnostic logs, ImageIntact can automatically replace sensitive information like usernames and drive names with generic placeholders. This protects your privacy when sharing logs for support.")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    
                                    HStack(spacing: 8) {
                                        Text("Example:")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        
                                        Text("/Users/john → /Users/[USER]")
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(.accentColor)
                                    }
                                }
                                .padding(8)
                            }
                        }
                    }
                    
                    // Performance
                    HelpSection(title: "Performance (v1.2)") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("ImageIntact automatically optimizes performance based on your destinations:")
                            
                            VStack(alignment: .leading, spacing: 8) {
                                HelpPoint(title: "Independent Destinations", 
                                         description: "Each destination runs at full speed - fast SSDs don't wait for slow network drives")
                                
                                HelpPoint(title: "Queue-Based System", 
                                         description: "Smart task scheduling with 1-8 adaptive workers per destination")
                                
                                HelpPoint(title: "Real-time ETA", 
                                         description: "See estimated time remaining for each destination")
                                
                                HelpPoint(title: "SHA-256 Checksums", 
                                         description: "Cryptographically secure verification using native Swift")
                            }
                        }
                    }
                    
                    // Automatic Updates
                    HelpSection(title: "Automatic Updates (v1.2)") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("ImageIntact can automatically check for updates:")
                            
                            VStack(alignment: .leading, spacing: 8) {
                                HelpPoint(title: "Daily Checks", 
                                         description: "Automatically checks once per day on launch")
                                
                                HelpPoint(title: "Manual Check", 
                                         description: "Use ImageIntact menu → Check for Updates")
                                
                                HelpPoint(title: "Safe Downloads", 
                                         description: "Downloads to your Downloads folder with progress tracking")
                                
                                HelpPoint(title: "Version Skipping", 
                                         description: "You can skip specific versions if desired")
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
                            HelpShortcut(key: "⌘?", action: "Show this help")
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
            .onAppear {
                if let section = scrollToSection {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation {
                            proxy.scrollTo(section, anchor: .top)
                        }
                    }
                }
            }
        }
        }
        .frame(width: 600, height: 700)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// Help section container
struct HelpSection<Content: View>: View {
    let title: String
    let id: String?
    let content: Content
    
    init(title: String, id: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.id = id
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .id(id)
            
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