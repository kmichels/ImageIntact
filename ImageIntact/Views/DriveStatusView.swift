//
//  DriveStatusView.swift
//  ImageIntact
//
//  Shows drive status indicators and health warnings
//

import SwiftUI

struct DriveStatusView: View {
    let driveInfo: DriveAnalyzer.DriveInfo
    @ObservedObject var identityManager = DriveIdentityManager.shared
    @State private var driveIdentity: DriveIdentity?
    @State private var healthReport: SMARTMonitor.HealthReport?
    @State private var showingCustomization = false
    
    var body: some View {
        HStack(spacing: 8) {
            // Drive emoji/icon
            Text(driveIdentity?.emoji ?? "💾")
                .font(.system(size: 16))
            
            VStack(alignment: .leading, spacing: 2) {
                // Drive name
                HStack(spacing: 4) {
                    Text(displayName)
                        .font(.system(size: 13, weight: .medium))
                    
                    // Connection type badge
                    ConnectionTypeBadge(type: driveInfo.connectionType)
                    
                    // Preferred badge
                    if driveIdentity?.isPreferredBackup == true {
                        Text("PREFERRED")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.blue)
                            .cornerRadius(3)
                    }
                    
                    // Auto-start badge
                    if driveIdentity?.autoStartBackup == true {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.green)
                            .help("Auto-starts backup when connected")
                    }
                }
                
                // Drive details
                HStack(spacing: 12) {
                    // Capacity
                    Text(formatBytes(driveInfo.totalCapacity))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    // Free space with color coding
                    HStack(spacing: 2) {
                        Circle()
                            .fill(freeSpaceColor)
                            .frame(width: 6, height: 6)
                        Text("\(formatBytes(driveInfo.freeSpace)) free")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    // Health indicator
                    if let health = healthReport {
                        HealthIndicator(health: health)
                    }
                    
                    // Physical location
                    if let location = driveIdentity?.physicalLocation {
                        Text("📍 \(location)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                
                // Last backup info
                if let lastBackup = lastBackupInfo {
                    Text(lastBackup)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
            
            Spacer()
            
            // Customize button
            Button(action: { showingCustomization = true }) {
                Image(systemName: "gear")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Customize drive settings")
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(backgroundColorFor(driveIdentity))
        .cornerRadius(6)
        .onAppear {
            loadDriveIdentity()
            checkDriveHealth()
        }
        .sheet(isPresented: $showingCustomization) {
            if let identity = driveIdentity {
                DriveCustomizationView(drive: identity)
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var displayName: String {
        if let customName = driveIdentity?.userLabel, !customName.isEmpty {
            return customName
        }
        return driveInfo.deviceName
    }
    
    private var freeSpaceColor: Color {
        let percentage = Double(driveInfo.freeSpace) / Double(driveInfo.totalCapacity)
        if percentage > 0.3 {
            return .green
        } else if percentage > 0.15 {
            return .orange
        } else {
            return .red
        }
    }
    
    private var lastBackupInfo: String? {
        guard let identity = driveIdentity,
              let sessions = identity.backupSessions as? Set<BackupSession>,
              let lastSession = sessions.max(by: { ($0.startedAt ?? Date.distantPast) < ($1.startedAt ?? Date.distantPast) }) else {
            return nil
        }
        
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        
        if let date = lastSession.startedAt {
            return "Last backup: \(formatter.localizedString(for: date, relativeTo: Date()))"
        }
        return nil
    }
    
    private func backgroundColorFor(_ identity: DriveIdentity?) -> Color {
        if identity?.isPreferredBackup == true {
            return Color.blue.opacity(0.1)
        }
        return Color.gray.opacity(0.05)
    }
    
    // MARK: - Methods
    
    private func loadDriveIdentity() {
        // Only try to load/create identity if Core Data is available
        if let identity = identityManager.findOrCreateDriveIdentity(for: driveInfo) {
            driveIdentity = identity
        }
    }
    
    private func checkDriveHealth() {
        healthReport = SMARTMonitor.getHealthReport(for: driveInfo.mountPath)
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Connection Type Badge

struct ConnectionTypeBadge: View {
    let type: DriveAnalyzer.ConnectionType
    
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(type.displayName)
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundColor(color)
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(color.opacity(0.2))
        .cornerRadius(3)
    }
    
    private var icon: String {
        switch type {
        case .usb2: return "cable.connector"
        case .usb30, .usb31Gen1, .usb31Gen2, .usb32Gen2x2: return "cable.connector"
        case .thunderbolt3, .thunderbolt4, .thunderbolt5: return "bolt.fill"
        case .network: return "network"
        case .internalDrive: return "internaldrive"
        case .unknown: return "questionmark.circle"
        }
    }
    
    private var color: Color {
        switch type {
        case .thunderbolt3, .thunderbolt4, .thunderbolt5: return .purple
        case .usb30, .usb31Gen1, .usb31Gen2, .usb32Gen2x2: return .blue
        case .usb2: return .gray
        case .network: return .green
        case .internalDrive: return .orange
        case .unknown: return .gray
        }
    }
}

// MARK: - Health Indicator

struct HealthIndicator: View {
    let health: SMARTMonitor.HealthReport
    
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(color)
            
            if let percentage = health.healthPercentage {
                Text("\(percentage)%")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(color)
            }
        }
        .help(health.status.displayName)
    }
    
    private var icon: String {
        switch health.status {
        case .excellent, .good: return "checkmark.circle.fill"
        case .fair: return "exclamationmark.triangle.fill"
        case .poor, .failing: return "xmark.circle.fill"
        case .unknown: return "questionmark.circle"
        }
    }
    
    private var color: Color {
        switch health.status {
        case .excellent, .good: return .green
        case .fair: return .orange
        case .poor, .failing: return .red
        case .unknown: return .gray
        }
    }
}