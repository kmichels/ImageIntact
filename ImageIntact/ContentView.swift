import SwiftUI
import Darwin

struct ContentView: View {
    let sourceKey = "sourceBookmark"
    let destinationKeys = ["dest1Bookmark", "dest2Bookmark", "dest3Bookmark", "dest4Bookmark"]

    @State private var sourceURL: URL? = ContentView.loadBookmark(forKey: "sourceBookmark")
    @State private var destinationURLs: [URL?] = ContentView.loadDestinationBookmarks()
    @State private var isProcessing = false
    @State private var statusMessage = ""
    @State private var totalFiles = 0
    @State private var processedFiles = 0
    @State private var currentFile = ""
    @State private var failedFiles: [(file: String, destination: String, error: String)] = []
    @State var sessionID = UUID().uuidString  // Made internal for testing
    @State private var logEntries: [LogEntry] = []
    @FocusState private var focusedField: FocusField?
    @State private var shouldCancel = false
    @State private var currentOperation: DispatchWorkItem?
    @State private var debugLog: [String] = []
    
    struct LogEntry {
        let timestamp: Date
        let sessionID: String
        let action: String
        let source: String
        let destination: String
        let checksum: String
        let algorithm: String
        let fileSize: Int64
        let reason: String
    }
    
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
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Source", systemImage: "folder")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        FolderRow(
                            title: "Select Source Folder",
                            selectedURL: Binding(
                                get: { sourceURL },
                                set: { newValue in
                                    sourceURL = newValue
                                    if let url = newValue {
                                        saveBookmark(url: url, key: sourceKey)
                                    }
                                }
                            ),
                            onClear: {
                                sourceURL = nil
                                UserDefaults.standard.removeObject(forKey: sourceKey)
                            },
                            onSelect: { url in
                                tagSourceFolder(at: url)
                            }
                        )
                        .focused($focusedField, equals: .source)
                        .onTapGesture {
                            focusedField = .source
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    
                    Divider()
                        .padding(.horizontal, 20)
                    
                    // Destinations Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Destinations", systemImage: "arrow.triangle.branch")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            if destinationURLs.count < 4 {
                                Button(action: {
                                    destinationURLs.append(nil)
                                }) {
                                    Label("Add", systemImage: "plus.circle.fill")
                                        .font(.footnote)
                                }
                                .keyboardShortcut("+", modifiers: .command)
                                .buttonStyle(.plain)
                                .foregroundColor(.accentColor)
                            }
                        }
                        
                        VStack(spacing: 8) {
                            ForEach(0..<destinationURLs.count, id: \.self) { index in
                                FolderRow(
                                    title: "Destination \(index + 1)",
                                    selectedURL: Binding(
                                        get: { destinationURLs[index] },
                                        set: { newValue in
                                            destinationURLs[index] = newValue
                                            if let url = newValue, index < destinationKeys.count {
                                                saveBookmark(url: url, key: destinationKeys[index])
                                            }
                                        }
                                    ),
                                    onClear: {
                                        destinationURLs[index] = nil
                                        UserDefaults.standard.removeObject(forKey: destinationKeys[index])
                                    },
                                    onSelect: { url in
                                        // Check if this is a source folder
                                        if checkForSourceTag(at: url) {
                                            // Show alert
                                            let alert = NSAlert()
                                            alert.messageText = "Source Folder Selected"
                                            alert.informativeText = "This folder has been tagged as a source folder. Using it as a destination could lead to data loss. Please select a different folder."
                                            alert.alertStyle = .warning
                                            alert.addButton(withTitle: "OK")
                                            alert.runModal()
                                            
                                            // Reset the selection
                                            destinationURLs[index] = nil
                                        }
                                    }
                                )
                                .focused($focusedField, equals: .destination(index))
                                .onTapGesture {
                                    focusedField = .destination(index)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // Status Section (with progress indicator)
                    if !statusMessage.isEmpty || isProcessing {
                        VStack(alignment: .leading, spacing: 12) {
                            Divider()
                                .padding(.horizontal, 20)
                            
                            if isProcessing && totalFiles > 0 {
                                // Progress bar
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("Processing files...")
                                            .font(.headline)
                                        
                                        Spacer()
                                        
                                        Text("\(processedFiles) of \(totalFiles)")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    HStack(spacing: 8) {
                                        ProgressView(value: Double(processedFiles), total: Double(totalFiles))
                                            .progressViewStyle(.linear)
                                        
                                        Button(action: {
                                            cancelOperation()
                                        }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.red)
                                                .imageScale(.large)
                                        }
                                        .buttonStyle(.plain)
                                        .help("Cancel backup")
                                    }
                                    
                                    if !currentFile.isEmpty {
                                        Text(currentFile)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(8)
                                .padding(.horizontal, 20)
                            } else {
                                HStack {
                                    if isProcessing {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle())
                                            .scaleEffect(0.8)
                                    }
                                    
                                    Text(statusMessage)
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundColor(.secondary)
                                    
                                    Spacer()
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                        .transition(.opacity)
                    }
                    
                    // Add some bottom padding so content doesn't hide behind buttons
                    Color.clear.frame(height: 20)
                }
            }
            .frame(maxHeight: .infinity)
            
            // Bottom action area - always visible
            Divider()
            
            HStack {
                Button("Clear All") {
                    clearAllSelections()
                }
                .keyboardShortcut("k", modifiers: .command)
                .buttonStyle(.plain)
                .foregroundColor(.red)
                
                Spacer()
                
                Button("Run Backup") {
                    runCopyAndVerify()
                }
                .keyboardShortcut("r", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(sourceURL == nil || destinationURLs.compactMap { $0 }.isEmpty || isProcessing)
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
        }
    }
    
    func writeChecksumManifests(for destinations: [URL]) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        
        for destination in destinations {
            let manifestDir = destination.appendingPathComponent(".imageintact_checksums")
            try? FileManager.default.createDirectory(at: manifestDir, withIntermediateDirectories: true)
            try? FileManager.default.setAttributes([.extensionHidden: true], ofItemAtPath: manifestDir.path)
            
            let manifestFile = manifestDir.appendingPathComponent("manifest_\(timestamp)_\(sessionID).csv")
            
            // Filter log entries for this destination and successful actions
            let relevantEntries = logEntries.filter { entry in
                entry.destination.hasPrefix(destination.path) &&
                (entry.action == "COPIED" || entry.action == "SKIPPED")
            }
            
            // Write manifest header
            var manifestContent = "file_path,checksum,algorithm,file_size,action,timestamp\n"
            
            // Add entries
            for entry in relevantEntries {
                let relativePath = entry.source.replacingOccurrences(of: sourceURL?.path ?? "", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                manifestContent += "\(relativePath),\(entry.checksum),\(entry.algorithm),\(entry.fileSize),\(entry.action),\(entry.timestamp.ISO8601Format())\n"
            }
            
            // Write manifest
            try? manifestContent.write(to: manifestFile, atomically: true, encoding: .utf8)
            
            print("✅ Wrote checksum manifest to: \(manifestFile.lastPathComponent)")
        }
    }
    
    func isNetworkVolume(at url: URL) -> Bool {
        var stat = statfs()
        guard statfs(url.path, &stat) == 0 else {
            return false
        }

        let fsType = withUnsafePointer(to: &stat.f_fstypename) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MFSTYPENAMELEN)) {
                String(cString: $0)
            }
        }

        print("🔍 Volume at \(url.lastPathComponent) is of type: \(fsType)")
        return ["smbfs", "afpfs", "webdav", "nfs", "fuse", "cifs"].contains(fsType.lowercased())
    }
    
    func detectModifiedFiles(source: URL, destination: URL) throws -> Bool {
        // Get file attributes
        let sourceAttrs = try FileManager.default.attributesOfItem(atPath: source.path)
        let destAttrs = try FileManager.default.attributesOfItem(atPath: destination.path)
        
        let sourceSize = sourceAttrs[.size] as? Int64 ?? 0
        let destSize = destAttrs[.size] as? Int64 ?? 0
        
        // If sizes match, we still need to check checksums
        if sourceSize == destSize {
            let sourceChecksum = try sha256Checksum(for: source)
            let destChecksum = try sha256Checksum(for: destination)
            
            if sourceChecksum != destChecksum {
                print("⚠️ File has same size but different checksum: \(source.lastPathComponent)")
                return true
            }
        }
        
        return false
    }
    
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
            if !destinationURLs.isEmpty {
                selectDestinationFolder(at: 0)
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AddDestination"),
            object: nil,
            queue: .main
        ) { _ in
            if destinationURLs.count < 4 {
                destinationURLs.append(nil)
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("RunBackup"),
            object: nil,
            queue: .main
        ) { _ in
            if sourceURL != nil && !destinationURLs.compactMap({ $0 }).isEmpty && !isProcessing {
                runCopyAndVerify()
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ClearAll"),
            object: nil,
            queue: .main
        ) { _ in
            clearAllSelections()
        }
    }
    
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
                    if !destinationURLs.isEmpty {
                        selectDestinationFolder(at: 0)
                    }
                    return nil
                default:
                    break
                }
            }
            
            // Escape key to cancel operation
            if event.keyCode == 53 && isProcessing { // 53 is the key code for Escape
                // In a real implementation, you'd add cancellation logic here
                print("Cancel operation requested")
                return nil
            }
            
            return event
        }
    }
    
    func selectSourceFolder() {
        let dialog = NSOpenPanel()
        dialog.canChooseFiles = false
        dialog.canChooseDirectories = true
        dialog.allowsMultipleSelection = false

        if dialog.runModal() == .OK {
            if let url = dialog.url {
                sourceURL = url
                saveBookmark(url: url, key: sourceKey)
                tagSourceFolder(at: url)
            }
        }
    }
    
    func selectDestinationFolder(at index: Int) {
        guard index < destinationURLs.count else { return }
        
        let dialog = NSOpenPanel()
        dialog.canChooseFiles = false
        dialog.canChooseDirectories = true
        dialog.allowsMultipleSelection = false

        if dialog.runModal() == .OK {
            if let url = dialog.url {
                // Check if this is a source folder
                if checkForSourceTag(at: url) {
                    // Show alert
                    let alert = NSAlert()
                    alert.messageText = "Source Folder Selected"
                    alert.informativeText = "This folder has been tagged as a source folder. Using it as a destination could lead to data loss. Please select a different folder."
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                    return
                }
                
                destinationURLs[index] = url
                if index < destinationKeys.count {
                    saveBookmark(url: url, key: destinationKeys[index])
                }
            }
        }
    }
    
    func saveBookmark(url: URL, key: String) {
        do {
            let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: key)
        } catch {
            print("Failed to save bookmark: \(error)")
        }
    }
    
    func cancelOperation() {
        shouldCancel = true
        statusMessage = "Cancelling backup..."
        currentOperation?.cancel()
        
        // Write debug log to file
        writeDebugLog()
    }
    
    func writeDebugLog() {
        // Only write debug log if there are slow operations or errors
        let hasSlowOperations = debugLog.contains { $0.contains("SLOW CHECKSUM") }
        let hasErrors = !failedFiles.isEmpty || shouldCancel
        
        if !hasSlowOperations && !hasErrors {
            return  // Nothing interesting to log
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        
        var logContent = "ImageIntact Debug Log - \(timestamp)\n"
        logContent += "Session ID: \(sessionID)\n"
        logContent += "Total Files: \(totalFiles)\n"
        logContent += "Processed Files: \(processedFiles)\n"
        logContent += "Failed Files: \(failedFiles.count)\n"
        logContent += "Was Cancelled: \(shouldCancel)\n\n"
        logContent += "Checksum Timings:\n"
        logContent += debugLog.joined(separator: "\n")
        
        // Write to app's Documents folder which we have access to
        if let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let logDir = documentsURL.appendingPathComponent("ImageIntact_Logs")
            try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
            
            let logFile = logDir.appendingPathComponent("Debug_\(timestamp).log")
            
            do {
                try logContent.write(to: logFile, atomically: true, encoding: .utf8)
                print("📄 Debug log written to: \(logFile.path)")
                
                // If there were issues, notify the user
                if hasSlowOperations || hasErrors {
                    DispatchQueue.main.async {
                        let alert = NSAlert()
                        alert.messageText = "Debug Log Saved"
                        alert.informativeText = "Performance issues were detected. A debug log has been saved to:\n\n\(logFile.path)\n\nWould you like to open the log file?"
                        alert.alertStyle = .informational
                        alert.addButton(withTitle: "Open Log")
                        alert.addButton(withTitle: "OK")
                        
                        if alert.runModal() == .alertFirstButtonReturn {
                            NSWorkspace.shared.open(logFile)
                        }
                    }
                }
            } catch {
                print("❌ Failed to write debug log: \(error)")
            }
        }
    }
    
    func clearAllSelections() {
        sourceURL = nil
        UserDefaults.standard.removeObject(forKey: sourceKey)
        for (i, _) in destinationURLs.enumerated() {
            destinationURLs[i] = nil
            if i < destinationKeys.count {
                UserDefaults.standard.removeObject(forKey: destinationKeys[i])
            }
        }
        // Reset to show at least one destination slot
        destinationURLs = [nil]
    }

    func runCopyAndVerify() {
        guard let source = sourceURL else {
            print("Missing source folder.")
            return
        }

        let destinations = destinationURLs.compactMap { $0 }

        isProcessing = true
        statusMessage = "Preparing backup..."
        totalFiles = 0
        processedFiles = 0
        currentFile = ""
        failedFiles = []
        sessionID = UUID().uuidString
        logEntries = []
        shouldCancel = false
        debugLog = []

        // Run the operation on a background thread
        DispatchQueue.global(qos: .userInitiated).async {
            // Start accessing security-scoped resources
            let sourceAccess = source.startAccessingSecurityScopedResource()
            let destAccesses = destinations.map { $0.startAccessingSecurityScopedResource() }

            defer {
                // Always stop accessing when done
                if sourceAccess { source.stopAccessingSecurityScopedResource() }
                for (index, access) in destAccesses.enumerated() {
                    if access {
                        destinations[index].stopAccessingSecurityScopedResource()
                    }
                }

                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.shouldCancel = false
                    if !self.debugLog.isEmpty {
                        self.writeDebugLog()
                    }
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateStyle = .none
                    dateFormatter.timeStyle = .medium
                    let timeString = dateFormatter.string(from: Date())
                    
                    if self.failedFiles.isEmpty {
                        self.statusMessage = "✅ Backup completed at \(timeString)"
                    } else {
                        self.statusMessage = "⚠️ Backup completed at \(timeString) with \(self.failedFiles.count) errors"
                    }
                }
            }

            let fileManager = FileManager.default

            guard let enumerator = fileManager.enumerator(at: source, includingPropertiesForKeys: [.isDirectoryKey], options: [], errorHandler: nil) else {
                print("Failed to create enumerator for source directory.")
                return
            }

            let fileURLs = (enumerator.compactMap { $0 as? URL }).filter {
                guard let resourceValues = try? $0.resourceValues(forKeys: [.isDirectoryKey]),
                      resourceValues.isDirectory == false,
                      !$0.lastPathComponent.hasPrefix(".") else {
                    return false
                }
                return true
            }
            
            // Update total files count
            DispatchQueue.main.async {
                self.totalFiles = fileURLs.count
                self.statusMessage = "Found \(fileURLs.count) files to process"
            }
            
            // If no files found, exit early
            if fileURLs.isEmpty {
                DispatchQueue.main.async {
                    self.statusMessage = "No files found to backup"
                }
                return
            }

            let group = DispatchGroup()
            let queue = DispatchQueue(label: "com.tonalphoto.imageintact", qos: .userInitiated, attributes: .concurrent)
            let progressQueue = DispatchQueue(label: "com.tonalphoto.imageintact.progress", qos: .utility)
            
            // Detect network volumes and create semaphore for throttling
            let networkDestinations = Set(destinations.filter { isNetworkVolume(at: $0) })
            let networkSemaphore = DispatchSemaphore(value: 2) // Max 2 concurrent operations for network volumes
            
            if !networkDestinations.isEmpty {
                print("🌐 Detected \(networkDestinations.count) network destination(s), will throttle concurrent writes")
            }
            
            for fileURL in fileURLs {
                // Check for cancellation before processing each file
                if self.shouldCancel {
                    DispatchQueue.main.async {
                        self.statusMessage = "Backup cancelled by user"
                        self.isProcessing = false
                    }
                    break
                }
                
                group.enter()
                queue.async(qos: .userInitiated) {
                    defer {
                        group.leave()
                        progressQueue.async {
                            self.processedFiles += 1
                        }
                    }
                    
                    // Check for cancellation at start of each file operation
                    if self.shouldCancel {
                        return
                    }
                    
                    let relativePath = fileURL.path.replacingOccurrences(of: source.path + "/", with: "")
                    
                    // Update current file
                    DispatchQueue.main.async {
                        self.currentFile = fileURL.lastPathComponent
                    }

                    do {
                        let sourceChecksum = try self.sha256Checksum(for: fileURL)

                        for dest in destinations {
                            // Throttle network destinations
                            let isNetwork = networkDestinations.contains(dest)
                            if isNetwork {
                                networkSemaphore.wait()
                            }
                            
                            defer {
                                if isNetwork {
                                    networkSemaphore.signal()
                                }
                            }
                            
                            let destPath = dest.appendingPathComponent(relativePath)
                            let destDir = destPath.deletingLastPathComponent()
                            
                            // Create directory if needed
                            if !fileManager.fileExists(atPath: destDir.path) {
                                try fileManager.createDirectory(at: destDir, withIntermediateDirectories: true, attributes: nil)
                            }
                            
                            // Check if file already exists and has matching checksum
                            var needsCopy = true
                            if fileManager.fileExists(atPath: destPath.path) {
                                // Check for modified files even with same size
                                let isModified = try self.detectModifiedFiles(source: fileURL, destination: destPath)
                                
                                if !isModified {
                                    let existingChecksum = try self.sha256Checksum(for: destPath)
                                    if existingChecksum == sourceChecksum {
                                        print("✅ \(relativePath) to \(dest.lastPathComponent): already exists with matching checksum, skipping.")
                                        self.logAction(action: "SKIPPED", source: fileURL, destination: destPath, checksum: sourceChecksum, reason: "Already exists with matching checksum")
                                        needsCopy = false
                                    }
                                } else {
                                    print("⚠️  \(relativePath) to \(dest.lastPathComponent): exists with same size but different checksum, will quarantine and replace.")
                                    // Quarantine the existing file
                                    try self.quarantineFile(at: destPath, fileManager: fileManager)
                                    self.logAction(action: "QUARANTINED", source: fileURL, destination: destPath, checksum: try self.sha256Checksum(for: destPath), reason: "Same size but checksum mismatch")
                                }
                            }
                            
                            // Only copy if needed
                            if needsCopy {
                                try fileManager.copyItem(at: fileURL, to: destPath)
                                let destChecksum = try self.sha256Checksum(for: destPath)
                                if sourceChecksum == destChecksum {
                                    print("✅ \(relativePath) to \(dest.lastPathComponent): copied successfully, checksums match.")
                                    self.logAction(action: "COPIED", source: fileURL, destination: destPath, checksum: destChecksum, reason: "")
                                } else {
                                    print("❌ \(relativePath) to \(dest.lastPathComponent): checksum mismatch after copy!")
                                    self.logAction(action: "FAILED", source: fileURL, destination: destPath, checksum: destChecksum, reason: "Checksum mismatch after copy")
                                    DispatchQueue.main.async {
                                        self.failedFiles.append((file: relativePath, destination: dest.lastPathComponent, error: "Checksum mismatch after copy"))
                                    }
                                }
                            }
                        }
                    } catch {
                        print("Error processing \(relativePath): \(error.localizedDescription)")
                        DispatchQueue.main.async {
                            self.failedFiles.append((file: relativePath, destination: "Multiple", error: error.localizedDescription))
                        }
                    }
                }
            }

            group.wait()
            
            // Write checksum manifests for each destination
            DispatchQueue.main.async {
                self.writeChecksumManifests(for: destinations)
            }
        }
    }

    func xxh128Checksum(for fileURL: URL) throws -> String {
        // The xxHash-Swift package uses a different API structure
        // We need to use xxHash_Swift as the module name
        // For now, let's fall back to SHA256 until we figure out the exact API
        return try sha256Checksum(for: fileURL)
    }
    
    func sha256Checksum(for fileURL: URL) throws -> String {
        let startTime = Date()
        defer {
            let elapsed = Date().timeIntervalSince(startTime)
            let logMessage = "Checksum for \(fileURL.lastPathComponent): \(String(format: "%.2f", elapsed))s"
            DispatchQueue.main.async {
                self.debugLog.append(logMessage)
                if self.debugLog.count > 100 {
                    self.debugLog.removeFirst()
                }
            }
            if elapsed > 2.0 {
                print("⚠️ SLOW CHECKSUM: \(logMessage)")
            }
        }
        
        // Retry mechanism for network drives
        var lastError: Error?
        
        for attempt in 1...3 {  // Reduced from 5 to 3 attempts
            do {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/shasum")
                process.arguments = ["-a", "256", fileURL.path]

                let pipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = pipe
                process.standardError = errorPipe
                
                // Set up file handles before running process
                let outputHandle = pipe.fileHandleForReading
                let errorHandle = errorPipe.fileHandleForReading

                try process.run()
                
                // Add timeout mechanism - 30 seconds max per checksum
                let timeoutSeconds: TimeInterval = 30.0
                let deadline = Date().addingTimeInterval(timeoutSeconds)
                
                while process.isRunning && Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.1)
                }
                
                if process.isRunning {
                    process.terminate()
                    // Give it a moment to terminate gracefully
                    Thread.sleep(forTimeInterval: 0.5)
                    if process.isRunning {
                        process.interrupt()  // Force kill if needed
                    }
                    // Clean up file handles
                    try? outputHandle.close()
                    try? errorHandle.close()
                    throw NSError(domain: "ImageIntact", code: 4, userInfo: [NSLocalizedDescriptionKey: "Checksum timed out after \(timeoutSeconds) seconds for \(fileURL.lastPathComponent)"])
                }

                guard process.terminationStatus == 0 else {
                    let errorData = errorHandle.readDataToEndOfFile()
                    let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                    // Clean up file handles
                    try? outputHandle.close()
                    try? errorHandle.close()
                    throw NSError(domain: "ImageIntact", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "shasum failed: \(errorOutput)"])
                }

                let data = outputHandle.readDataToEndOfFile()
                // Clean up file handles
                try? outputHandle.close()
                try? errorHandle.close()
                
                guard let output = String(data: data, encoding: .utf8),
                      let checksum = output.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .whitespaces).first else {
                    throw NSError(domain: "ImageIntact", code: 2, userInfo: [NSLocalizedDescriptionKey: "Checksum parsing failed"])
                }

                return checksum
            } catch {
                lastError = error
                print("⏳ Checksum attempt \(attempt) failed for \(fileURL.lastPathComponent): \(error.localizedDescription)")
                if attempt < 3 {
                    // Use async sleep instead of blocking Thread.sleep
                    Thread.sleep(forTimeInterval: Double(attempt) * 0.5)  // Shorter delays
                }
            }
        }
        
        throw lastError ?? NSError(domain: "ImageIntact", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to calculate checksum after 3 attempts"])
    }
    
    func quarantineFile(at url: URL, fileManager: FileManager) throws {
        let quarantineDir = url.deletingLastPathComponent().appendingPathComponent(".ImageIntactQuarantine")
        
        // Create quarantine directory if needed
        if !fileManager.fileExists(atPath: quarantineDir.path) {
            try fileManager.createDirectory(at: quarantineDir, withIntermediateDirectories: true)
            
            // Hide the quarantine folder
            try fileManager.setAttributes([.extensionHidden: true], ofItemAtPath: quarantineDir.path)
        }
        
        // Create timestamped filename
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let quarantinedName = "\(url.lastPathComponent)_\(timestamp)"
        let quarantineDestination = quarantineDir.appendingPathComponent(quarantinedName)
        
        // Move file to quarantine
        try fileManager.moveItem(at: url, to: quarantineDestination)
    }
    
    func tagSourceFolder(at url: URL) {
        let tagFile = url.appendingPathComponent(".imageintact_source")
        let tagContent = """
        {
            "source_id": "\(UUID().uuidString)",
            "tagged_date": "\(Date().ISO8601Format())",
            "app_version": "1.0.0"
        }
        """
        
        do {
            try tagContent.write(to: tagFile, atomically: true, encoding: .utf8)
            // Hide the tag file
            try FileManager.default.setAttributes([.extensionHidden: true], ofItemAtPath: tagFile.path)
        } catch {
            print("Failed to tag source folder: \(error)")
        }
    }
    
    func checkForSourceTag(at url: URL) -> Bool {
        let tagFile = url.appendingPathComponent(".imageintact_source")
        return FileManager.default.fileExists(atPath: tagFile.path)
    }
    
    func logAction(action: String, source: URL, destination: URL, checksum: String, reason: String = "") {
        // Get file size
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: source.path)[.size] as? Int64) ?? 0
        
        // Create log entry
        let entry = LogEntry(
            timestamp: Date(),
            sessionID: sessionID,
            action: action,
            source: source.path,
            destination: destination.path,
            checksum: checksum,
            algorithm: "SHA256",
            fileSize: fileSize,
            reason: reason
        )
        
        // Add to in-memory log
        DispatchQueue.main.async {
            self.logEntries.append(entry)
        }
        
        // Write to log file
        writeLogEntry(entry, to: destination.deletingLastPathComponent())
    }
    
    func writeLogEntry(_ entry: LogEntry, to baseDir: URL) {
        let logDir = baseDir.appendingPathComponent(".imageintact_logs")
        
        // Create log directory if needed
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.extensionHidden: true], ofItemAtPath: logDir.path)
        
        // Create log file name with date
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())
        let logFile = logDir.appendingPathComponent("imageintact_\(dateString).csv")
        
        // Create CSV header if file doesn't exist
        if !FileManager.default.fileExists(atPath: logFile.path) {
            let header = "timestamp,session_id,action,source,destination,checksum,algorithm,file_size,reason\n"
            try? header.write(to: logFile, atomically: true, encoding: .utf8)
        }
        
        // Format timestamp
        let timestampFormatter = DateFormatter()
        timestampFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timestampString = timestampFormatter.string(from: entry.timestamp)
        
        // Escape CSV fields
        let escapedSource = entry.source.contains(",") ? "\"\(entry.source)\"" : entry.source
        let escapedDest = entry.destination.contains(",") ? "\"\(entry.destination)\"" : entry.destination
        let escapedReason = entry.reason.contains(",") ? "\"\(entry.reason)\"" : entry.reason
        
        // Create CSV line
        let logLine = "\(timestampString),\(entry.sessionID),\(entry.action),\(escapedSource),\(escapedDest),\(entry.checksum),\(entry.algorithm),\(entry.fileSize),\(escapedReason)\n"
        
        // Append to log file
        if let fileHandle = FileHandle(forWritingAtPath: logFile.path) {
            fileHandle.seekToEndOfFile()
            if let data = logLine.data(using: .utf8) {
                fileHandle.write(data)
            }
            fileHandle.closeFile()
        } else {
            // File doesn't exist, write it
            try? logLine.write(to: logFile, atomically: true, encoding: .utf8)
        }
    }

    static func loadBookmark(forKey key: String) -> URL? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        var isStale = false
        return try? URL(resolvingBookmarkData: data, options: [.withoutUI, .withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale)
    }
    
    static func loadDestinationBookmarks() -> [URL?] {
        let keys = ["dest1Bookmark", "dest2Bookmark", "dest3Bookmark", "dest4Bookmark"]
        var urls: [URL?] = []
        
        // Load all saved bookmarks in their exact positions
        for key in keys {
            if let url = loadBookmark(forKey: key) {
                print("Loaded destination from \(key): \(url.lastPathComponent)")
                urls.append(url)
            } else {
                print("No bookmark found for \(key)")
                // Stop looking for more bookmarks after finding an empty slot
                break
            }
        }
        
        // Always show at least one slot
        if urls.isEmpty {
            urls = [nil]
        }
        
        print("Total destinations loaded: \(urls.count)")
        return urls
    }
}

// Reusable folder selection row
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
