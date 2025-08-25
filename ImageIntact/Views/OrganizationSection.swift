import SwiftUI

struct OrganizationSection: View {
    @Bindable var backupManager: BackupManager
    @State private var showInfoPopover = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Backup Organization", systemImage: "folder.badge.gear")
                .font(.headline)
                .foregroundColor(.primary)
            
            // Inner content - indented
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Text("Organize backups in folder:")
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                    
                    TextField("Enter folder name", text: $backupManager.organizationName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 250)
                        .help("Files will be copied into this folder at each destination")
                        .onAppear {
                            // Set default if empty and source is selected
                            if backupManager.organizationName.isEmpty,
                               let sourceURL = backupManager.sourceURL {
                                backupManager.organizationName = sourceURL.lastPathComponent
                            }
                        }
                        .onChange(of: backupManager.sourceURL) { oldValue, newValue in
                            // Update organization name when source changes (only if it was using the old default)
                            if let oldURL = oldValue,
                               let newURL = newValue,
                               backupManager.organizationName == oldURL.lastPathComponent {
                                backupManager.organizationName = newURL.lastPathComponent
                            }
                        }
                    
                    Button(action: { showInfoPopover.toggle() }) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showInfoPopover, arrowEdge: .trailing) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Backup Organization")
                                .font(.headline)
                            
                            Text("Your files will be organized into a folder with this name at each destination.")
                                .font(.system(size: 12))
                                .fixedSize(horizontal: false, vertical: true)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Benefits:", systemImage: "checkmark.circle.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.green)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("• Prevents mixing files from different sources")
                                    Text("• Makes backups easier to identify")
                                    Text("• Allows multiple sources to same destination")
                                }
                                .font(.system(size: 11))
                                .padding(.leading, 20)
                            }
                            
                            if !backupManager.organizationName.isEmpty && backupManager.destinationItems.count > 0 {
                                Divider()
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Example:")
                                        .font(.system(size: 11, weight: .semibold))
                                    
                                    if let firstDest = backupManager.destinationItems.first {
                                        Text(firstDest.url?.lastPathComponent ?? "Destination")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                        HStack(spacing: 4) {
                                            Text("└")
                                                .font(.system(size: 10, design: .monospaced))
                                                .foregroundColor(.secondary)
                                            Image(systemName: "folder.fill")
                                                .font(.system(size: 10))
                                                .foregroundColor(.accentColor)
                                            Text(backupManager.organizationName)
                                                .font(.system(size: 10, weight: .medium))
                                        }
                                        .padding(.leading, 8)
                                    }
                                }
                            }
                        }
                        .padding()
                        .frame(width: 320)
                    }
                    
                    Spacer()
                }
                
                // Always show the destination structure preview
                HStack(spacing: 4) {
                    Image(systemName: "folder.badge.person.crop")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Files will be organized as:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    // Show actual destination example or placeholder
                    if let firstDest = backupManager.destinationItems.first,
                       let destURL = firstDest.url {
                        Text("\(destURL.lastPathComponent)/\(backupManager.organizationName.isEmpty ? "folder-name" : backupManager.organizationName)/")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.accentColor)
                            .fontWeight(.medium)
                    } else {
                        Text("[destination]/\(backupManager.organizationName.isEmpty ? "folder-name" : backupManager.organizationName)/")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.accentColor)
                            .fontWeight(.medium)
                    }
                    
                    Text("your-files")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
            }
            .padding(.leading, 20)
        }
        .padding(.horizontal, 20)
    }
}