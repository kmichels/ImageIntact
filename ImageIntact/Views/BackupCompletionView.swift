//
//  BackupCompletionView.swift
//  ImageIntact
//
//  Displays detailed backup completion report
//

import SwiftUI

struct BackupCompletionView: View {
    let statistics: BackupStatistics
    @Environment(\.dismiss) var dismiss
    @State private var showingCopyAlert = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HeaderSection(statistics: statistics)
            
            Divider()
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Overall Statistics
                    OverallStatsSection(statistics: statistics)
                    
                    // File Type Breakdown
                    if !statistics.fileTypeStats.isEmpty {
                        FileTypeStatsSection(statistics: statistics)
                    }
                    
                    // Destination Breakdown
                    if !statistics.destinationStats.isEmpty {
                        DestinationStatsSection(statistics: statistics)
                    }
                    
                    // Filter Information
                    if !statistics.activeFilter.includedExtensions.isEmpty {
                        FilterInfoSection(statistics: statistics)
                    }
                }
                .padding(20)
            }
            
            Divider()
            
            // Footer
            HStack {
                Button("Copy Report") {
                    copyReportToClipboard()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 450, height: 500)
        .alert("Report Copied", isPresented: $showingCopyAlert) {
            Button("OK") { }
        } message: {
            Text("The backup report has been copied to your clipboard.")
        }
    }
    
    private func copyReportToClipboard() {
        let report = statistics.generateSummary()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        showingCopyAlert = true
    }
}

// MARK: - Header Section

struct HeaderSection: View {
    let statistics: BackupStatistics
    
    private var statusIcon: String {
        if statistics.totalFilesFailed == 0 {
            return "checkmark.circle.fill"
        } else if statistics.successRate > 90 {
            return "exclamationmark.circle.fill"
        } else {
            return "xmark.circle.fill"
        }
    }
    
    private var statusColor: Color {
        if statistics.totalFilesFailed == 0 {
            return .green
        } else if statistics.successRate > 90 {
            return .orange
        } else {
            return .red
        }
    }
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: statusIcon)
                .font(.system(size: 48))
                .foregroundColor(statusColor)
            
            Text("Backup Complete")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(statistics.formattedDuration)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

// MARK: - Overall Statistics Section

struct OverallStatsSection: View {
    let statistics: BackupStatistics
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Overall Statistics")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                StatRow(
                    label: "Files Processed",
                    value: "\(statistics.totalFilesProcessed) of \(statistics.totalFilesInSource)",
                    detail: String(format: "%.1f%%", statistics.successRate)
                )
                
                if statistics.filesExcludedByFilter > 0 {
                    StatRow(
                        label: "Filtered Out",
                        value: "\(statistics.filesExcludedByFilter) files",
                        detail: formatBytes(statistics.bytesExcludedByFilter),
                        valueColor: .orange
                    )
                }
                
                if statistics.totalFilesSkipped > 0 {
                    StatRow(
                        label: "Skipped",
                        value: "\(statistics.totalFilesSkipped) files",
                        detail: "Already existed",
                        valueColor: .blue
                    )
                }
                
                if statistics.totalFilesFailed > 0 {
                    StatRow(
                        label: "Failed",
                        value: "\(statistics.totalFilesFailed) files",
                        valueColor: .red
                    )
                }
                
                Divider()
                
                StatRow(
                    label: "Total Size",
                    value: formatBytes(statistics.totalBytesProcessed)
                )
                
                StatRow(
                    label: "Average Speed",
                    value: String(format: "%.1f MB/s", statistics.averageThroughput)
                )
            }
            .padding(12)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - File Type Statistics Section

struct FileTypeStatsSection: View {
    let statistics: BackupStatistics
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("By File Type")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 4) {
                ForEach(sortedFileTypes, id: \.0) { type, stats in
                    CompletionFileTypeRow(type: type, stats: stats)
                }
            }
            .padding(12)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
    }
    
    private var sortedFileTypes: [(ImageFileType, FileTypeStatistics)] {
        statistics.fileTypeStats
            .filter { $0.value.filesProcessed > 0 }
            .sorted { $0.value.filesProcessed > $1.value.filesProcessed }
            .map { ($0.key, $0.value) }
    }
}

struct CompletionFileTypeRow: View {
    let type: ImageFileType
    let stats: FileTypeStatistics
    
    var body: some View {
        HStack {
            Text(type.rawValue)
                .font(.system(.body, design: .monospaced))
                .frame(width: 80, alignment: .leading)
            
            Text("\(stats.successCount) files")
                .foregroundColor(.primary)
            
            if stats.failedCount > 0 {
                Text("(\(stats.failedCount) failed)")
                    .font(.caption)
                    .foregroundColor(.red)
            }
            
            Spacer()
            
            Text(formatBytes(stats.totalBytes))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Destination Statistics Section

struct DestinationStatsSection: View {
    let statistics: BackupStatistics
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("By Destination")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 16) {
                ForEach(sortedDestinations, id: \.0) { name, stats in
                    DestinationStatsView(name: name, stats: stats)
                }
            }
        }
    }
    
    private var sortedDestinations: [(String, DestinationStatistics)] {
        statistics.destinationStats
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value) }
    }
}

struct DestinationStatsView: View {
    let name: String
    let stats: DestinationStatistics
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(name, systemImage: "externaldrive")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                if stats.averageSpeed > 0 {
                    Text(String(format: "%.1f MB/s", stats.averageSpeed))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                if stats.filesCopied > 0 {
                    StatRow(
                        label: "Copied",
                        value: "\(stats.filesCopied) files",
                        detail: formatBytes(stats.bytesWritten),
                        compact: true
                    )
                }
                
                if stats.filesSkipped > 0 {
                    StatRow(
                        label: "Skipped",
                        value: "\(stats.filesSkipped) files",
                        valueColor: .blue,
                        compact: true
                    )
                }
                
                if stats.filesFailed > 0 {
                    StatRow(
                        label: "Failed",
                        value: "\(stats.filesFailed) files",
                        valueColor: .red,
                        compact: true
                    )
                }
            }
            .padding(8)
            .background(Color.gray.opacity(0.05))
            .cornerRadius(6)
        }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Filter Information Section

struct FilterInfoSection: View {
    let statistics: BackupStatistics
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Filter Applied")
                .font(.headline)
            
            HStack {
                Image(systemName: "line.3.horizontal.decrease.circle.fill")
                    .foregroundColor(.accentColor)
                
                Text(statistics.activeFilter.description)
                    .font(.body)
                
                Spacer()
                
                if statistics.filesExcludedByFilter > 0 {
                    Text("\(statistics.filesExcludedByFilter) files excluded")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(12)
            .background(Color.accentColor.opacity(0.1))
            .cornerRadius(8)
        }
    }
}

// MARK: - Stat Row Component

struct StatRow: View {
    let label: String
    let value: String
    var detail: String? = nil
    var valueColor: Color = .primary
    var compact: Bool = false
    
    var body: some View {
        HStack {
            Text(label)
                .font(compact ? .caption : .body)
                .foregroundColor(.secondary)
                .frame(width: compact ? 60 : 120, alignment: .leading)
            
            Text(value)
                .font(compact ? .caption : .body)
                .fontWeight(compact ? .regular : .medium)
                .foregroundColor(valueColor)
            
            if let detail = detail {
                Text("• \(detail)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}