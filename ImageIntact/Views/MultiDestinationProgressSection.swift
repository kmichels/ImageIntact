import SwiftUI

struct MultiDestinationProgressSection: View {
    @Bindable var backupManager: BackupManager
    
    private var destinations: [URL] {
        backupManager.destinationURLs.compactMap { $0 }
    }
    
    private func phaseDescription(for phase: BackupPhase) -> String {
        switch phase {
        case .idle: return "Idle"
        case .analyzingSource: return "Analyzing source files"
        case .buildingManifest: return "Building manifest (calculating checksums)"
        case .copyingFiles: return "Copying files"
        case .flushingToDisk: return "Flushing to disk"
        case .verifyingDestinations: return "Verifying checksums"
        case .complete: return "Complete"
        }
    }
    
    var body: some View {
        if !backupManager.statusMessage.isEmpty || backupManager.isProcessing {
            VStack(alignment: .leading, spacing: 12) {
                Divider()
                    .padding(.horizontal, 20)
                
                if backupManager.isProcessing && backupManager.totalFiles > 0 {
                    // Show different UI based on destination count
                    if destinations.count <= 1 {
                        // Single destination - show simple progress
                        SimpleBackupProgress(backupManager: backupManager)
                    } else {
                        // Multiple destinations - show per-destination progress
                        MultiDestinationProgress(backupManager: backupManager, destinations: destinations)
                    }
                } else {
                    // Preparing or simple status with phase indicator
                    VStack(alignment: .leading, spacing: 8) {
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
                        
                        // Show phase progress if in phase-based backup
                        if backupManager.isProcessing {
                            HStack(spacing: 4) {
                                PhaseIndicator(label: "Analyze", isActive: backupManager.currentPhase == .analyzingSource, 
                                             isComplete: backupManager.currentPhase.rawValue > BackupPhase.analyzingSource.rawValue)
                                PhaseIndicator(label: "Manifest", isActive: backupManager.currentPhase == .buildingManifest,
                                             isComplete: backupManager.currentPhase.rawValue > BackupPhase.buildingManifest.rawValue)
                                PhaseIndicator(label: "Copy", isActive: backupManager.currentPhase == .copyingFiles,
                                             isComplete: backupManager.currentPhase.rawValue > BackupPhase.copyingFiles.rawValue)
                                PhaseIndicator(label: "Flush", isActive: backupManager.currentPhase == .flushingToDisk,
                                             isComplete: backupManager.currentPhase.rawValue > BackupPhase.flushingToDisk.rawValue)
                                PhaseIndicator(label: "Verify", isActive: backupManager.currentPhase == .verifyingDestinations,
                                             isComplete: backupManager.currentPhase.rawValue > BackupPhase.verifyingDestinations.rawValue)
                            }
                            .font(.caption2)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .transition(.opacity)
        }
    }
}

struct SimpleBackupProgress: View {
    @Bindable var backupManager: BackupManager
    
    var body: some View {
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
                // Show current phase
                Text("Phase: \(phaseDescription(for: backupManager.currentPhase))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
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
                
                // Overall progress across all phases
                ProgressView(value: backupManager.overallProgress)
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
    }
}

struct MultiDestinationProgress: View {
    @Bindable var backupManager: BackupManager
    let destinations: [URL]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Backup Progress")
                    .font(.headline)
                
                Spacer()
                
                Text("Files: \(backupManager.currentFileIndex)/\(backupManager.totalFiles)")
                    .font(.subheadline)
                
                if backupManager.copySpeed > 0 {
                    Text("(\(String(format: "%.1f", backupManager.copySpeed)) MB/s)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
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
            
            // Overall progress bar (shows total progress across all phases)
            VStack(alignment: .leading, spacing: 4) {
                Text("Overall Progress")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                ProgressView(value: backupManager.overallProgress)
                    .progressViewStyle(.linear)
            }
            
            // Per-destination progress
            ForEach(destinations, id: \.lastPathComponent) { destination in
                DestinationProgressRow(
                    destinationName: destination.lastPathComponent,
                    completedFiles: backupManager.destinationProgress[destination.lastPathComponent] ?? 0,
                    totalFiles: backupManager.totalFiles,
                    isActive: backupManager.currentDestinationName == destination.lastPathComponent
                )
            }
            
            // Current file info
            if !backupManager.currentFileName.isEmpty {
                HStack {
                    Text("Current: \(backupManager.currentFileName)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
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
    }
}

struct DestinationProgressRow: View {
    let destinationName: String
    let completedFiles: Int
    let totalFiles: Int
    let isActive: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(destinationName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text("\(completedFiles)/\(totalFiles)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // Activity indicator
                Circle()
                    .fill(isActive ? Color.green : Color.clear)
                    .frame(width: 8, height: 8)
            }
            
            ProgressView(value: Double(completedFiles), total: Double(totalFiles))
                .progressViewStyle(.linear)
                .scaleEffect(x: 1, y: 0.6) // Make it a bit thinner
        }
        .padding(.vertical, 4)
    }
}

struct PhaseIndicator: View {
    let label: String
    let isActive: Bool
    var isComplete: Bool = false
    
    var body: some View {
        HStack(spacing: 2) {
            if isComplete {
                Image(systemName: "checkmark.circle.fill")
                    .imageScale(.small)
                    .foregroundColor(.green)
            }
            Text(label)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isActive ? Color.accentColor : (isComplete ? Color.green.opacity(0.2) : Color.gray.opacity(0.2)))
        )
        .foregroundColor(isActive ? .white : (isComplete ? .green : .secondary))
    }
}