//
//  PrivacyExplanationView.swift
//  ImageIntact
//
//  Explains path anonymization to users
//

import SwiftUI

struct PrivacyExplanationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingFullHelp = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "lock.shield")
                    .font(.system(size: 24))
                    .foregroundColor(.accentColor)
                
                Text("Privacy Protection")
                    .font(.system(size: 18, weight: .semibold))
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            
            Divider()
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // What is Path Anonymization?
                    VStack(alignment: .leading, spacing: 12) {
                        Text("What is Path Anonymization?")
                            .font(.system(size: 14, weight: .semibold))
                        
                        Text("Path anonymization protects your privacy when sharing diagnostic logs with support or posting them online. It automatically replaces personal information in file paths with generic placeholders.")
                            .font(.system(size: 12))
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    // Why is this important?
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Why is this important?")
                            .font(.system(size: 14, weight: .semibold))
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Protects your username from being exposed", systemImage: "person.fill.xmark")
                                .font(.system(size: 12))
                            
                            Label("Hides names of your external drives", systemImage: "externaldrive.fill")
                                .font(.system(size: 12))
                            
                            Label("Keeps your folder structure private", systemImage: "folder.fill")
                                .font(.system(size: 12))
                            
                            Label("Prevents location tracking through file paths", systemImage: "location.slash.fill")
                                .font(.system(size: 12))
                        }
                    }
                    
                    // How it works
                    VStack(alignment: .leading, spacing: 12) {
                        Text("How it works")
                            .font(.system(size: 14, weight: .semibold))
                        
                        Text("When you export logs with anonymization enabled:")
                            .font(.system(size: 12))
                        
                        VStack(alignment: .leading, spacing: 10) {
                            ExampleRow(
                                original: "/Users/johndoe/Pictures/Vacation",
                                anonymized: "/Users/[USER]/Pictures/Vacation"
                            )
                            
                            ExampleRow(
                                original: "/Volumes/MyBackupDrive/Photos",
                                anonymized: "/Volumes/[VOLUME]/Photos"
                            )
                            
                            ExampleRow(
                                original: "/Users/jane/Library/Mobile Documents/iCloud",
                                anonymized: "/Users/[USER]/Library/Mobile Documents/iCloud"
                            )
                        }
                    }
                    
                    // What is preserved
                    VStack(alignment: .leading, spacing: 12) {
                        Text("What information is preserved?")
                            .font(.system(size: 14, weight: .semibold))
                        
                        Text("Important diagnostic information is kept to help troubleshoot issues:")
                            .font(.system(size: 12))
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text("• File extensions (.jpg, .raw, etc.)")
                            Text("• System paths (/System, /Library)")
                            Text("• Folder structure (to understand organization)")
                            Text("• Error messages and status codes")
                        }
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    }
                    
                    // Recommendation
                    GroupBox {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.green)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Recommendation")
                                    .font(.system(size: 12, weight: .semibold))
                                
                                Text("Keep this setting enabled (default) to protect your privacy when sharing logs.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                    }
                    
                    // Learn more button
                    HStack {
                        Spacer()
                        
                        Button(action: {
                            showingFullHelp = true
                        }) {
                            Label("View in Help Guide", systemImage: "questionmark.circle")
                                .font(.system(size: 12))
                        }
                        .controlSize(.small)
                        
                        Spacer()
                    }
                    .padding(.top, 8)
                }
                .padding(20)
            }
        }
        .frame(width: 500, height: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showingFullHelp) {
            // This would open the full help documentation
            HelpView(scrollToSection: "privacy")
        }
    }
}

struct ExampleRow: View {
    let original: String
    let anonymized: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text("Before:")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                
                Text(original)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.red.opacity(0.8))
            }
            
            HStack(spacing: 4) {
                Text("After:")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                
                Text(anonymized)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.green.opacity(0.8))
            }
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(4)
    }
}