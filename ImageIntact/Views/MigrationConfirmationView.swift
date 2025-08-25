import SwiftUI

struct MigrationConfirmationView: View {
    let plan: BackupMigrationDetector.MigrationPlan
    let destinationName: String
    @Binding var isPresented: Bool
    let onMigrate: () -> Void
    let onSkip: () -> Void
    
    @State private var isMigrating = false
    @State private var migrationProgress = 0
    @State private var migrationTotal = 0
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "folder.badge.questionmark")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)
                
                Text("Organize Existing Backup?")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Found existing files that match your source")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // Details
            VStack(alignment: .leading, spacing: 12) {
                DetailRow(
                    icon: "doc.on.doc",
                    label: "Files to organize:",
                    value: "\(plan.fileCount) files"
                )
                
                DetailRow(
                    icon: "arrow.up.arrow.down",
                    label: "Total size:",
                    value: formatBytes(plan.totalSize)
                )
                
                DetailRow(
                    icon: "folder",
                    label: "Move to folder:",
                    value: plan.organizationFolder
                )
                
                DetailRow(
                    icon: "externaldrive",
                    label: "Destination:",
                    value: destinationName
                )
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            
            // Explanation
            VStack(alignment: .leading, spacing: 8) {
                Label("What will happen:", systemImage: "info.circle")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("• Files will be moved (not copied) to the organized folder")
                    Text("• Each file will be verified after moving")
                    Text("• Original files will no longer be in the root folder")
                    Text("• This helps keep your backups organized by source")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 20)
            }
            
            // Progress (shown during migration)
            if isMigrating {
                VStack(spacing: 8) {
                    ProgressView(value: Double(migrationProgress), total: Double(migrationTotal))
                    Text("Moving file \(migrationProgress) of \(migrationTotal)...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
            }
            
            // Buttons
            HStack(spacing: 12) {
                Button("Skip") {
                    onSkip()
                    isPresented = false
                }
                .buttonStyle(.plain)
                .disabled(isMigrating)
                
                Spacer()
                
                Button("Keep in Root") {
                    // User wants to keep files in root, just proceed
                    isPresented = false
                }
                .disabled(isMigrating)
                
                Button(isMigrating ? "Organizing..." : "Organize Files") {
                    if !isMigrating {
                        performMigration()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isMigrating)
            }
        }
        .padding(24)
        .frame(width: 500)
    }
    
    private func performMigration() {
        isMigrating = true
        migrationTotal = plan.fileCount
        migrationProgress = 0
        
        Task {
            let detector = BackupMigrationDetector()
            
            do {
                try await detector.performMigration(plan: plan) { completed, total in
                    Task { @MainActor in
                        migrationProgress = completed
                        migrationTotal = total
                    }
                }
                
                await MainActor.run {
                    onMigrate()
                    isPresented = false
                }
            } catch {
                await MainActor.run {
                    // Show error
                    print("❌ Migration failed: \(error)")
                    isMigrating = false
                    
                    // Show error alert
                    let alert = NSAlert()
                    alert.messageText = "Migration Failed"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .critical
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
        }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

struct DetailRow: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .frame(width: 20)
            
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.system(size: 12, weight: .medium))
        }
    }
}