//
//  BackupConfigurationView.swift
//  ImageIntact
//
//  Combined view for backup presets and file type filters
//

import SwiftUI

struct BackupConfigurationView: View {
    @Bindable var backupManager: BackupManager
    @StateObject private var presetManager = BackupPresetManager.shared
    @State private var showingPresetManagement = false
    @State private var showingCreatePreset = false
    @State private var showFilterSheet = false
    @State private var selectedTypes: Set<ImageFileType> = []
    @State private var isInitialized = false
    
    var body: some View {
        HStack(spacing: 8) {
            // Backup Presets Menu
            Menu {
                // Built-in presets section
                Section("Built-in Presets") {
                    ForEach(presetManager.presets.filter { $0.isBuiltIn }) { preset in
                        Button(action: { applyPreset(preset) }) {
                            Label(preset.name, systemImage: preset.icon)
                        }
                        .help(getPresetDescription(preset))
                    }
                }
                
                // Custom presets section
                let customPresets = presetManager.presets.filter { !$0.isBuiltIn }
                if !customPresets.isEmpty {
                    Section("Custom Presets") {
                        ForEach(customPresets) { preset in
                            Button(action: { applyPreset(preset) }) {
                                Label(preset.name, systemImage: preset.icon)
                            }
                        }
                    }
                }
                
                Divider()
                
                // Management options
                Button(action: { showingCreatePreset = true }) {
                    Label("Save Current Settings...", systemImage: "plus.circle")
                }
                
                Button(action: { showingPresetManagement = true }) {
                    Label("Manage Presets...", systemImage: "gear")
                }
                
                Divider()
                
                // Reset to defaults
                Button(action: resetToDefaults) {
                    Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                }
                .foregroundColor(.orange)
                
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: presetManager.selectedPreset?.icon ?? "doc.text")
                        .font(.caption)
                    Text(presetManager.selectedPreset?.name ?? "Backup Preset")
                        .font(.caption)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Quick backup configuration presets")
            
            // File Type Filter Menu
            Menu {
                Button("All Files") {
                    applyFilterPreset(.allFiles)
                }
                Divider()
                Button("RAW Only") {
                    applyFilterPreset(.rawOnly)
                }
                Button("Photos Only") {
                    applyFilterPreset(.photosOnly)
                }
                Button("Videos Only") {
                    applyFilterPreset(.videosOnly)
                }
                Divider()
                Button("Custom...") {
                    showFilterSheet = true
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.caption)
                    Text("Filter")
                        .font(.caption)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Filter which file types to backup")
            
            // Current filter status
            HStack(spacing: 4) {
                Image(systemName: filterIcon)
                    .font(.caption)
                    .foregroundColor(isFilterActive ? .accentColor : .secondary)
                Text(filterDescription)
                    .font(.caption)
                    .foregroundColor(isFilterActive ? .primary : .secondary)
                if isFilterActive {
                    Button(action: clearFilter) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear filter")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isFilterActive ? Color.accentColor.opacity(0.1) : Color.gray.opacity(0.1))
            )
            .onTapGesture {
                if !isFilterActive {
                    showFilterSheet = true
                }
            }
            .help(isFilterActive ? "Current filter: \(filterDescription)" : "Click to set custom filter")
            
            Spacer()
        }
        .sheet(isPresented: $showingCreatePreset) {
            CreatePresetSheet(
                backupManager: backupManager,
                presetManager: presetManager,
                isPresented: $showingCreatePreset
            )
        }
        .sheet(isPresented: $showingPresetManagement) {
            ManagePresetsSheet(
                presetManager: presetManager,
                isPresented: $showingPresetManagement
            )
        }
        .sheet(isPresented: $showFilterSheet) {
            FileTypeSelectionSheet(
                backupManager: backupManager,
                selectedTypes: $selectedTypes,
                onApply: applyCustomFilter
            )
        }
        .onAppear {
            if !isInitialized {
                initializeSelectedTypes()
                isInitialized = true
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var isFilterActive: Bool {
        !backupManager.fileTypeFilter.includedExtensions.isEmpty
    }
    
    private var filterIcon: String {
        if !isFilterActive {
            return "line.3.horizontal.decrease.circle"
        } else if backupManager.fileTypeFilter.isRawOnly {
            return "camera.aperture"
        } else if backupManager.fileTypeFilter.isVideosOnly {
            return "video.circle"
        } else if backupManager.fileTypeFilter.isPhotosOnly {
            return "photo.circle"
        } else {
            return "line.3.horizontal.decrease.circle.fill"
        }
    }
    
    private var filterDescription: String {
        backupManager.fileTypeFilter.description
    }
    
    // MARK: - Methods
    
    private func applyPreset(_ preset: BackupPreset) {
        presetManager.applyPreset(preset, to: backupManager)
    }
    
    private func applyFilterPreset(_ filter: FileTypeFilter) {
        backupManager.fileTypeFilter = filter
    }
    
    private func clearFilter() {
        backupManager.fileTypeFilter = FileTypeFilter()
    }
    
    private func resetToDefaults() {
        // Reset to default state
        presetManager.selectedPreset = nil
        backupManager.fileTypeFilter = FileTypeFilter()
        // Reset other settings as needed
    }
    
    private func getPresetDescription(_ preset: BackupPreset) -> String {
        switch preset.name {
        case "Daily Workflow":
            return "Incremental backup of photos only, balanced performance. Ideal for regular photographer workflow with 2 destinations."
        case "Travel Backup":
            return "Fast RAW-only backup, starts on drive connect. Perfect for on-location backup to a portable drive."
        case "Client Delivery":
            return "Mirror copy of JPEG/TIFF with full verification. Ensures exact copies for client delivery."
        case "Archive Master":
            return "Complete archive of all files with full verification to 3 destinations. For long-term preservation."
        case "Video Project":
            return "Fast incremental backup of video files. Optimized for large video projects to 2 destinations."
        case "Quick Mirror":
            return "Fast exact mirror without verification. Quick duplication when speed matters most."
        default:
            return preset.isBuiltIn ? "Built-in preset" : "Custom preset"
        }
    }
    
    private func initializeSelectedTypes() {
        if !backupManager.fileTypeFilter.includedExtensions.isEmpty {
            var types = Set<ImageFileType>()
            for type in ImageFileType.allCases {
                if !type.extensions.intersection(backupManager.fileTypeFilter.includedExtensions).isEmpty {
                    types.insert(type)
                }
            }
            selectedTypes = types
        } else {
            selectedTypes = Set(ImageFileType.allCases)
        }
    }
    
    private func applyCustomFilter() {
        if selectedTypes.isEmpty || selectedTypes.count == ImageFileType.allCases.count {
            backupManager.fileTypeFilter = FileTypeFilter()
        } else {
            var extensions = Set<String>()
            for type in selectedTypes {
                extensions.formUnion(type.extensions)
            }
            backupManager.fileTypeFilter = FileTypeFilter(extensions: extensions)
        }
    }
}