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
                            .font(.system(size: 11))
                    }
                    .keyboardShortcut("+", modifiers: .command)
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                    .accessibilityLabel("Add destination folder")
                    .help("Add another backup destination")
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
                        
                        // Show drive analysis with new DriveStatusView if we have drive info
                        if let _ = item.url, 
                           let driveInfo = backupManager.destinationDriveInfo[item.id] {
                            DriveStatusView(driveInfo: driveInfo)
                                .padding(.leading, 12)
                                .padding(.top, 4)
                        } else if let estimate = backupManager.getDestinationEstimate(at: index) {
                            // Fallback to old estimate display if no drive info
                            HStack(spacing: 8) {
                                Text(estimate)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                
                                // Show disk space status if we have backup size info
                                if let url = item.url, backupManager.totalBytesToCopy > 0 {
                                    let spaceCheck = DiskSpaceChecker.checkDestinationSpace(
                                        destination: url,
                                        requiredBytes: backupManager.totalBytesToCopy
                                    )
                                    
                                    if spaceCheck.error != nil {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.system(size: 10))
                                            .foregroundColor(.red)
                                            .help("Insufficient space for backup")
                                    } else if spaceCheck.willHaveLessThan10PercentFree {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.system(size: 10))
                                            .foregroundColor(.orange)
                                            .help("Drive will be less than 10% free after backup")
                                    } else {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 10))
                                            .foregroundColor(.green)
                                            .help("\(spaceCheck.spaceInfo.formattedAvailable) available")
                                    }
                                }
                            }
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