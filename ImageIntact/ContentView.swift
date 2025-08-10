import SwiftUI
import Darwin

struct ContentView: View {
    @State private var backupManager = BackupManager()
    @State private var updateManager = UpdateManager()
    @FocusState private var focusedField: FocusField?
    
    // First-run and help system
    @State private var showWelcomePopup = false
    @State private var showHelpWindow = false
    
    enum FocusField: Hashable {
        case source
        case destination(Int)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text("ImageIntact")
                    .font(.largeTitle)
                    .fontWeight(.semibold)
                
                Text("Verify and backup your photos to multiple locations")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 20)
            .padding(.bottom, 10)
            
            Divider()
                .padding(.horizontal)
            
            // Main content - ScrollView for everything except header and bottom buttons
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Source Section
                    SourceFolderSection(backupManager: backupManager, focusedField: $focusedField)
                    
                    Divider()
                        .padding(.horizontal, 20)
                    
                    // Destinations Section
                    DestinationSection(backupManager: backupManager, focusedField: $focusedField)
                    
                    // Progress Section
                    MultiDestinationProgressSection(backupManager: backupManager)
                    
                    // Add some bottom padding so content doesn't hide behind buttons
                    Color.clear.frame(height: 20)
                }
            }
            .frame(maxHeight: .infinity)
            
            // Bottom action area - always visible
            Divider()
            
            HStack {
                Button("Clear All") {
                    backupManager.clearAllSelections()
                }
                .keyboardShortcut("k", modifiers: .command)
                .buttonStyle(.plain)
                .foregroundColor(.red)
                
                Spacer()
                
                Button("Run Backup") {
                    backupManager.runBackup()
                }
                .keyboardShortcut("r", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!backupManager.canRunBackup())
            }
            .padding(20)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 500, idealWidth: 600, maxWidth: .infinity,
               minHeight: 400, idealHeight: 500, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            setupKeyboardShortcuts()
            setupMenuCommands()
            
            print("🔐 Using SHA-256 checksums for maximum compatibility")
            
            // Check for first run
            checkFirstRun()
            
            // Check for updates
            updateManager.checkForUpdates()
        }
        .sheet(isPresented: $showWelcomePopup) {
            WelcomeView(isPresented: $showWelcomePopup)
        }
        .sheet(isPresented: $showHelpWindow) {
            HelpView(isPresented: $showHelpWindow)
        }
        .alert("Update Available", isPresented: $updateManager.showUpdateAlert, presenting: updateManager.availableUpdate) { update in
            if updateManager.isDownloadingUpdate {
                Button("Cancel Download") {
                    updateManager.cancelDownload()
                }
                .keyboardShortcut(.cancelAction)
            } else {
                Button("Download & Install") {
                    Task {
                        await updateManager.downloadUpdate(update)
                    }
                }
                .keyboardShortcut(.defaultAction)
                
                Button("Later") { }
                    .keyboardShortcut(.cancelAction)
                
                Button("Skip This Version") {
                    updateManager.skipVersion(update.version)
                }
            }
        } message: { update in
            if updateManager.isDownloadingUpdate {
                VStack {
                    Text("Downloading ImageIntact \(update.version)...")
                    ProgressView(value: updateManager.downloadProgress, total: 1.0)
                        .frame(width: 200)
                    Text("\(Int(updateManager.downloadProgress * 100))%")
                        .font(.caption)
                }
            } else {
                VStack {
                    Text("Version \(update.version) is available!")
                        .fontWeight(.medium)
                    Text("\(update.releaseNotes)")
                        .padding(.top, 4)
                }
            }
        }
    }
    
    // MARK: - Menu Commands
    func setupMenuCommands() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SelectSourceFolder"),
            object: nil,
            queue: .main
        ) { _ in
            selectSourceFolder()
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SelectDestination1"),
            object: nil,
            queue: .main
        ) { _ in
            if !backupManager.destinationURLs.isEmpty {
                selectDestinationFolder(at: 0)
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AddDestination"),
            object: nil,
            queue: .main
        ) { _ in
            backupManager.addDestination()
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("RunBackup"),
            object: nil,
            queue: .main
        ) { _ in
            if backupManager.canRunBackup() {
                backupManager.runBackup()
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ClearAll"),
            object: nil,
            queue: .main
        ) { _ in
            backupManager.clearAllSelections()
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ShowDebugLog"),
            object: nil,
            queue: .main
        ) { _ in
            showDebugLog()
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ExportDebugLog"),
            object: nil,
            queue: .main
        ) { _ in
            exportDebugLog()
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ShowHelp"),
            object: nil,
            queue: .main
        ) { _ in
            showHelpWindow = true
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("CheckForUpdates"),
            object: nil,
            queue: .main
        ) { _ in
            Task {
                await updateManager.performUpdateCheck()
            }
        }
    }
    
    // MARK: - Keyboard Shortcuts
    func setupKeyboardShortcuts() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Check if Command key is pressed
            if event.modifierFlags.contains(.command) {
                switch event.charactersIgnoringModifiers {
                case "1":
                    // Select source folder
                    selectSourceFolder()
                    return nil
                case "2":
                    // Select first destination
                    if !backupManager.destinationURLs.isEmpty {
                        selectDestinationFolder(at: 0)
                    }
                    return nil
                default:
                    break
                }
            }
            
            // Escape key to cancel operation
            if event.keyCode == 53 && backupManager.isProcessing { // 53 is the key code for Escape
                backupManager.cancelOperation()
                print("Cancel operation requested")
                return nil
            }
            
            return event
        }
    }
    
    // MARK: - UI Helper Methods
    func selectSourceFolder() {
        let dialog = NSOpenPanel()
        dialog.canChooseFiles = false
        dialog.canChooseDirectories = true
        dialog.allowsMultipleSelection = false

        if dialog.runModal() == .OK {
            if let url = dialog.url {
                backupManager.setSource(url)
            }
        }
    }
    
    func selectDestinationFolder(at index: Int) {
        guard index < backupManager.destinationURLs.count else { return }
        
        let dialog = NSOpenPanel()
        dialog.canChooseFiles = false
        dialog.canChooseDirectories = true
        dialog.allowsMultipleSelection = false

        if dialog.runModal() == .OK {
            if let url = dialog.url {
                backupManager.setDestination(url, at: index)
            }
        }
    }
    
    // MARK: - Debug Log Methods
    func showDebugLog() {
        if let logPath = backupManager.lastDebugLogPath {
            NSWorkspace.shared.open(logPath)
        } else {
            // Create a temporary log file with current session data
            let tempLogContent = generateCurrentSessionDebugLog()
            let tempDir = FileManager.default.temporaryDirectory
            let tempLogPath = tempDir.appendingPathComponent("ImageIntact_CurrentSession.log")
            
            do {
                try tempLogContent.write(to: tempLogPath, atomically: true, encoding: .utf8)
                NSWorkspace.shared.open(tempLogPath)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Cannot Show Debug Log"
                alert.informativeText = "Could not create temporary debug log: \(error.localizedDescription)"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }
    
    func generateCurrentSessionDebugLog() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        
        var logContent = "ImageIntact Debug Log - \(timestamp)\n"
        logContent += "Session ID: \(backupManager.sessionID)\n"
        logContent += "Total Files: \(backupManager.totalFiles)\n"
        logContent += "Processed Files: \(backupManager.processedFiles)\n"
        logContent += "Failed Files: \(backupManager.failedFiles.count)\n"
        logContent += "Was Cancelled: \(backupManager.shouldCancel)\n\n"
        
        // Add detailed error information
        if !backupManager.failedFiles.isEmpty {
            logContent += "ERROR DETAILS:\n"
            for (index, failure) in backupManager.failedFiles.enumerated() {
                logContent += "\(index + 1). File: \(failure.file)\n"
                logContent += "   Destination: \(failure.destination)\n"
                logContent += "   Error: \(failure.error)\n\n"
            }
        }
        
        if !backupManager.debugLog.isEmpty {
            logContent += "Checksum Timings:\n"
            logContent += backupManager.debugLog.joined(separator: "\n")
        } else {
            logContent += "No timing data available yet.\n"
        }
        
        return logContent
    }
    
    func exportDebugLog() {
        // Always generate a log with current session data
        let logContent: String
        if let logPath = backupManager.lastDebugLogPath,
           let existingContent = try? String(contentsOf: logPath) {
            logContent = existingContent
        } else {
            // Generate debug log with current session data
            logContent = generateCurrentSessionDebugLog()
        }
        
        let savePanel = NSSavePanel()
        savePanel.title = "Export Debug Log"
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        savePanel.nameFieldStringValue = "ImageIntact_Debug_\(dateFormatter.string(from: Date())).txt"
        savePanel.allowedContentTypes = [.plainText]
        savePanel.canCreateDirectories = true
        
        if savePanel.runModal() == .OK, let exportURL = savePanel.url {
            do {
                try logContent.write(to: exportURL, atomically: true, encoding: .utf8)
                
                let alert = NSAlert()
                alert.messageText = "Debug Log Exported"
                alert.informativeText = "Debug log has been saved to:\n\n\(exportURL.path)"
                alert.alertStyle = .informational
                alert.addButton(withTitle: "OK")
                alert.runModal()
            } catch {
                let alert = NSAlert()
                alert.messageText = "Export Failed"
                alert.informativeText = "Could not export debug log: \(error.localizedDescription)"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }
    
    // MARK: - First Run
    func checkFirstRun() {
        let hasSeenWelcome = UserDefaults.standard.bool(forKey: "hasSeenWelcome")
        if !hasSeenWelcome {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.showWelcomePopup = true
                UserDefaults.standard.set(true, forKey: "hasSeenWelcome")
            }
        }
    }
}

// MARK: - Reusable FolderRow
struct FolderRow: View {
    let title: String
    @Binding var selectedURL: URL?
    let onClear: () -> Void
    var onSelect: ((URL) -> Void)? = nil
    
    var body: some View {
        HStack(spacing: 12) {
            Button(action: selectFolder) {
                HStack {
                    Image(systemName: selectedURL == nil ? "folder.badge.plus" : "folder.fill")
                        .foregroundColor(selectedURL == nil ? .secondary : .accentColor)
                    
                    Text(selectedURL?.lastPathComponent ?? title)
                        .foregroundColor(selectedURL == nil ? .secondary : .primary)
                    
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            
            if selectedURL != nil {
                Button("Clear") {
                    onClear()
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .font(.footnote)
            }
        }
    }
    
    func selectFolder() {
        let dialog = NSOpenPanel()
        dialog.canChooseFiles = false
        dialog.canChooseDirectories = true
        dialog.allowsMultipleSelection = false

        if dialog.runModal() == .OK {
            if let url = dialog.url {
                selectedURL = url
                onSelect?(url)
            }
        }
    }
}