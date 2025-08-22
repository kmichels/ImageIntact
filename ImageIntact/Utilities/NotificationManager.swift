//
//  NotificationManager.swift
//  ImageIntact
//
//  Manages system notifications for backup events
//

import Foundation
import UserNotifications
import AppKit

/// Manages system notifications for the application
class NotificationManager: NSObject {
    static let shared = NotificationManager()
    
    private var hasRequestedAuthorization = false
    private var isAuthorized = false
    
    private override init() {
        super.init()
        requestAuthorizationIfNeeded()
    }
    
    /// Request notification authorization if not already done
    private func requestAuthorizationIfNeeded() {
        guard !hasRequestedAuthorization else { return }
        hasRequestedAuthorization = true
        
        // First check current authorization status
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                // User hasn't been asked yet, request permission
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
                    self?.isAuthorized = granted
                    
                    if let error = error {
                        logWarning("Failed to request notification authorization: \(error)")
                    } else if granted {
                        logInfo("Notification authorization granted")
                    } else {
                        logInfo("Notification authorization denied by user")
                    }
                }
                
            case .denied:
                // User has explicitly denied permission
                self?.isAuthorized = false
                logInfo("Notifications are disabled (user denied permission)")
                
            case .authorized, .provisional, .ephemeral:
                // User has granted permission
                self?.isAuthorized = true
                logInfo("Notifications are already authorized")
                
            @unknown default:
                self?.isAuthorized = false
                logInfo("Unknown notification authorization status")
            }
        }
        
        // Set ourselves as the delegate to handle notifications while app is in foreground
        UNUserNotificationCenter.current().delegate = self
    }
    
    /// Send a notification when backup completes successfully
    func sendBackupCompletionNotification(filesCopied: Int, destinations: Int, duration: TimeInterval) {
        guard isAuthorized else {
            logInfo("Notifications not authorized, skipping completion notification")
            return
        }
        
        guard PreferencesManager.shared.showNotificationOnComplete else {
            logInfo("Completion notifications disabled by user preference")
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = "Backup Complete"
        content.subtitle = formatBackupSummary(filesCopied: filesCopied, destinations: destinations)
        content.body = formatDuration(duration)
        content.sound = .default
        
        // Add action buttons
        content.categoryIdentifier = "BACKUP_COMPLETE"
        
        // Create the request
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // Deliver immediately
        )
        
        // Schedule the notification
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                logError("Failed to send completion notification: \(error)")
            } else {
                logInfo("Backup completion notification sent")
            }
        }
    }
    
    /// Send a notification when backup fails
    func sendBackupFailureNotification(error: String) {
        guard isAuthorized else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Backup Failed"
        content.subtitle = "An error occurred during backup"
        content.body = error
        content.sound = .default
        
        // Create the request
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        // Schedule the notification
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                logError("Failed to send failure notification: \(error)")
            }
        }
    }
    
    /// Send a warning notification (e.g., low disk space)
    func sendWarningNotification(title: String, message: String) {
        guard isAuthorized else { return }
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                logError("Failed to send warning notification: \(error)")
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func formatBackupSummary(filesCopied: Int, destinations: Int) -> String {
        let filesText = filesCopied == 1 ? "1 file" : "\(filesCopied) files"
        let destText = destinations == 1 ? "1 destination" : "\(destinations) destinations"
        return "\(filesText) backed up to \(destText)"
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 60 {
            return String(format: "Completed in %.0f seconds", duration)
        } else if duration < 3600 {
            let minutes = Int(duration / 60)
            let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
            if seconds == 0 {
                return "Completed in \(minutes) minute\(minutes == 1 ? "" : "s")"
            } else {
                return "Completed in \(minutes) minute\(minutes == 1 ? "" : "s") \(seconds) second\(seconds == 1 ? "" : "s")"
            }
        } else {
            let hours = Int(duration / 3600)
            let minutes = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)
            if minutes == 0 {
                return "Completed in \(hours) hour\(hours == 1 ? "" : "s")"
            } else {
                return "Completed in \(hours) hour\(hours == 1 ? "" : "s") \(minutes) minute\(minutes == 1 ? "" : "s")"
            }
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    /// Handle notifications when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, 
                                willPresent notification: UNNotification, 
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound])
    }
    
    /// Handle notification actions
    func userNotificationCenter(_ center: UNUserNotificationCenter, 
                                didReceive response: UNNotificationResponse, 
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        // Handle any notification actions here if needed
        completionHandler()
    }
}