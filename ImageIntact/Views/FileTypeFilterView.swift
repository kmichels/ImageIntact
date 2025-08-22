//
//  FileTypeFilterView.swift
//  ImageIntact
//
//  UI for selecting file types to backup
//

import SwiftUI

struct FileTypeFilterView: View {
    @Bindable var backupManager: BackupManager
    @State private var showFilterSheet = false
    @State private var selectedTypes: Set<ImageFileType> = []
    @State private var isInitialized = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Current filter indicator
            HStack(spacing: 6) {
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
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isFilterActive ? Color.accentColor.opacity(0.1) : Color.gray.opacity(0.1))
            )
            .onTapGesture {
                showFilterSheet = true
            }
            
            // Preset buttons
            Menu {
                Button("All Files") {
                    applyPreset(.allFiles)
                }
                Divider()
                Button("RAW Only") {
                    applyPreset(.rawOnly)
                }
                Button("Photos Only") {
                    applyPreset(.photosOnly)
                }
                Button("Videos Only") {
                    applyPreset(.videosOnly)
                }
            } label: {
                Label("Presets", systemImage: "line.3.horizontal.decrease.circle")
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Quick filter presets")
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
    
    private func initializeSelectedTypes() {
        // Initialize selected types from current filter
        if !backupManager.fileTypeFilter.includedExtensions.isEmpty {
            // Try to determine which types are selected based on extensions
            var types = Set<ImageFileType>()
            for type in ImageFileType.allCases {
                // Check if any of this type's extensions are in the filter
                if !type.extensions.intersection(backupManager.fileTypeFilter.includedExtensions).isEmpty {
                    types.insert(type)
                }
            }
            selectedTypes = types
        } else {
            // No filter active - select all scanned types
            selectedTypes = Set(backupManager.sourceFileTypes.keys)
        }
    }
    
    private func clearFilter() {
        backupManager.fileTypeFilter = FileTypeFilter()
        selectedTypes = Set(backupManager.sourceFileTypes.keys)
        
        // Save preference
        PreferencesManager.shared.defaultFileTypeFilter = "all"
    }
    
    private func applyPreset(_ preset: FileTypeFilter) {
        backupManager.fileTypeFilter = preset
        
        // Save preference based on preset type
        if preset.isRawOnly {
            PreferencesManager.shared.defaultFileTypeFilter = "raw"
        } else if preset.isPhotosOnly {
            PreferencesManager.shared.defaultFileTypeFilter = "photos"
        } else if preset.isVideosOnly {
            PreferencesManager.shared.defaultFileTypeFilter = "videos"
        } else if preset.includedExtensions.isEmpty {
            PreferencesManager.shared.defaultFileTypeFilter = "all"
        }
        
        // Update selected types to match preset
        if preset.includedExtensions.isEmpty {
            // "All Files" preset - select everything
            selectedTypes = Set(backupManager.sourceFileTypes.keys)
        } else {
            // Filter preset - only select types that exist in source AND match the preset
            var types = Set<ImageFileType>()
            for (type, _) in backupManager.sourceFileTypes {
                // Check if this type's extensions overlap with the preset's included extensions
                if !type.extensions.intersection(preset.includedExtensions).isEmpty {
                    types.insert(type)
                }
            }
            selectedTypes = types
            
            // If no matching types found, it means the preset doesn't match any files in source
            // In this case, clear the filter to avoid backing up nothing
            if selectedTypes.isEmpty {
                logWarning("Preset '\(preset.includedExtensions)' doesn't match any files in source")
                backupManager.fileTypeFilter = FileTypeFilter() // Reset to all files
                selectedTypes = Set(backupManager.sourceFileTypes.keys)
            }
        }
    }
    
    private func applyCustomFilter() {
        backupManager.fileTypeFilter = FileTypeFilter.from(
            scanResults: backupManager.sourceFileTypes,
            selectedTypes: selectedTypes
        )
        
        // For custom filters, we don't update the default preference
        // since it's specific to the current selection
    }
}

// MARK: - File Type Selection Sheet

struct FileTypeSelectionSheet: View {
    @Bindable var backupManager: BackupManager
    @Binding var selectedTypes: Set<ImageFileType>
    let onApply: () -> Void
    @Environment(\.dismiss) var dismiss
    
    // Group types by category
    private var photoTypes: [(ImageFileType, Int)] {
        backupManager.sourceFileTypes
            .filter { isPhotoType($0.key) }
            .sorted { $0.value > $1.value }
            .map { ($0.key, $0.value) }
    }
    
    private var videoTypes: [(ImageFileType, Int)] {
        backupManager.sourceFileTypes
            .filter { isVideoType($0.key) }
            .sorted { $0.value > $1.value }
            .map { ($0.key, $0.value) }
    }
    
    private var sidecarTypes: [(ImageFileType, Int)] {
        backupManager.sourceFileTypes
            .filter { isSidecarType($0.key) }
            .sorted { $0.value > $1.value }
            .map { ($0.key, $0.value) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Select File Types to Backup")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Quick select buttons
                    HStack(spacing: 8) {
                        Button("Select All") {
                            selectedTypes = Set(backupManager.sourceFileTypes.keys)
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Select None") {
                            selectedTypes = []
                        }
                        .buttonStyle(.bordered)
                        
                        Spacer()
                        
                        Text("\(selectedTypes.count) of \(backupManager.sourceFileTypes.count) selected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    
                    // Photo types
                    if !photoTypes.isEmpty {
                        TypeCategorySection(
                            title: "Photos",
                            icon: "photo",
                            types: photoTypes,
                            selectedTypes: $selectedTypes
                        )
                    }
                    
                    // Video types
                    if !videoTypes.isEmpty {
                        TypeCategorySection(
                            title: "Videos",
                            icon: "video",
                            types: videoTypes,
                            selectedTypes: $selectedTypes
                        )
                    }
                    
                    // Sidecar types
                    if !sidecarTypes.isEmpty {
                        TypeCategorySection(
                            title: "Sidecar Files",
                            icon: "doc.badge.gearshape",
                            types: sidecarTypes,
                            selectedTypes: $selectedTypes
                        )
                    }
                }
                .padding(.vertical)
            }
            
            Divider()
            
            // Footer
            HStack {
                Text(summaryText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button("Apply") {
                    onApply()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedTypes.isEmpty)
            }
            .padding()
        }
        .frame(width: 500, height: 600)
    }
    
    private var summaryText: String {
        let totalFiles = backupManager.sourceFileTypes.values.reduce(0, +)
        let selectedFiles = selectedTypes.reduce(0) { sum, type in
            sum + (backupManager.sourceFileTypes[type] ?? 0)
        }
        
        if selectedTypes.isEmpty {
            return "No files will be backed up"
        } else if selectedTypes.count == backupManager.sourceFileTypes.count {
            return "All \(totalFiles) files will be backed up"
        } else {
            // Build a summary of selected types
            var selectedSummary: [ImageFileType: Int] = [:]
            for type in selectedTypes {
                if let count = backupManager.sourceFileTypes[type] {
                    selectedSummary[type] = count
                }
            }
            let typesSummary = ImageFileScanner.formatScanResults(selectedSummary, groupRaw: false)
            return "\(selectedFiles) of \(totalFiles) files will be backed up • \(typesSummary)"
        }
    }
    
    private func isPhotoType(_ type: ImageFileType) -> Bool {
        // Check if it's a photo format (including RAW)
        let photoExtensions = FileTypeFilter.photosOnly.includedExtensions
        return !type.extensions.intersection(photoExtensions).isEmpty
    }
    
    private func isVideoType(_ type: ImageFileType) -> Bool {
        // Check if it's a video format
        let videoExtensions = FileTypeFilter.videosOnly.includedExtensions
        return !type.extensions.intersection(videoExtensions).isEmpty
    }
    
    private func isSidecarType(_ type: ImageFileType) -> Bool {
        // Types that are neither photo nor video (metadata files)
        return !isPhotoType(type) && !isVideoType(type)
    }
}

// MARK: - Type Category Section

struct TypeCategorySection: View {
    let title: String
    let icon: String
    let types: [(ImageFileType, Int)]
    @Binding var selectedTypes: Set<ImageFileType>
    
    private var allSelected: Bool {
        types.allSatisfy { selectedTypes.contains($0.0) }
    }
    
    private var someSelected: Bool {
        types.contains { selectedTypes.contains($0.0) } && !allSelected
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Category header with select all
            HStack {
                Button(action: toggleCategory) {
                    HStack(spacing: 6) {
                        Image(systemName: allSelected ? "checkmark.square.fill" : 
                                (someSelected ? "minus.square.fill" : "square"))
                            .foregroundColor(someSelected ? .accentColor : .primary)
                        
                        Label(title, systemImage: icon)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Text("\(types.count) types")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            
            // Individual type checkboxes
            VStack(alignment: .leading, spacing: 4) {
                ForEach(types, id: \.0) { type, count in
                    FileTypeSelectionRow(
                        type: type,
                        count: count,
                        isSelected: selectedTypes.contains(type),
                        onToggle: {
                            if selectedTypes.contains(type) {
                                selectedTypes.remove(type)
                            } else {
                                selectedTypes.insert(type)
                            }
                        }
                    )
                }
            }
            .padding(.leading, 28)
        }
    }
    
    private func toggleCategory() {
        if allSelected {
            // Deselect all in category
            for (type, _) in types {
                selectedTypes.remove(type)
            }
        } else {
            // Select all in category
            for (type, _) in types {
                selectedTypes.insert(type)
            }
        }
    }
}

// MARK: - File Type Selection Row

struct FileTypeSelectionRow: View {
    let type: ImageFileType
    let count: Int
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                
                Text(type.rawValue)
                    .foregroundColor(.primary)
                
                Text("(\(count))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Show primary extensions
                Text(type.extensions.prefix(3).joined(separator: ", "))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? Color.accentColor.opacity(0.05) : Color.clear)
        )
    }
}