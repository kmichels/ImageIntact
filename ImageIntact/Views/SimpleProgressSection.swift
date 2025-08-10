import SwiftUI

struct SimpleProgressSection: View {
    @Bindable var backupManager: BackupManager
    
    var body: some View {
        if !backupManager.statusMessage.isEmpty || backupManager.isProcessing {
            VStack(alignment: .leading, spacing: 12) {
                Divider()
                    .padding(.horizontal, 20)
                
                if backupManager.isProcessing && backupManager.totalFiles > 0 {
                    // Simple overall progress
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Backup Progress")
                                .font(.headline)
                            
                            Spacer()
                            
                            Button(action: {
                                backupManager.cancelOperation()
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                    .imageScale(.large)
                            }
                            .buttonStyle(.plain)
                            .help("Cancel backup")
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            // Overall progress
                            HStack {
                                Text("Files: \(backupManager.currentFileIndex)/\(backupManager.totalFiles)")
                                    .font(.subheadline)
                                
                                Spacer()
                                
                                if backupManager.copySpeed > 0 {
                                    Text("\(String(format: "%.1f", backupManager.copySpeed)) MB/s")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            ProgressView(value: Double(backupManager.currentFileIndex), total: Double(backupManager.totalFiles))
                                .progressViewStyle(.linear)
                            
                            HStack {
                                if !backupManager.currentFileName.isEmpty {
                                    Text("Current: \(backupManager.currentFileName)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                
                                Spacer()
                                
                                if !backupManager.currentDestinationName.isEmpty {
                                    Text("→ \(backupManager.currentDestinationName)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .padding(16)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    .padding(.horizontal, 20)
                } else {
                    HStack {
                        if backupManager.isProcessing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .scaleEffect(0.8)
                        }
                        
                        Text(backupManager.statusMessage)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                }
            }
            .transition(.opacity)
        }
    }
}