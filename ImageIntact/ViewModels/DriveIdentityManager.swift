//
//  DriveIdentityManager.swift
//  ImageIntact
//
//  Manages drive identity persistence and UI state
//

import Foundation
import CoreData
import Combine

/// Manages drive identities using Core Data and provides UI state
@MainActor
class DriveIdentityManager: ObservableObject {
    static let shared = DriveIdentityManager()
    
    // MARK: - Published Properties
    @Published var knownDrives: [DriveIdentity] = []
    @Published var connectedDrives: [DriveAnalyzer.DriveInfo] = []
    @Published var isFirstTimeSetup = false
    
    // MARK: - Private Properties
    private let container: NSPersistentContainer
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    private init() {
        // Use the same container as EventLogger with matching configuration
        container = NSPersistentContainer(name: "ImageIntactEvents")
        
        // Configure for performance and match EventLogger settings
        if let description = container.persistentStoreDescriptions.first {
            // Enable persistent history tracking (MUST match EventLogger)
            description.setOption(true as NSNumber, 
                                 forKey: NSPersistentHistoryTrackingKey)
            
            // Enable remote change notifications
            description.setOption(true as NSNumber,
                                 forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            
            // Set SQLite pragmas for performance
            description.setOption(["journal_mode": "WAL",
                                   "synchronous": "NORMAL",
                                   "cache_size": "10000"] as NSDictionary,
                                 forKey: NSSQLitePragmasOption)
            
            // Enable automatic migration
            description.setOption(true as NSNumber,
                                 forKey: NSMigratePersistentStoresAutomaticallyOption)
            description.setOption(true as NSNumber,
                                 forKey: NSInferMappingModelAutomaticallyOption)
        }
        
        container.loadPersistentStores { _, error in
            if let error = error {
                ApplicationLogger.shared.error("Failed to load Core Data: \(error)", category: .database)
            }
        }
        
        // Configure contexts
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        // Set up drive monitor subscriptions
        setupDriveMonitorSubscriptions()
        
        // Load known drives
        loadKnownDrives()
    }
    
    // MARK: - Drive Monitor Integration
    private func setupDriveMonitorSubscriptions() {
        // Subscribe to connected drives
        DriveMonitor.shared.$connectedDrives
            .receive(on: DispatchQueue.main)
            .sink { [weak self] drives in
                self?.connectedDrives = drives
                self?.updateDriveIdentities(drives)
            }
            .store(in: &cancellables)
        
        // Subscribe to drive connected events
        DriveMonitor.shared.driveConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] driveInfo in
                self?.handleDriveConnected(driveInfo)
            }
            .store(in: &cancellables)
        
        // Subscribe to drive disconnected events
        DriveMonitor.shared.driveDisconnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] driveInfo in
                self?.handleDriveDisconnected(driveInfo)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Core Data Operations
    
    /// Load all known drives from Core Data
    func loadKnownDrives() {
        let request: NSFetchRequest<DriveIdentity> = DriveIdentity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "lastSeen", ascending: false)]
        
        do {
            knownDrives = try container.viewContext.fetch(request)
        } catch {
            ApplicationLogger.shared.error("Failed to fetch drives: \(error)", category: .database)
        }
    }
    
    /// Find or create a drive identity
    func findOrCreateDriveIdentity(for driveInfo: DriveAnalyzer.DriveInfo) -> DriveIdentity? {
        // Check if Core Data is available
        guard container.persistentStoreCoordinator.persistentStores.count > 0 else {
            ApplicationLogger.shared.error("Core Data not available for drive identity", category: .database)
            return nil
        }
        // Try to find existing drive by UUID
        let request: NSFetchRequest<DriveIdentity> = DriveIdentity.fetchRequest()
        request.predicate = NSPredicate(format: "volumeUUID == %@", driveInfo.volumeUUID ?? "")
        request.fetchLimit = 1
        
        if let existing = try? container.viewContext.fetch(request).first {
            // Update last seen
            existing.lastSeen = Date()
            return existing
        }
        
        // Try to find by hardware serial if UUID not available
        if let serial = driveInfo.hardwareSerial {
            request.predicate = NSPredicate(format: "hardwareSerial == %@", serial)
            if let existing = try? container.viewContext.fetch(request).first {
                // Update UUID if we now have it
                if let uuid = driveInfo.volumeUUID {
                    existing.volumeUUID = uuid
                }
                existing.lastSeen = Date()
                return existing
            }
        }
        
        // Create new drive identity
        let newDrive = DriveIdentity(context: container.viewContext)
        newDrive.id = UUID()
        newDrive.volumeUUID = driveInfo.volumeUUID
        newDrive.hardwareSerial = driveInfo.hardwareSerial
        newDrive.deviceModel = driveInfo.deviceModel
        newDrive.capacity = driveInfo.totalCapacity
        newDrive.firstSeen = Date()
        newDrive.lastSeen = Date()
        newDrive.totalBackups = 0
        newDrive.totalBytesWritten = 0
        newDrive.isPreferredBackup = false
        newDrive.autoStartBackup = false
        
        saveContext()
        
        // Show first-time setup for new drives
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.isFirstTimeSetup = true
        }
        
        return newDrive
    }
    
    /// Update drive identities with current connected drives
    private func updateDriveIdentities(_ drives: [DriveAnalyzer.DriveInfo]) {
        for driveInfo in drives {
            _ = findOrCreateDriveIdentity(for: driveInfo)
        }
        saveContext()
        loadKnownDrives()
    }
    
    /// Update drive customization
    func updateDriveCustomization(_ drive: DriveIdentity, name: String?, emoji: String?, location: String?, notes: String?) {
        drive.userLabel = name
        drive.emoji = emoji
        drive.physicalLocation = location
        drive.notes = notes
        saveContext()
    }
    
    /// Set drive preferences
    func setDrivePreferences(_ drive: DriveIdentity, isPreferred: Bool, autoStart: Bool) {
        drive.isPreferredBackup = isPreferred
        drive.autoStartBackup = autoStart
        saveContext()
    }
    
    /// Update drive health status
    func updateDriveHealth(_ drive: DriveIdentity, healthReport: SMARTMonitor.HealthReport) {
        drive.healthStatus = healthReport.status.displayName
        drive.lastHealthCheck = Date()
        saveContext()
    }
    
    /// Record backup session for a drive
    func recordBackupSession(_ drive: DriveIdentity, session: BackupSession) {
        drive.addToBackupSessions(session)
        drive.totalBackups = Int32(drive.backupSessions?.count ?? 0)
        
        // Update total bytes written
        drive.totalBytesWritten += session.totalBytes
        
        saveContext()
    }
    
    // MARK: - Event Handlers
    
    private func handleDriveConnected(_ driveInfo: DriveAnalyzer.DriveInfo) {
        guard let identity = findOrCreateDriveIdentity(for: driveInfo) else {
            ApplicationLogger.shared.info("Drive connected (no identity): \(driveInfo.deviceName)", category: .app)
            return
        }
        
        // Check S.M.A.R.T. health
        if let healthReport = SMARTMonitor.getHealthReport(for: driveInfo.mountPath) {
            updateDriveHealth(identity, healthReport: healthReport)
            
            // Show warning if health is poor
            if healthReport.status == .poor || healthReport.status == .failing {
                NotificationCenter.default.post(
                    name: NSNotification.Name("ShowDriveHealthWarning"),
                    object: nil,
                    userInfo: ["drive": identity, "health": healthReport]
                )
            }
        }
        
        // Auto-start backup if configured
        if identity.autoStartBackup {
            NotificationCenter.default.post(
                name: NSNotification.Name("AutoStartBackup"),
                object: nil,
                userInfo: ["drive": identity, "driveInfo": driveInfo]
            )
        }
        
        ApplicationLogger.shared.info("Drive connected: \(identity.userLabel ?? driveInfo.deviceName)", category: .app)
    }
    
    private func handleDriveDisconnected(_ driveInfo: DriveAnalyzer.DriveInfo) {
        ApplicationLogger.shared.info("Drive disconnected: \(driveInfo.deviceName)", category: .app)
    }
    
    // MARK: - Helper Methods
    
    private func saveContext() {
        guard container.persistentStoreCoordinator.persistentStores.count > 0 else {
            ApplicationLogger.shared.error("Cannot save: No persistent stores available", category: .database)
            return
        }
        
        if container.viewContext.hasChanges {
            do {
                try container.viewContext.save()
            } catch {
                ApplicationLogger.shared.error("Failed to save context: \(error)", category: .database)
            }
        }
    }
    
    /// Get display name for a drive
    func displayName(for drive: DriveIdentity) -> String {
        if let customName = drive.userLabel, !customName.isEmpty {
            return customName
        }
        return drive.deviceModel ?? "Unknown Drive"
    }
    
    /// Get emoji for a drive
    func emoji(for drive: DriveIdentity) -> String {
        return drive.emoji ?? "💾"
    }
    
    /// Check if drive is currently connected
    func isConnected(_ drive: DriveIdentity) -> Bool {
        return connectedDrives.contains { driveInfo in
            driveInfo.volumeUUID == drive.volumeUUID ||
            driveInfo.hardwareSerial == drive.hardwareSerial
        }
    }
    
    /// Get current DriveInfo for a DriveIdentity
    func currentDriveInfo(for drive: DriveIdentity) -> DriveAnalyzer.DriveInfo? {
        return connectedDrives.first { driveInfo in
            driveInfo.volumeUUID == drive.volumeUUID ||
            driveInfo.hardwareSerial == drive.hardwareSerial
        }
    }
}