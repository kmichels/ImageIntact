//
//  PreferencesView.swift
//  ImageIntact
//
//  Application preferences window
//

import SwiftUI

struct PreferencesView: View {
    @StateObject private var preferences = PreferencesManager.shared
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralPreferencesView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(0)
            
            PerformancePreferencesView()
                .tabItem {
                    Label("Performance", systemImage: "speedometer")
                }
                .tag(1)
            
            LoggingPreferencesView()
                .tabItem {
                    Label("Logging & Privacy", systemImage: "doc.text.magnifyingglass")
                }
                .tag(2)
            
            AdvancedPreferencesView()
                .tabItem {
                    Label("Advanced", systemImage: "wrench.and.screwdriver")
                }
                .tag(3)
        }
        .frame(width: 600, height: 450)
    }
}

// MARK: - General Tab

struct GeneralPreferencesView: View {
    @ObservedObject private var preferences = PreferencesManager.shared
    @State private var selectedSourceURL: URL?
    @State private var selectedDestinationURL: URL?
    
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Default Paths")
                        .font(.headline)
                    
                    HStack {
                        Text("Default Source:")
                            .frame(width: 120, alignment: .trailing)
                        
                        Text(preferences.defaultSourcePath.isEmpty ? "Not set" : URL(fileURLWithPath: preferences.defaultSourcePath).lastPathComponent)
                            .foregroundColor(preferences.defaultSourcePath.isEmpty ? .secondary : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Button("Choose...") {
                            selectSourceFolder()
                        }
                        
                        if !preferences.defaultSourcePath.isEmpty {
                            Button("Clear") {
                                preferences.defaultSourcePath = ""
                            }
                        }
                    }
                    
                    HStack {
                        Text("Default Destination:")
                            .frame(width: 120, alignment: .trailing)
                        
                        Text(preferences.defaultDestinationPath.isEmpty ? "Not set" : URL(fileURLWithPath: preferences.defaultDestinationPath).lastPathComponent)
                            .foregroundColor(preferences.defaultDestinationPath.isEmpty ? .secondary : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Button("Choose...") {
                            selectDestinationFolder()
                        }
                        
                        if !preferences.defaultDestinationPath.isEmpty {
                            Button("Clear") {
                                preferences.defaultDestinationPath = ""
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            
            Divider()
            
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Startup Behavior")
                        .font(.headline)
                    
                    Toggle("Check for updates automatically", isOn: .constant(true))
                        .disabled(true)
                        .help("Updates are checked every 24 hours")
                    
                    Toggle("Restore last session paths on launch", isOn: $preferences.restoreLastSession)
                        .help("Automatically reload the source and destination folders from your last session")
                    
                    Toggle("Show welcome screen on first launch", isOn: $preferences.showWelcomeOnLaunch)
                        .help("Display the welcome guide for new users")
                }
                .padding(.vertical, 8)
            }
            
            Divider()
            
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("File Handling")
                        .font(.headline)
                    
                    Toggle("Exclude cache files by default", isOn: $preferences.excludeCacheFiles)
                        .help("Skip Lightroom previews, Capture One cache, and similar files")
                    
                    Toggle("Skip hidden files", isOn: $preferences.skipHiddenFiles)
                        .help("Ignore .DS_Store, ._* files, and other system files")
                    
                    HStack {
                        Text("Default file type filter:")
                            .frame(width: 150, alignment: .trailing)
                        
                        Picker("", selection: $preferences.defaultFileTypeFilter) {
                            Text("All Files").tag("all")
                            Text("Photos Only").tag("photos")
                            Text("RAW Only").tag("raw")
                            Text("Videos Only").tag("videos")
                        }
                        .pickerStyle(MenuPickerStyle())
                        .frame(width: 150)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .padding()
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
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("System Information")
                        .font(.headline)
                    
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Processor:")
                                    .foregroundColor(.secondary)
                                    .frame(width: 100, alignment: .trailing)
                                Text(systemInfo?.processorName ?? "Unknown")
                                    .fontWeight(.medium)
                            }
                            
                            HStack {
                                Text("Cores:")
                                    .foregroundColor(.secondary)
                                    .frame(width: 100, alignment: .trailing)
                                if let info = systemInfo {
                                    if info.performanceCores > 0 {
                                        Text("\(info.cpuCores) total (\(info.performanceCores) performance, \(info.efficiencyCores) efficiency)")
                                    } else {
                                        Text("\(info.cpuCores)")
                                    }
                                }
                            }
                            
                            HStack {
                                Text("RAM:")
                                    .foregroundColor(.secondary)
                                    .frame(width: 100, alignment: .trailing)
                                if let info = systemInfo {
                                    Text(ByteCountFormatter.string(fromByteCount: info.totalRAM, countStyle: .binary))
                                }
                            }
                            
                            HStack {
                                Text("Neural Engine:")
                                    .foregroundColor(.secondary)
                                    .frame(width: 100, alignment: .trailing)
                                if SystemCapabilities.shared.hasNeuralEngine {
                                    Label("Available", systemImage: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                } else {
                                    Text("Not Available")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(8)
                    }
                }
                .padding(.vertical, 8)
            }
            
            Divider()
            
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Vision Framework")
                        .font(.headline)
                    
                    Text("Future feature for intelligent photo analysis")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Toggle("Enable Vision Framework features", isOn: $preferences.enableVisionFramework)
                        .disabled(true) // Not implemented yet
                        .help("Coming in v1.3 - Intelligent photo search and organization")
                        .onChange(of: preferences.enableVisionFramework) { oldValue, newValue in
                            if !SystemCapabilities.shared.isAppleSilicon && newValue {
                                showIntelWarning = true
                            } else if SystemCapabilities.shared.isAppleSilicon && !newValue {
                                showAppleSiliconWarning = true
                            }
                        }
                    
                    HStack {
                        Text("Processing priority:")
                            .frame(width: 130, alignment: .trailing)
                        
                        Picker("", selection: $preferences.visionProcessingPriority) {
                            Text("Low").tag("low")
                            Text("Normal").tag("normal")
                            Text("High").tag("high")
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .frame(width: 200)
                        .disabled(true) // Not implemented yet
                    }
                }
                .padding(.vertical, 8)
            }
            
            Divider()
            
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("System Behavior")
                        .font(.headline)
                    
                    Toggle("Prevent sleep during backup", isOn: $preferences.preventSleepDuringBackup)
                        .help("Keep your Mac awake while backup is running")
                    
                    Toggle("Show notification when backup completes", isOn: $preferences.showNotificationOnComplete)
                        .help("Display a system notification when backup finishes")
                }
                .padding(.vertical, 8)
            }
        }
        .padding()
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
    
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Operational Logs")
                        .font(.headline)
                    
                    Text("Debug and error logs for troubleshooting")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Text("Minimum log level:")
                            .frame(width: 130, alignment: .trailing)
                        
                        Picker("", selection: $preferences.minimumLogLevel) {
                            Text("Debug").tag(0)
                            Text("Info").tag(1)
                            Text("Warning").tag(2)
                            Text("Error").tag(3)
                            Text("Critical").tag(4)
                        }
                        .pickerStyle(MenuPickerStyle())
                        .frame(width: 120)
                    }
                    
                    Toggle("Log to Console.app", isOn: $preferences.enableConsoleLogging)
                        .help("Send logs to macOS Console for debugging")
                    
                    Toggle("Enable debug menu items", isOn: $preferences.enableDebugMenu)
                        .help("Show additional debugging options in menus")
                    
                    HStack {
                        Text("Keep operational logs for:")
                            .frame(width: 160, alignment: .trailing)
                        
                        Picker("", selection: $preferences.operationalLogRetention) {
                            Text("7 days").tag(7)
                            Text("14 days").tag(14)
                            Text("30 days").tag(30)
                            Text("60 days").tag(60)
                        }
                        .pickerStyle(MenuPickerStyle())
                        .frame(width: 100)
                    }
                }
                .padding(.vertical, 8)
            }
            
            Divider()
            
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Backup History")
                        .font(.headline)
                    
                    Text("ImageIntact maintains a local, private record of all your backups on this Mac to help you locate files in the future. This data never leaves your computer.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    HStack(spacing: 12) {
                        Button("View Backup History...") {
                            // TODO: Implement backup history viewer
                            logInfo("View Backup History clicked - not yet implemented")
                        }
                        .disabled(true)
                        
                        Button("Export Backup Catalog...") {
                            // TODO: Implement catalog export
                            logInfo("Export Backup Catalog clicked - not yet implemented")
                        }
                        .disabled(true)
                    }
                    
                    HStack {
                        Text("Storage location:")
                            .foregroundColor(.secondary)
                        Text("~/Library/Application Support/ImageIntact/")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }
            
            Divider()
            
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Privacy")
                        .font(.headline)
                    
                    Toggle("Anonymize paths when exporting logs", isOn: $preferences.anonymizePathsInExport)
                        .help("Replace usernames and volume names with placeholders in exported logs")
                    
                    Button("Clear Operational Logs") {
                        showClearConfirmation = true
                    }
                    .help("Remove debug logs while keeping backup history")
                }
                .padding(.vertical, 8)
            }
        }
        .padding()
        .alert("Clear Operational Logs?", isPresented: $showClearConfirmation) {
            Button("Clear", role: .destructive) {
                ApplicationLogger.shared.cleanupOldLogs(daysToKeep: 0)
                logInfo("Operational logs cleared by user")
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will remove all debug and error logs. Your backup history will be preserved.")
        }
    }
}

// MARK: - Advanced Tab

struct AdvancedPreferencesView: View {
    @ObservedObject private var preferences = PreferencesManager.shared
    
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Experimental Features")
                        .font(.headline)
                    
                    Toggle("Enable smart duplicate detection", isOn: $preferences.enableSmartDuplicateDetection)
                        .disabled(true)
                        .help("Coming soon - Detect and skip files that are already backed up")
                    
                    Toggle("Show technical details during backup", isOn: $preferences.showTechnicalDetails)
                        .help("Display additional technical information in the progress view")
                }
                .padding(.vertical, 8)
            }
            
            Divider()
            
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Safety Confirmations")
                        .font(.headline)
                    
                    Toggle("Require confirmation for large backups", isOn: $preferences.requireConfirmationLargeBackup)
                        .help("Ask for confirmation before starting backups over the threshold")
                    
                    HStack {
                        Text("Large backup threshold:")
                            .frame(width: 150, alignment: .trailing)
                        
                        TextField("", value: $preferences.largeBackupThresholdGB, format: .number)
                            .frame(width: 60)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .disabled(!preferences.requireConfirmationLargeBackup)
                        
                        Text("GB")
                    }
                    
                    Toggle("Show summary before starting backup", isOn: $preferences.showPreflightSummary)
                        .help("Display a summary of what will be backed up before starting")
                }
                .padding(.vertical, 8)
            }
            
            Divider()
            
            HStack {
                Spacer()
                Button("Reset to Defaults") {
                    preferences.resetToDefaults()
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 8)
        }
        .padding()
    }
}

// MARK: - Preview

struct PreferencesView_Previews: PreviewProvider {
    static var previews: some View {
        PreferencesView()
    }
}