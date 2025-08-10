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
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }
}