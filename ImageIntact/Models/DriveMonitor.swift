//
//  DriveMonitor.swift
//  ImageIntact
//
//  Real-time drive monitoring with DiskArbitration and IOKit
//

import Foundation
import DiskArbitration
import IOKit
import IOKit.usb
import IOKit.storage
import Combine

/// Monitors drive connections and provides real-time notifications
class DriveMonitor: ObservableObject {
    static let shared = DriveMonitor()
    
    // MARK: - Published Properties
    @Published var connectedDrives: [DriveAnalyzer.DriveInfo] = []
    @Published var recentlyDisconnected: [DriveAnalyzer.DriveInfo] = []
    
    // MARK: - Drive Events
    let driveConnected = PassthroughSubject<DriveAnalyzer.DriveInfo, Never>()
    let driveDisconnected = PassthroughSubject<DriveAnalyzer.DriveInfo, Never>()
    let driveChanged = PassthroughSubject<DriveAnalyzer.DriveInfo, Never>()
    
    // MARK: - Private Properties
    private var daSession: DASession?
    private var notificationPort: IONotificationPortRef?
    private var runLoopSource: CFRunLoopSource?
    private var monitoringActive = false
    private let monitorQueue = DispatchQueue(label: "com.imageintact.drivemonitor", qos: .background)
    
    // Track drives by UUID for smart recognition
    private var knownDrives: [String: DriveMetadata] = [:]
    
    // MARK: - Drive Metadata
    struct DriveMetadata: Codable {
        let uuid: String
        let serialNumber: String?
        let modelName: String?
        var customName: String?
        var lastSeen: Date
        var totalBackups: Int
        var totalBytesWritten: Int64
        var preferredForBackup: Bool
        var autoStartBackup: Bool
    }
    
    // MARK: - Initialization
    private init() {
        loadKnownDrives()
    }
    
    // MARK: - Public API
    
    /// Start monitoring for drive events
    func startMonitoring() {
        guard !monitoringActive else { return }
        
        monitorQueue.async { [weak self] in
            self?.setupDiskArbitration()
            self?.setupIOKitNotifications()
            self?.scanCurrentDrives()
            self?.monitoringActive = true
            
            logInfo("Drive monitoring started")
        }
    }
    
    /// Stop monitoring for drive events
    func stopMonitoring() {
        guard monitoringActive else { return }
        
        monitorQueue.async { [weak self] in
            self?.teardownDiskArbitration()
            self?.teardownIOKitNotifications()
            self?.monitoringActive = false
            
            logInfo("Drive monitoring stopped")
        }
    }
    
    /// Get detailed information about a specific drive
    func getDriveDetails(_ url: URL) -> DriveAnalyzer.DriveInfo? {
        return DriveAnalyzer.analyzeDrive(at: url)
    }
    
    /// Set a custom name for a drive
    func setCustomName(for driveUUID: String, name: String) {
        if var identity = knownDrives[driveUUID] {
            identity.customName = name
            knownDrives[driveUUID] = identity
            saveKnownDrives()
        }
    }
    
    /// Mark a drive as preferred for backups
    func setPreferredForBackup(for driveUUID: String, preferred: Bool) {
        if var identity = knownDrives[driveUUID] {
            identity.preferredForBackup = preferred
            knownDrives[driveUUID] = identity
            saveKnownDrives()
        }
    }
    
    /// Enable auto-start backup when drive connects
    func setAutoStartBackup(for driveUUID: String, autoStart: Bool) {
        if var identity = knownDrives[driveUUID] {
            identity.autoStartBackup = autoStart
            knownDrives[driveUUID] = identity
            saveKnownDrives()
        }
    }
    
    // MARK: - DiskArbitration Setup
    
    private func setupDiskArbitration() {
        // Create a DiskArbitration session
        guard let session = DASessionCreate(kCFAllocatorDefault) else {
            logError("Failed to create DiskArbitration session")
            return
        }
        
        self.daSession = session
        
        // Schedule with run loop
        DASessionScheduleWithRunLoop(session, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        
        // Register for disk appeared notifications
        DARegisterDiskAppearedCallback(session, nil, driveAppearedCallback, Unmanaged.passUnretained(self).toOpaque())
        
        // Register for disk disappeared notifications  
        DARegisterDiskDisappearedCallback(session, nil, driveDisappearedCallback, Unmanaged.passUnretained(self).toOpaque())
        
        // Register for disk description changed notifications (fixed parameter order)
        DARegisterDiskDescriptionChangedCallback(session, nil, nil, driveChangedCallback, Unmanaged.passUnretained(self).toOpaque())
    }
    
    private func teardownDiskArbitration() {
        if let session = daSession {
            // DAUnregisterCallback requires specific callbacks - just unschedule instead
            DASessionUnscheduleFromRunLoop(session, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            self.daSession = nil
        }
    }
    
    // MARK: - IOKit Notifications
    
    private func setupIOKitNotifications() {
        // Create notification port
        notificationPort = IONotificationPortCreate(kIOMainPortDefault)
        guard let notificationPort = notificationPort else {
            logError("Failed to create IOKit notification port")
            return
        }
        
        // Get run loop source
        runLoopSource = IONotificationPortGetRunLoopSource(notificationPort)?.takeUnretainedValue()
        guard let runLoopSource = runLoopSource else {
            logError("Failed to get run loop source")
            return
        }
        
        // Add to run loop
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, CFRunLoopMode.defaultMode)
        
        // Register for USB device notifications
        var usbIterator: io_iterator_t = 0
        let usbMatching = IOServiceMatching(kIOUSBDeviceClassName)
        
        IOServiceAddMatchingNotification(
            notificationPort,
            kIOMatchedNotification,
            usbMatching,
            usbDeviceAdded,
            Unmanaged.passUnretained(self).toOpaque(),
            &usbIterator
        )
        
        // Process existing USB devices
        processDeviceIterator(usbIterator)
    }
    
    private func teardownIOKitNotifications() {
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, CFRunLoopMode.defaultMode)
            self.runLoopSource = nil
        }
        
        if let notificationPort = notificationPort {
            IONotificationPortDestroy(notificationPort)
            self.notificationPort = nil
        }
    }
    
    func processDeviceIterator(_ iterator: io_iterator_t) {
        var device = IOIteratorNext(iterator)
        while device != 0 {
            // Process device (can check for specific properties)
            IOObjectRelease(device)
            device = IOIteratorNext(iterator)
        }
    }
    
    // MARK: - Current Drive Scanning
    
    private func scanCurrentDrives() {
        let fileManager = FileManager.default
        
        // Get all mounted volumes
        guard let volumes = fileManager.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeNameKey, .volumeIsLocalKey], options: [.skipHiddenVolumes]) else {
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.connectedDrives = volumes.compactMap { url in
                DriveAnalyzer.analyzeDrive(at: url)
            }
        }
    }
    
    // MARK: - Drive Identity Management
    
    func identifyDrive(_ disk: DADisk) -> DriveMetadata? {
        guard let description = DADiskCopyDescription(disk) as? [String: Any] else {
            return nil
        }
        
        // Get UUID - need to handle the type conversion carefully
        var uuidString: String?
        if let uuidRef = description[kDADiskDescriptionVolumeUUIDKey as String] {
            if CFGetTypeID(uuidRef as CFTypeRef) == CFUUIDGetTypeID() {
                let uuid = uuidRef as! CFUUID
                uuidString = CFUUIDCreateString(nil, uuid) as String
            }
        }
        
        guard let finalUUID = uuidString else {
            return nil
        }
        
        // Get other properties
        let serial = description[kDADiskDescriptionDeviceModelKey as String] as? String
        let model = description[kDADiskDescriptionDeviceVendorKey as String] as? String
        
        // Check if we know this drive
        if var identity = knownDrives[finalUUID] {
            identity.lastSeen = Date()
            knownDrives[finalUUID] = identity
            saveKnownDrives()
            return identity
        } else {
            // New drive
            let identity = DriveMetadata(
                uuid: finalUUID,
                serialNumber: serial,
                modelName: model,
                customName: nil,
                lastSeen: Date(),
                totalBackups: 0,
                totalBytesWritten: 0,
                preferredForBackup: false,
                autoStartBackup: false
            )
            knownDrives[finalUUID] = identity
            saveKnownDrives()
            return identity
        }
    }
    
    // MARK: - Persistence
    
    private func loadKnownDrives() {
        guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }
        
        let driveDataURL = appSupportURL
            .appendingPathComponent("ImageIntact", isDirectory: true)
            .appendingPathComponent("KnownDrives.json")
        
        if let data = try? Data(contentsOf: driveDataURL),
           let drives = try? JSONDecoder().decode([String: DriveMetadata].self, from: data) {
            self.knownDrives = drives
        }
    }
    
    private func saveKnownDrives() {
        guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }
        
        let driveDataURL = appSupportURL
            .appendingPathComponent("ImageIntact", isDirectory: true)
            .appendingPathComponent("KnownDrives.json")
        
        // Create directory if needed
        try? FileManager.default.createDirectory(
            at: driveDataURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        
        if let data = try? JSONEncoder().encode(knownDrives) {
            try? data.write(to: driveDataURL)
        }
    }
}

// MARK: - C Callback Functions

private func driveAppearedCallback(disk: DADisk?, context: UnsafeMutableRawPointer?) {
    guard let disk = disk,
          let context = context else { return }
    
    let monitor = Unmanaged<DriveMonitor>.fromOpaque(context).takeUnretainedValue()
    
    // Get mount point
    guard let description = DADiskCopyDescription(disk) as? [String: Any],
          let path = description[kDADiskDescriptionVolumePathKey as String] as? URL else {
        return
    }
    
    // Analyze drive
    if let driveInfo = DriveAnalyzer.analyzeDrive(at: path) {
        DispatchQueue.main.async {
            monitor.connectedDrives.append(driveInfo)
            monitor.driveConnected.send(driveInfo)
            
            // Check for auto-start backup
            if let identity = monitor.identifyDrive(disk),
               identity.autoStartBackup {
                NotificationCenter.default.post(
                    name: Notification.Name("AutoStartBackup"),
                    object: nil,
                    userInfo: ["driveInfo": driveInfo]
                )
            }
            
            logInfo("Drive connected: \(driveInfo.deviceName) (\(driveInfo.connectionType.displayName))")
        }
    }
}

private func driveDisappearedCallback(disk: DADisk?, context: UnsafeMutableRawPointer?) {
    guard let disk = disk,
          let context = context else { return }
    
    let monitor = Unmanaged<DriveMonitor>.fromOpaque(context).takeUnretainedValue()
    
    // Get mount point
    guard let description = DADiskCopyDescription(disk) as? [String: Any],
          let path = description[kDADiskDescriptionVolumePathKey as String] as? URL else {
        return
    }
    
    DispatchQueue.main.async {
        if let index = monitor.connectedDrives.firstIndex(where: { $0.mountPath == path }) {
            let driveInfo = monitor.connectedDrives.remove(at: index)
            monitor.recentlyDisconnected.append(driveInfo)
            monitor.driveDisconnected.send(driveInfo)
            
            logInfo("Drive disconnected: \(driveInfo.deviceName)")
            
            // Keep only last 5 disconnected drives
            if monitor.recentlyDisconnected.count > 5 {
                monitor.recentlyDisconnected.removeFirst()
            }
        }
    }
}

private func driveChangedCallback(disk: DADisk?, keys: CFArray?, context: UnsafeMutableRawPointer?) {
    guard let disk = disk,
          let context = context else { return }
    
    let monitor = Unmanaged<DriveMonitor>.fromOpaque(context).takeUnretainedValue()
    
    // Handle drive property changes (e.g., renamed, reformatted)
    guard let description = DADiskCopyDescription(disk) as? [String: Any],
          let path = description[kDADiskDescriptionVolumePathKey as String] as? URL else {
        return
    }
    
    if let updatedInfo = DriveAnalyzer.analyzeDrive(at: path) {
        DispatchQueue.main.async {
            if let index = monitor.connectedDrives.firstIndex(where: { $0.mountPath == path }) {
                monitor.connectedDrives[index] = updatedInfo
                monitor.driveChanged.send(updatedInfo)
            }
        }
    }
}

private func usbDeviceAdded(refcon: UnsafeMutableRawPointer?, iterator: io_iterator_t) {
    guard let refcon = refcon else { return }
    let monitor = Unmanaged<DriveMonitor>.fromOpaque(refcon).takeUnretainedValue()
    monitor.processDeviceIterator(iterator)
}