//
//  BackupPresetView.swift
//  ImageIntact
//
//  UI for selecting and managing backup presets
//

import SwiftUI

struct BackupPresetView: View {
    @Bindable var backupManager: BackupManager
    @StateObject private var presetManager = BackupPresetManager.shared
    @State private var showingCreateSheet = false
    @State private var showingEditSheet = false
    @State private var editingPreset: BackupPreset?
    @State private var newPresetName = ""
    
    var body: some View {
        HStack(spacing: 12) {
            // Preset selector
            Menu {
                // Built-in presets section
                Section("Built-in Presets") {
                    ForEach(presetManager.presets.filter { $0.isBuiltIn }) { preset in
                        Button(action: { applyPreset(preset) }) {
                            Label(preset.name, systemImage: preset.icon)
                        }
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
                
                // Save current as preset
                Button(action: { showingCreateSheet = true }) {
                    Label("Save Current Settings...", systemImage: "plus.circle")
                }
                
                // Manage presets
                Button(action: { showingEditSheet = true }) {
                    Label("Manage Presets...", systemImage: "gear")
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: presetManager.selectedPreset?.icon ?? "doc.text")
                        .font(.system(size: 11))
                    Text(presetManager.selectedPreset?.name ?? "Select Preset")
                        .font(.system(size: 11))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.1))
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Quick backup configuration presets")
            
            // Current configuration indicator
            if let preset = presetManager.selectedPreset {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        // Strategy
                        Label(preset.strategy.displayName, systemImage: preset.strategy.icon)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        
                        Text("•")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        
                        // Performance
                        Label(preset.performanceMode.displayName, systemImage: preset.performanceMode.icon)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    
                    // File filter
                    Text(preset.fileTypeFilter.description)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }
        }
        .sheet(isPresented: $showingCreateSheet) {
            CreatePresetSheet(
                backupManager: backupManager,
                presetManager: presetManager,
                isPresented: $showingCreateSheet
            )
        }
        .sheet(isPresented: $showingEditSheet) {
            ManagePresetsSheet(
                presetManager: presetManager,
                isPresented: $showingEditSheet
            )
        }
    }
    
    private func applyPreset(_ preset: BackupPreset) {
        presetManager.applyPreset(preset, to: backupManager)
    }
}

// MARK: - Create Preset Sheet
struct CreatePresetSheet: View {
    let backupManager: BackupManager
    let presetManager: BackupPresetManager
    @Binding var isPresented: Bool
    
    @State private var presetName = ""
    @State private var selectedIcon = "star"
    
    private let availableIcons = [
        "star", "camera", "photo", "video", "doc.text",
        "folder", "archivebox", "lock.shield", "bolt",
        "airplane", "briefcase", "house", "building"
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text("Save Current Settings as Preset")
                    .font(.headline)
                
                Text("Your current backup configuration will be saved for quick reuse")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            
            Divider()
            
            // Form
            Form {
                Section("Preset Details") {
                    HStack {
                        Text("Name:")
                            .frame(width: 80, alignment: .trailing)
                        TextField("My Backup Preset", text: $presetName)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    HStack {
                        Text("Icon:")
                            .frame(width: 80, alignment: .trailing)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(availableIcons, id: \.self) { icon in
                                    Button(action: { selectedIcon = icon }) {
                                        Image(systemName: icon)
                                            .font(.system(size: 16))
                                            .frame(width: 32, height: 32)
                                            .background(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .fill(selectedIcon == icon ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.1))
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                
                Section("Current Configuration") {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("File Filter: \(backupManager.fileTypeFilter.description)", systemImage: "doc.text")
                            .font(.caption)
                        
                        if backupManager.excludeCacheFiles {
                            Label("Excludes cache files", systemImage: "minus.circle")
                                .font(.caption)
                        }
                        
                        Label("\(backupManager.destinationItems.count) destination(s)", systemImage: "arrow.triangle.branch")
                            .font(.caption)
                    }
                }
            }
            .formStyle(.grouped)
            
            Divider()
            
            // Buttons
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button("Save Preset") {
                    savePreset()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(presetName.isEmpty)
            }
            .padding()
        }
        .frame(width: 450, height: 350)
    }
    
    private func savePreset() {
        let preset = presetManager.createPresetFromCurrent(
            name: presetName.isEmpty ? "Custom Preset" : presetName,
            backupManager: backupManager
        )
        
        var customPreset = preset
        customPreset.icon = selectedIcon
        
        presetManager.addPreset(customPreset)
        isPresented = false
    }
}

// MARK: - Manage Presets Sheet
struct ManagePresetsSheet: View {
    @ObservedObject var presetManager: BackupPresetManager
    @Binding var isPresented: Bool
    @State private var selectedPreset: BackupPreset?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            Text("Manage Presets")
                .font(.headline)
                .padding()
            
            Divider()
            
            // Preset list
            List {
                Section("Built-in Presets") {
                    ForEach(presetManager.presets.filter { $0.isBuiltIn }) { preset in
                        PresetRow(preset: preset, isSelected: selectedPreset?.id == preset.id)
                            .onTapGesture {
                                selectedPreset = preset
                            }
                    }
                }
                
                let customPresets = presetManager.presets.filter { !$0.isBuiltIn }
                if !customPresets.isEmpty {
                    Section("Custom Presets") {
                        ForEach(customPresets) { preset in
                            PresetRow(preset: preset, isSelected: selectedPreset?.id == preset.id)
                                .onTapGesture {
                                    selectedPreset = preset
                                }
                                .contextMenu {
                                    Button("Delete", role: .destructive) {
                                        presetManager.deletePreset(preset)
                                    }
                                }
                        }
                    }
                }
            }
            .listStyle(.inset)
            .frame(height: 300)
            
            // Preset details
            if let preset = selectedPreset {
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: preset.icon)
                            .font(.title2)
                        Text(preset.name)
                            .font(.title3)
                            .fontWeight(.medium)
                        Spacer()
                        if preset.isBuiltIn {
                            Text("Built-in")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.2))
                                .cornerRadius(4)
                        }
                    }
                    
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                        GridRow {
                            Text("Strategy:")
                                .foregroundColor(.secondary)
                            Label(preset.strategy.displayName, systemImage: preset.strategy.icon)
                        }
                        GridRow {
                            Text("Schedule:")
                                .foregroundColor(.secondary)
                            Label(preset.schedule.displayName, systemImage: preset.schedule.icon)
                        }
                        GridRow {
                            Text("Performance:")
                                .foregroundColor(.secondary)
                            Label(preset.performanceMode.displayName, systemImage: preset.performanceMode.icon)
                        }
                        GridRow {
                            Text("File Filter:")
                                .foregroundColor(.secondary)
                            Text(preset.fileTypeFilter.description)
                        }
                        GridRow {
                            Text("Destinations:")
                                .foregroundColor(.secondary)
                            Text("\(preset.destinationCount)")
                        }
                    }
                    .font(.caption)
                    
                    if let lastUsed = preset.lastUsedDate {
                        Text("Last used: \(lastUsed.formatted())")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .frame(height: 120)
            }
            
            Divider()
            
            // Buttons
            HStack {
                if let preset = selectedPreset, !preset.isBuiltIn {
                    Button("Delete", role: .destructive) {
                        presetManager.deletePreset(preset)
                        selectedPreset = nil
                    }
                }
                
                Spacer()
                
                Button("Done") {
                    isPresented = false
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 500, height: 550)
    }
}

// MARK: - Preset Row
struct PresetRow: View {
    let preset: BackupPreset
    let isSelected: Bool
    
    var body: some View {
        HStack {
            Image(systemName: preset.icon)
                .font(.system(size: 14))
                .foregroundColor(isSelected ? .accentColor : .primary)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(preset.name)
                    .font(.system(size: 12, weight: .medium))
                
                Text("\(preset.strategy.displayName) • \(preset.fileTypeFilter.description)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if preset.useCount > 0 {
                Text("Used \(preset.useCount)×")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        )
    }
}