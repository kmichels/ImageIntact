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
                
                if backupManager.destinationItems.count < 4 {
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
                ForEach(Array(backupManager.destinationItems.enumerated()), id: \.element.id) { index, item in
                    VStack(alignment: .leading, spacing: 4) {
                        FolderRow(
                        title: "Destination \(index + 1)",
                        selectedURL: Binding(
                            get: { 
                                item.url
                            },
                            set: { newValue in
                                if let url = newValue {
                                    backupManager.setDestination(url, at: index)
                                }
                            }
                        ),
                        onClear: {
                            backupManager.removeDestination(at: index)
                        },
                        onSelect: { url in
                            // Validation handled in backupManager.setDestination()
                        },
                        showRemoveButton: backupManager.destinationItems.count > 1
                        )
                        .focused($focusedField, equals: .destination(index))
                        .onTapGesture {
                            focusedField = .destination(index)
                        }
                        
                        // Show drive analysis and time estimate
                        if let estimate = backupManager.getDestinationEstimate(at: index) {
                            Text(estimate)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.leading, 12)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
    }
}