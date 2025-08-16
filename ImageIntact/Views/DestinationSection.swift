import SwiftUI

struct DestinationSection: View {
    @Bindable var backupManager: BackupManager
    @FocusState.Binding var focusedField: ContentView.FocusField?
    @State private var showingAddPicker = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Destinations", systemImage: "arrow.triangle.branch")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                if backupManager.destinationItems.count < 4 {
                    Button(action: {
                        showingAddPicker = true
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
        .fileImporter(
            isPresented: $showingAddPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    // Add new destination
                    backupManager.addDestination()
                    // Set the URL for the newly added destination
                    let newIndex = backupManager.destinationItems.count - 1
                    backupManager.setDestination(url, at: newIndex)
                }
            case .failure(let error):
                print("Failed to select destination: \(error)")
            }
        }
    }
}