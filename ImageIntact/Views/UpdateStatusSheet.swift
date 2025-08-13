import SwiftUI

struct UpdateStatusSheet: View {
    let result: UpdateCheckResult
    let currentVersion: String
    let onDownload: (AppUpdate) -> Void
    let onSkipVersion: (String) -> Void
    let onCancel: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            contentView
        }
        .padding(40)
        .frame(width: 450)
        .fixedSize()
    }
    
    @ViewBuilder
    private var contentView: some View {
        switch result {
        case .checking:
            checkingView
            
        case .upToDate:
            upToDateView
            
        case .updateAvailable(let update):
            updateAvailableView(update)
            
        case .error(let error):
            errorView(error)
            
        case .downloading(let progress):
            downloadingView(progress)
        }
    }
    
    // MARK: - State Views
    
    private var checkingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.5)
            
            Text("Checking for Updates...")
                .font(.headline)
            
            Text("Connecting to GitHub...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(height: 150)
    }
    
    private var upToDateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)
            
            Text("You're up to date!")
                .font(.headline)
            
            Text("ImageIntact \(currentVersion) is the latest version available.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("OK") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
    }
    
    private func updateAvailableView(_ update: AppUpdate) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.blue)
            
            Text("Update Available")
                .font(.headline)
            
            Text("Version \(update.version) is now available — you have \(currentVersion).")
                .font(.body)
                .multilineTextAlignment(.center)
            
            // Release notes
            Group {
                if !update.releaseNotes.isEmpty {
                    ScrollView {
                        Text(update.releaseNotes)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(height: 100)
                    .frame(maxWidth: .infinity)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                }
            }
            
            // File size if available
            if let fileSize = update.fileSize {
                Text("Download size: \(formatFileSize(fileSize))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 12) {
                Button("Skip This Version") {
                    onSkipVersion(update.version)
                    dismiss()
                }
                .buttonStyle(.plain)
                
                Button("Later") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Download") {
                    onDownload(update)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
    }
    
    private func errorView(_ error: Error) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            Text("Update Check Failed")
                .font(.headline)
            
            Text(error.localizedDescription)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("OK") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
    }
    
    private func downloadingView(_ progress: Double) -> some View {
        VStack(spacing: 16) {
            Text("Downloading Update...")
                .font(.headline)
            
            ProgressView(value: progress, total: 1.0)
                .progressViewStyle(.linear)
                .frame(width: 300)
            
            Text("\(Int(progress * 100))%")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Button("Cancel") {
                onCancel()
                dismiss()
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Helper Methods
    
    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }
}