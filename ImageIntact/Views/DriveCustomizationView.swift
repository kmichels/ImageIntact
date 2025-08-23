//
//  DriveCustomizationView.swift
//  ImageIntact
//
//  Allows users to customize drive settings and appearance
//

import SwiftUI

struct DriveCustomizationView: View {
    let drive: DriveIdentity
    @Environment(\.dismiss) var dismiss
    @ObservedObject var identityManager = DriveIdentityManager.shared
    
    @State private var customName: String = ""
    @State private var selectedEmoji: String = ""
    @State private var physicalLocation: String = ""
    @State private var notes: String = ""
    @State private var isPreferred: Bool = false
    @State private var autoStart: Bool = false
    @State private var showingEmojiPicker = false
    
    private let availableEmojis = ["💾", "💿", "📀", "💽", "🗄️", "🗂️", "📁", "💻", "🖥️", "⚡", "🔌", "📱", "🏠", "🏢", "☁️", "🔒", "🛡️", "✅", "🎯", "🚀"]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text("Customize Drive")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                HStack {
                    Text(selectedEmoji)
                        .font(.system(size: 32))
                    
                    VStack(alignment: .leading) {
                        Text(drive.deviceModel ?? "Unknown Drive")
                            .font(.system(size: 13, weight: .medium))
                        
                        if let uuid = drive.volumeUUID {
                            Text("UUID: \(uuid)")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.top, 8)
            }
            .padding()
            
            Divider()
            
            // Form
            Form {
                Section("Identification") {
                    HStack {
                        Text("Custom Name:")
                            .frame(width: 100, alignment: .trailing)
                        TextField("My Backup Drive", text: $customName)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    HStack {
                        Text("Icon:")
                            .frame(width: 100, alignment: .trailing)
                        
                        Button(action: { showingEmojiPicker.toggle() }) {
                            Text(selectedEmoji)
                                .font(.system(size: 24))
                                .frame(width: 40, height: 40)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        
                        if showingEmojiPicker {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(availableEmojis, id: \.self) { emoji in
                                        Button(action: {
                                            selectedEmoji = emoji
                                            showingEmojiPicker = false
                                        }) {
                                            Text(emoji)
                                                .font(.system(size: 20))
                                                .frame(width: 32, height: 32)
                                                .background(selectedEmoji == emoji ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.1))
                                                .cornerRadius(6)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 4)
                            }
                            .frame(height: 40)
                        }
                    }
                    
                    HStack {
                        Text("Location:")
                            .frame(width: 100, alignment: .trailing)
                        TextField("Office, Home, Portable, etc.", text: $physicalLocation)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                
                Section("Preferences") {
                    Toggle(isOn: $isPreferred) {
                        Text("Preferred Backup Drive")
                            .help("This drive will be suggested first when selecting backup destinations")
                    }
                    .toggleStyle(.checkbox)
                    
                    Toggle(isOn: $autoStart) {
                        Text("Auto-start Backup When Connected")
                            .help("Automatically begin backup when this drive is connected")
                    }
                    .toggleStyle(.checkbox)
                }
                
                Section("Notes") {
                    VStack(alignment: .leading) {
                        Text("Additional Notes:")
                            .font(.system(size: 12, weight: .medium))
                        
                        TextEditor(text: $notes)
                            .font(.system(size: 12))
                            .frame(height: 60)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                    }
                }
                
                // Drive Statistics
                Section("Statistics") {
                    HStack {
                        Text("First Seen:")
                            .frame(width: 100, alignment: .trailing)
                            .foregroundColor(.secondary)
                        Text(formatDate(drive.firstSeen))
                    }
                    
                    HStack {
                        Text("Last Seen:")
                            .frame(width: 100, alignment: .trailing)
                            .foregroundColor(.secondary)
                        Text(formatDate(drive.lastSeen))
                    }
                    
                    HStack {
                        Text("Total Backups:")
                            .frame(width: 100, alignment: .trailing)
                            .foregroundColor(.secondary)
                        Text("\(drive.totalBackups)")
                    }
                    
                    HStack {
                        Text("Data Written:")
                            .frame(width: 100, alignment: .trailing)
                            .foregroundColor(.secondary)
                        Text(formatBytes(drive.totalBytesWritten))
                    }
                    
                    if let healthStatus = drive.healthStatus {
                        HStack {
                            Text("Health Status:")
                                .frame(width: 100, alignment: .trailing)
                                .foregroundColor(.secondary)
                            Text(healthStatus)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .padding()
            
            Divider()
            
            // Buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button("Save") {
                    saveDriveSettings()
                    dismiss()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 500, height: 600)
        .onAppear {
            loadCurrentSettings()
        }
    }
    
    // MARK: - Methods
    
    private func loadCurrentSettings() {
        customName = drive.userLabel ?? ""
        selectedEmoji = drive.emoji ?? "💾"
        physicalLocation = drive.physicalLocation ?? ""
        notes = drive.notes ?? ""
        isPreferred = drive.isPreferredBackup
        autoStart = drive.autoStartBackup
    }
    
    private func saveDriveSettings() {
        identityManager.updateDriveCustomization(
            drive,
            name: customName.isEmpty ? nil : customName,
            emoji: selectedEmoji.isEmpty ? nil : selectedEmoji,
            location: physicalLocation.isEmpty ? nil : physicalLocation,
            notes: notes.isEmpty ? nil : notes
        )
        
        identityManager.setDrivePreferences(
            drive,
            isPreferred: isPreferred,
            autoStart: autoStart
        )
    }
    
    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "Unknown" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}