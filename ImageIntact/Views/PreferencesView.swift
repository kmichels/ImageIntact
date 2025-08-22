//
//  PreferencesView.swift
//  ImageIntact
//
//  Application preferences window
//

import SwiftUI

struct PreferencesView: View {
    @StateObject private var preferences = PreferencesManager.shared
    @State private var selectedTab = "general"
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selectedTab) {
                GeneralPreferencesView()
                    .tabItem {
                        Label("General", systemImage: "gearshape")
                    }
                    .tag("general")
                
                PerformancePreferencesView()
                    .tabItem {
                        Label("Performance", systemImage: "cpu")
                    }
                    .tag("performance")
                
                LoggingPreferencesView()
                    .tabItem {
                        Label("Logging & Privacy", systemImage: "lock.shield")
                    }
                    .tag("logging")
                
                AdvancedPreferencesView()
                    .tabItem {
                        Label("Advanced", systemImage: "gearshape.2")
                    }
                    .tag("advanced")
            }
            .padding(.top, 10) // Standard macOS preferences window tab padding
            
            // Close button at bottom
            Divider()
            
            HStack {
                Spacer()
                
                Button("Close") {
                    dismiss()
                }
                .controlSize(.regular)
                .keyboardShortcut(.defaultAction)
                .padding(.trailing, 20)
                .padding(.vertical, 12)
            }
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 650, height: 560) // Slightly taller to accommodate close button
    }
}

// MARK: - General Tab

struct GeneralPreferencesView: View {
    @ObservedObject private var preferences = PreferencesManager.shared
    @State private var selectedSourceURL: URL?
    @State private var selectedDestinationURL: URL?
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Default Paths Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Default Paths")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        VStack(spacing: 12) {
                            HStack(alignment: .center, spacing: 12) {
                                Text("Default Source:")
                                    .font(.system(size: 13))
                                    .frame(alignment: .leading)
                                
                                Text(preferences.defaultSourcePath.isEmpty ? "Not set" : URL(fileURLWithPath: preferences.defaultSourcePath).lastPathComponent)
                                    .font(.system(size: 13))
                                    .foregroundColor(preferences.defaultSourcePath.isEmpty ? .secondary : .primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                
                                Spacer()
                                
                                Button("Choose...") {
                                    selectSourceFolder()
                                }
                                .controlSize(.small)
                                
                                if !preferences.defaultSourcePath.isEmpty {
                                    Button("Clear") {
                                        preferences.defaultSourcePath = ""
                                    }
                                    .controlSize(.small)
                                }
                            }
                            
                            HStack(alignment: .center, spacing: 12) {
                                Text("Default Destination:")
                                    .font(.system(size: 13))
                                    .frame(alignment: .leading)
                                
                                Text(preferences.defaultDestinationPath.isEmpty ? "Not set" : URL(fileURLWithPath: preferences.defaultDestinationPath).lastPathComponent)
                                    .font(.system(size: 13))
                                    .foregroundColor(preferences.defaultDestinationPath.isEmpty ? .secondary : .primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                
                                Spacer()
                                
                                Button("Choose...") {
                                    selectDestinationFolder()
                                }
                                .controlSize(.small)
                                
                                if !preferences.defaultDestinationPath.isEmpty {
                                    Button("Clear") {
                                        preferences.defaultDestinationPath = ""
                                    }
                                    .controlSize(.small)
                                }
                            }
                        }
                    }
                    
                    Divider()
                        .padding(.vertical, 8)
                    
                    // Startup Behavior Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Startup Behavior")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Check for updates automatically", isOn: .constant(true))
                                .font(.system(size: 13))
                                .disabled(true)
                                .help("Updates are checked every 24 hours")
                            
                            Toggle("Restore last session paths on launch", isOn: $preferences.restoreLastSession)
                                .font(.system(size: 13))
                                .help("Automatically reload the source and destination folders from your last session")
                            
                            Toggle("Show welcome screen on first launch", isOn: $preferences.showWelcomeOnLaunch)
                                .font(.system(size: 13))
                                .help("Display the welcome guide for new users")
                        }
                    }
                    
                    Divider()
                        .padding(.vertical, 8)
                    
                    // File Handling Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("File Handling")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Exclude cache files by default", isOn: $preferences.excludeCacheFiles)
                                .font(.system(size: 13))
                                .help("Skip Adobe cache files, Lightroom previews, .DS_Store, thumbnails, and other temporary files")
                            
                            Toggle("Skip hidden files", isOn: $preferences.skipHiddenFiles)
                                .font(.system(size: 13))
                                .help("Ignore .DS_Store, ._* files, and other system files")
                            
                            HStack(spacing: 6) {
                                Text("Default file type filter:")
                                    .font(.system(size: 13))
                                
                                Picker("", selection: $preferences.defaultFileTypeFilter) {
                                    Text("All Files").tag("all")
                                    Text("Photos Only").tag("photos")
                                    Text("RAW Only").tag("raw")
                                    Text("Videos Only").tag("videos")
                                }
                                .pickerStyle(MenuPickerStyle())
                                .frame(width: 150)
                                .help("Default filter applied when starting a new backup")
                                
                                Spacer()
                            }
                        }
                    }
                    
                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 100)
                .padding(.top, 20)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    func selectSourceFolder() {
        let dialog = NSOpenPanel()
        dialog.canChooseFiles = false
        dialog.canChooseDirectories = true
        dialog.allowsMultipleSelection = false
        
        if dialog.runModal() == .OK {
            if let url = dialog.url {
                preferences.defaultSourcePath = url.path
            }
        }
    }
    
    func selectDestinationFolder() {
        let dialog = NSOpenPanel()
        dialog.canChooseFiles = false
        dialog.canChooseDirectories = true
        dialog.allowsMultipleSelection = false
        
        if dialog.runModal() == .OK {
            if let url = dialog.url {
                preferences.defaultDestinationPath = url.path
            }
        }
    }
}

// MARK: - Performance Tab

struct PerformancePreferencesView: View {
    @ObservedObject private var preferences = PreferencesManager.shared
    @State private var showIntelWarning = false
    @State private var showAppleSiliconWarning = false
    
    private var systemInfo: SystemCapabilities.SystemInfo? {
        SystemCapabilities.shared.currentSystemInfo
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // System Information Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("System Information")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                    
                        GroupBox {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 12) {
                                    Text("Processor:")
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary)
                                        .frame(width: 100, alignment: .trailing)
                                    Text(systemInfo?.processorName ?? "Unknown")
                                        .font(.system(size: 13, weight: .medium))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                
                                HStack(spacing: 12) {
                                    Text("Cores:")
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary)
                                        .frame(width: 100, alignment: .trailing)
                                    if let info = systemInfo {
                                        if info.performanceCores > 0 {
                                            Text("\(info.cpuCores) total (\(info.performanceCores) performance, \(info.efficiencyCores) efficiency)")
                                                .font(.system(size: 13))
                                        } else {
                                            Text("\(info.cpuCores)")
                                                .font(.system(size: 13))
                                        }
                                    }
                                    Spacer()
                                }
                                
                                HStack(spacing: 12) {
                                    Text("RAM:")
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary)
                                        .frame(width: 100, alignment: .trailing)
                                    if let info = systemInfo {
                                        Text(ByteCountFormatter.string(fromByteCount: info.totalRAM, countStyle: .binary))
                                            .font(.system(size: 13))
                                    }
                                    Spacer()
                                }
                                
                                HStack(spacing: 12) {
                                    Text("Neural Engine:")
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary)
                                        .frame(width: 100, alignment: .trailing)
                                    if SystemCapabilities.shared.hasNeuralEngine {
                                        Label("Available", systemImage: "checkmark.circle.fill")
                                            .font(.system(size: 13))
                                            .foregroundColor(.green)
                                    } else {
                                        Text("Not Available")
                                            .font(.system(size: 13))
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                            }
                            .padding(12)
                        }
                    }
                    
                    Divider()
                        .padding(.vertical, 8)
                    
                    // Vision Framework Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Vision Framework")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        Text("Future feature for intelligent photo analysis")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    
                        
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Enable Vision Framework features", isOn: $preferences.enableVisionFramework)
                                .font(.system(size: 13))
                                .disabled(true) // Not implemented yet
                                .help("Coming in v1.3 - Intelligent photo search and organization")
                                .onChange(of: preferences.enableVisionFramework) { oldValue, newValue in
                                    if !SystemCapabilities.shared.isAppleSilicon && newValue {
                                        showIntelWarning = true
                                    } else if SystemCapabilities.shared.isAppleSilicon && !newValue {
                                        showAppleSiliconWarning = true
                                    }
                                }
                            
                            HStack(spacing: 12) {
                                Text("Processing priority:")
                                    .font(.system(size: 13))
                                    .frame(width: 130, alignment: .trailing)
                                
                                Picker("", selection: $preferences.visionProcessingPriority) {
                                    Text("Low").tag("low")
                                    Text("Normal").tag("normal")
                                    Text("High").tag("high")
                                }
                                .pickerStyle(SegmentedPickerStyle())
                                .frame(width: 200)
                                .disabled(true) // Not implemented yet
                                
                                Spacer()
                            }
                        }
                    }
                    
                    Divider()
                        .padding(.vertical, 8)
                    
                    // System Behavior Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("System Behavior")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Prevent sleep during backup", isOn: $preferences.preventSleepDuringBackup)
                                .font(.system(size: 13))
                                .help("Keep your Mac awake while backup is running")
                            
                            Toggle("Show notification when backup completes", isOn: $preferences.showNotificationOnComplete)
                                .font(.system(size: 13))
                                .help("Display a system notification when backup finishes")
                        }
                    }
                    
                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 100)
                .padding(.top, 20)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .alert("Performance Warning", isPresented: $showIntelWarning) {
            Button("Enable Anyway") { }
            Button("Cancel", role: .cancel) {
                preferences.enableVisionFramework = false
            }
        } message: {
            Text("""
                Vision Framework features are optimized for Apple Silicon and may cause:
                
                • Significantly slower backup speeds
                • High CPU usage and heat generation
                • Increased memory usage
                • Potential system unresponsiveness
                
                These features work best on Macs with Apple M-series processors.
                """)
        }
        .alert("Disable Vision Features?", isPresented: $showAppleSiliconWarning) {
            Button("Disable") { }
            Button("Keep Enabled", role: .cancel) {
                preferences.enableVisionFramework = true
            }
        } message: {
            Text("""
                Your Mac's Neural Engine is optimized for these features with minimal performance impact.
                
                Disabling will turn off future intelligent features like:
                • Photo search and organization
                • Scene detection
                • Content-based grouping
                """)
        }
    }
}

// MARK: - Logging Tab

struct LoggingPreferencesView: View {
    @ObservedObject private var preferences = PreferencesManager.shared
    @State private var showClearConfirmation = false
    @State private var showPrivacyExplanation = false
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Operational Logs Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Operational Logs")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        Text("Debug and error logs for troubleshooting")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    
                        
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 12) {
                                Text("Minimum log level:")
                                    .font(.system(size: 13))
                                    .frame(width: 160, alignment: .trailing)
                                
                                Picker("", selection: $preferences.minimumLogLevel) {
                                    Text("Debug").tag(0)
                                    Text("Info").tag(1)
                                    Text("Warning").tag(2)
                                    Text("Error").tag(3)
                                    Text("Critical").tag(4)
                                }
                                .pickerStyle(MenuPickerStyle())
                                .frame(width: 120)
                                
                                Spacer()
                            }
                            
                            Toggle("Log to Console.app", isOn: $preferences.enableConsoleLogging)
                                .font(.system(size: 13))
                                .help("Send logs to macOS Console for debugging")
                            
                            Toggle("Enable debug menu items", isOn: $preferences.enableDebugMenu)
                                .font(.system(size: 13))
                                .help("Show additional debugging options in menus")
                            
                            HStack(spacing: 12) {
                                Text("Keep operational logs for:")
                                    .font(.system(size: 13))
                                    .frame(width: 160, alignment: .trailing)
                                
                                Picker("", selection: $preferences.operationalLogRetention) {
                                    Text("7 days").tag(7)
                                    Text("14 days").tag(14)
                                    Text("30 days").tag(30)
                                    Text("60 days").tag(60)
                                }
                                .pickerStyle(MenuPickerStyle())
                                .frame(width: 100)
                                
                                Spacer()
                            }
                        }
                    }
                    
                    Divider()
                        .padding(.vertical, 8)
                    
                    // Backup History Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Backup History")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        Text("ImageIntact maintains a local, private record of all your backups on this Mac to help you locate files in the future. This data never leaves your computer.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    
                        
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 12) {
                                Button("View Backup History...") {
                                    // TODO: Implement backup history viewer
                                    logInfo("View Backup History clicked - not yet implemented")
                                }
                                .controlSize(.small)
                                .disabled(true)
                                
                                Button("Export Backup Catalog...") {
                                    // TODO: Implement catalog export
                                    logInfo("Export Backup Catalog clicked - not yet implemented")
                                }
                                .controlSize(.small)
                                .disabled(true)
                            }
                            
                            HStack(spacing: 8) {
                                Text("Storage location:")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Text("~/Library/Application Support/ImageIntact/")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    Divider()
                        .padding(.vertical, 8)
                    
                    // Privacy Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Privacy")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top, spacing: 8) {
                                Toggle("Anonymize paths when exporting logs", isOn: $preferences.anonymizePathsInExport)
                                    .font(.system(size: 13))
                                    .help("Replace usernames and volume names with placeholders in exported logs")
                                
                                Button(action: {
                                    showPrivacyExplanation = true
                                }) {
                                    Image(systemName: "questionmark.circle")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 12))
                                }
                                .buttonStyle(.plain)
                                .help("Learn about path anonymization")
                            }
                            
                            // Show example when enabled
                            if preferences.anonymizePathsInExport {
                                Text("Example: /Users/yourname/Pictures → /Users/[USER]/Pictures")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .padding(.leading, 20)
                            }
                            
                            Button("Clear Operational Logs") {
                                showClearConfirmation = true
                            }
                            .controlSize(.small)
                            .help("Remove debug logs while keeping backup history")
                        }
                    }
                    
                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 100)
                .padding(.top, 20)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .alert("Clear Operational Logs?", isPresented: $showClearConfirmation) {
            Button("Clear", role: .destructive) {
                ApplicationLogger.shared.cleanupOldLogs(daysToKeep: 0)
                logInfo("Operational logs cleared by user")
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will remove all debug and error logs. Your backup history will be preserved.")
        }
        .sheet(isPresented: $showPrivacyExplanation) {
            PrivacyExplanationView()
        }
    }
}

// MARK: - Advanced Tab

struct AdvancedPreferencesView: View {
    @ObservedObject private var preferences = PreferencesManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Experimental Features Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Experimental Features")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                    
                        
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Enable smart duplicate detection", isOn: $preferences.enableSmartDuplicateDetection)
                                .font(.system(size: 13))
                                .disabled(true)
                                .help("Coming soon - Detect and skip files that are already backed up")
                            
                            Toggle("Show technical details during backup", isOn: $preferences.showTechnicalDetails)
                                .font(.system(size: 13))
                                .help("Display additional technical information in the progress view")
                        }
                    }
                    
                    Divider()
                        .padding(.vertical, 8)
                    
                    // Safety Confirmations Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Safety Confirmations")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Confirm before large backups", isOn: $preferences.confirmLargeBackups)
                                .font(.system(size: 13))
                                .help("Ask for confirmation before starting backups over the threshold")
                            
                            HStack(spacing: 12) {
                                Text("File count threshold:")
                                    .font(.system(size: 13))
                                    .frame(width: 160, alignment: .trailing)
                                
                                TextField("", value: $preferences.largeBackupFileThreshold, format: .number)
                                    .frame(width: 80)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .disabled(!preferences.confirmLargeBackups)
                                
                                Text("files")
                                    .font(.system(size: 13))
                                
                                Spacer()
                            }
                            
                            HStack(spacing: 12) {
                                Text("Size threshold:")
                                    .font(.system(size: 13))
                                    .frame(width: 160, alignment: .trailing)
                                
                                TextField("", value: $preferences.largeBackupSizeThresholdGB, format: .number)
                                    .frame(width: 80)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .disabled(!preferences.confirmLargeBackups)
                                
                                Text("GB")
                                    .font(.system(size: 13))
                                
                                Spacer()
                            }
                            
                            Toggle("Show summary before starting backup", isOn: $preferences.showPreflightSummary)
                                .font(.system(size: 13))
                                .help("Display a summary of what will be backed up before starting")
                        }
                    }
                    
                    Spacer(minLength: 20)
                    
                    Divider()
                        .padding(.vertical, 8)
                    
                    HStack {
                        Spacer()
                        Button("Reset to Defaults") {
                            preferences.resetToDefaults()
                        }
                        .controlSize(.regular)
                    }
                }
                .padding(.horizontal, 100)
                .padding(.top, 20)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Preview

struct PreferencesView_Previews: PreviewProvider {
    static var previews: some View {
        PreferencesView()
    }
}