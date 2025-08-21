//
//  ImageIntactApp.swift
//  ImageIntact
//
//  Created by Konrad Michels on 8/1/25.
//

import SwiftUI

@main
struct ImageIntactApp: App {
    @State private var showPreferences = false
    
    init() {
        // Initialize logging system first
        _ = ApplicationLogger.shared
        
        // Initialize system capabilities detection on app launch
        _ = SystemCapabilities.shared
        ApplicationLogger.shared.info("🚀 ImageIntact starting on \(SystemCapabilities.shared.displayName)", category: .app)
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .sheet(isPresented: $showPreferences) {
                    PreferencesView()
                }
                .onAppear {
                    // Listen for preferences notification
                    NotificationCenter.default.addObserver(
                        forName: NSNotification.Name("ShowPreferences"),
                        object: nil,
                        queue: .main
                    ) { _ in
                        showPreferences = true
                    }
                }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 600, height: 400)
        .commands {
            // Add Preferences to the app menu
            CommandGroup(after: .appInfo) {
                Button("Preferences...") {
                    NotificationCenter.default.post(name: NSNotification.Name("ShowPreferences"), object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            // Replace the standard File menu items
            CommandGroup(replacing: .newItem) {
                Button("Select Source Folder") {
                    NotificationCenter.default.post(name: NSNotification.Name("SelectSourceFolder"), object: nil)
                }
                .keyboardShortcut("1", modifiers: .command)
                
                Button("Select First Destination") {
                    NotificationCenter.default.post(name: NSNotification.Name("SelectDestination1"), object: nil)
                }
                .keyboardShortcut("2", modifiers: .command)
                
                Button("Add Destination") {
                    NotificationCenter.default.post(name: NSNotification.Name("AddDestination"), object: nil)
                }
                .keyboardShortcut("+", modifiers: .command)
                
                Divider()
                
                Button("Run Backup") {
                    NotificationCenter.default.post(name: NSNotification.Name("RunBackup"), object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            
            // Add to Edit menu after the standard items
            CommandGroup(after: .pasteboard) {
                Divider()
                
                Button("Clear All Selections") {
                    NotificationCenter.default.post(name: NSNotification.Name("ClearAll"), object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)
            }
            
            // Add a custom ImageIntact menu
            CommandMenu("ImageIntact") {
                Button("Run Backup") {
                    NotificationCenter.default.post(name: NSNotification.Name("RunBackup"), object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
                
                Divider()
                
                Button("Select Source Folder") {
                    NotificationCenter.default.post(name: NSNotification.Name("SelectSourceFolder"), object: nil)
                }
                .keyboardShortcut("1", modifiers: .command)
                
                Button("Select First Destination") {
                    NotificationCenter.default.post(name: NSNotification.Name("SelectDestination1"), object: nil)
                }
                .keyboardShortcut("2", modifiers: .command)
                
                Button("Add Destination") {
                    NotificationCenter.default.post(name: NSNotification.Name("AddDestination"), object: nil)
                }
                .keyboardShortcut("+", modifiers: .command)
                
                Divider()
                
                Button("Clear All Selections") {
                    NotificationCenter.default.post(name: NSNotification.Name("ClearAll"), object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)
                
                Divider()
                
                Button("Show Debug Log") {
                    NotificationCenter.default.post(name: NSNotification.Name("ShowDebugLog"), object: nil)
                }
                
                Button("Export Debug Log...") {
                    NotificationCenter.default.post(name: NSNotification.Name("ExportDebugLog"), object: nil)
                }
                
                Button("Verify Core Data Storage") {
                    NotificationCenter.default.post(name: NSNotification.Name("VerifyCoreData"), object: nil)
                }
                
                Divider()
                
                Button("Check for Updates...") {
                    NotificationCenter.default.post(name: NSNotification.Name("CheckForUpdates"), object: nil)
                }
                
            }
            
            // Add Help menu
            CommandMenu("Help") {
                Button("ImageIntact Help") {
                    NotificationCenter.default.post(name: NSNotification.Name("ShowHelp"), object: nil)
                }
                .keyboardShortcut("?", modifiers: .command)
            }
        }
    }
}
