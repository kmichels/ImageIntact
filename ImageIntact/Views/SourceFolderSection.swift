import SwiftUI

struct SourceFolderSection: View {
    @Bindable var backupManager: BackupManager
    @FocusState.Binding var focusedField: ContentView.FocusField?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Source", systemImage: "folder")
                .font(.headline)
                .foregroundColor(.primary)
            
            FolderRow(
                title: "Select Source Folder",
                selectedURL: Binding(
                    get: { backupManager.sourceURL },
                    set: { newValue in
                        if let url = newValue {
                            backupManager.setSource(url)
                        }
                    }
                ),
                onClear: {
                    backupManager.sourceURL = nil
                    backupManager.sourceFileTypes = [:]
                    backupManager.scanProgress = ""
                    UserDefaults.standard.removeObject(forKey: backupManager.sourceKey)
                },
                onSelect: { url in
                    // Already handled in backupManager.setSource()
                }
            )
            .focused($focusedField, equals: .source)
            .onTapGesture {
                focusedField = .source
            }
            
            // File type summary and filter
            if backupManager.sourceURL != nil {
                VStack(alignment: .leading, spacing: 8) {
                    // File type summary
                    HStack(spacing: 4) {
                        if backupManager.isScanning {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 14, height: 14)
                        } else if !backupManager.sourceFileTypes.isEmpty {
                            Image(systemName: "photo.stack")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Text(backupManager.getFormattedFileTypeSummary())
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .animation(.easeInOut(duration: 0.2), value: backupManager.isScanning)
                    
                    // File type filter (only show after scan completes)
                    if !backupManager.sourceFileTypes.isEmpty && !backupManager.isScanning {
                        FileTypeFilterView(backupManager: backupManager)
                    }
                }
                .padding(.leading, 20)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }
}