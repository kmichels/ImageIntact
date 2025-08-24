//
//  PresetSelectionSheet.swift
//  ImageIntact
//
//  Sheet for selecting backup presets with detailed descriptions
//

import SwiftUI

struct PresetSelectionSheet: View {
    @Bindable var backupManager: BackupManager
    @ObservedObject var presetManager: BackupPresetManager
    @Environment(\.dismiss) var dismiss
    
    @State private var selectedPresetID: UUID?
    @State private var hoveredPresetID: UUID?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text("Select Backup Preset")
                    .font(.headline)
                Text("Choose a preset configuration for your backup workflow")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            
            Divider()
            
            // Content
            HStack(spacing: 0) {
                // Preset list
                ScrollView {
                    VStack(spacing: 2) {
                        // Built-in presets
                        Section {
                            ForEach(presetManager.presets.filter { $0.isBuiltIn }) { preset in
                                PresetSelectionRow(
                                    preset: preset,
                                    isSelected: selectedPresetID == preset.id,
                                    isHovered: hoveredPresetID == preset.id,
                                    action: { selectedPresetID = preset.id }
                                )
                                .onHover { hovering in
                                    hoveredPresetID = hovering ? preset.id : nil
                                }
                            }
                        } header: {
                            HStack {
                                Text("BUILT-IN PRESETS")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                        }
                        
                        // Custom presets if any
                        let customPresets = presetManager.presets.filter { !$0.isBuiltIn }
                        if !customPresets.isEmpty {
                            Section {
                                ForEach(customPresets) { preset in
                                    PresetSelectionRow(
                                        preset: preset,
                                        isSelected: selectedPresetID == preset.id,
                                        isHovered: hoveredPresetID == preset.id,
                                        action: { selectedPresetID = preset.id }
                                    )
                                    .onHover { hovering in
                                        hoveredPresetID = hovering ? preset.id : nil
                                    }
                                }
                            } header: {
                                HStack {
                                    Text("CUSTOM PRESETS")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .padding(.top, 8)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                .frame(width: 300)
                .background(Color(NSColor.controlBackgroundColor))
                
                Divider()
                
                // Details panel
                if let selectedID = selectedPresetID,
                   let preset = presetManager.presets.first(where: { $0.id == selectedID }) {
                    PresetDetailView(preset: preset)
                        .frame(maxWidth: .infinity)
                } else {
                    VStack {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("Select a preset to view details")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(height: 400)
            
            Divider()
            
            // Footer
            HStack {
                Button("Manage Presets...") {
                    // TODO: Open preset management
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Apply") {
                    if let selectedID = selectedPresetID,
                       let preset = presetManager.presets.first(where: { $0.id == selectedID }) {
                        presetManager.applyPreset(preset, to: backupManager)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedPresetID == nil)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 700, height: 500)
        .onAppear {
            // Pre-select current preset if any
            selectedPresetID = presetManager.selectedPreset?.id
        }
    }
}

// MARK: - Preset Selection Row
struct PresetSelectionRow: View {
    let preset: BackupPreset
    let isSelected: Bool
    let isHovered: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: preset.icon)
                    .font(.title2)
                    .foregroundColor(isSelected ? .white : .accentColor)
                    .frame(width: 30)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(isSelected ? .white : .primary)
                    
                    Text(getShortDescription())
                        .font(.caption)
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor : (isHovered ? Color.gray.opacity(0.1) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }
    
    private func getShortDescription() -> String {
        let filter = preset.fileTypeFilter.description
        let strategy = preset.strategy.rawValue
        return "\(filter) • \(strategy)"
    }
}

// MARK: - Preset Detail View
struct PresetDetailView: View {
    let preset: BackupPreset
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    Image(systemName: preset.icon)
                        .font(.largeTitle)
                        .foregroundColor(.accentColor)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(preset.name)
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text(getDetailedDescription())
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                
                // Configuration details
                VStack(alignment: .leading, spacing: 16) {
                    DetailSection(title: "Backup Strategy", icon: "arrow.triangle.2.circlepath") {
                        HStack {
                            Text(preset.strategy.rawValue)
                                .fontWeight(.medium)
                            Text("•")
                                .foregroundColor(.secondary)
                            Text(preset.strategy.description)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    DetailSection(title: "File Types", icon: "doc.on.doc") {
                        Text(preset.fileTypeFilter.description)
                            .fontWeight(.medium)
                    }
                    
                    DetailSection(title: "Performance", icon: "speedometer") {
                        HStack {
                            Text(preset.performanceMode.displayName)
                                .fontWeight(.medium)
                            Text("•")
                                .foregroundColor(.secondary)
                            Text(preset.performanceMode.description)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    DetailSection(title: "Schedule", icon: "clock") {
                        HStack {
                            Text(preset.schedule.displayName)
                                .fontWeight(.medium)
                            Text("•")
                                .foregroundColor(.secondary)
                            Text(preset.schedule.description)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    DetailSection(title: "Destinations", icon: "externaldrive.badge.checkmark") {
                        Text("\(preset.destinationCount) \(preset.destinationCount == 1 ? "destination" : "destinations")")
                            .fontWeight(.medium)
                    }
                    
                    if preset.excludeCacheFiles || preset.skipHiddenFiles || preset.preventSleep || preset.showNotification {
                        DetailSection(title: "Options", icon: "gearshape") {
                            VStack(alignment: .leading, spacing: 4) {
                                if preset.excludeCacheFiles {
                                    Label("Excludes cache files", systemImage: "xmark.circle")
                                        .font(.caption)
                                }
                                if preset.skipHiddenFiles {
                                    Label("Skips hidden files", systemImage: "eye.slash")
                                        .font(.caption)
                                }
                                if preset.preventSleep {
                                    Label("Prevents sleep during backup", systemImage: "wake")
                                        .font(.caption)
                                }
                                if preset.showNotification {
                                    Label("Shows completion notification", systemImage: "bell")
                                        .font(.caption)
                                }
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }
    
    private func getDetailedDescription() -> String {
        switch preset.name {
        case "Daily Workflow":
            return "Perfect for daily photography work. Backs up only image files incrementally with balanced speed and verification."
        case "Travel Backup":
            return "Optimized for on-location backup. Focuses on RAW files with fast processing and automatic start on drive connect."
        case "Client Delivery":
            return "Ensures perfect copies for client delivery. Creates exact mirrors of processed images with full verification."
        case "Archive Master":
            return "Comprehensive archival solution. Backs up everything with maximum verification to multiple destinations for long-term preservation."
        case "Video Project":
            return "Handles large video files efficiently. Fast incremental backup without verification bottlenecks."
        case "Quick Mirror":
            return "When you need a quick exact copy. Skips verification for maximum speed."
        default:
            return preset.isBuiltIn ? "Built-in preset configuration" : "Custom preset configuration"
        }
    }
}

// MARK: - Detail Section
struct DetailSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundColor(.secondary)
            
            content()
                .padding(.leading, 20)
        }
    }
}