import SwiftUI

struct DestinationSection: View {
    @Bindable var backupManager: BackupManager
    @FocusState.Binding var focusedField: ContentView.FocusField?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Destinations", systemImage: "arrow.triangle.branch")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                if backupManager.destinationURLs.count < 4 {
                    Button(action: {
                        backupManager.addDestination()
                    }) {
                        Label("Add", systemImage: "plus.circle.fill")
                            .font(.footnote)
                    }
                    .keyboardShortcut("+", modifiers: .command)
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }
            }
            
            VStack(spacing: 8) {
                ForEach(0..<backupManager.destinationURLs.count, id: \.self) { index in
                    FolderRow(
                        title: "Destination \(index + 1)",
                        selectedURL: Binding(
                            get: { backupManager.destinationURLs[index] },
                            set: { newValue in
                                if let url = newValue {
                                    backupManager.setDestination(url, at: index)
                                }
                            }
                        ),
                        onClear: {
                            backupManager.clearDestination(at: index)
                        },
                        onSelect: { url in
                            // Validation handled in backupManager.setDestination()
                        }
                    )
                    .focused($focusedField, equals: .destination(index))
                    .onTapGesture {
                        focusedField = .destination(index)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
    }
}