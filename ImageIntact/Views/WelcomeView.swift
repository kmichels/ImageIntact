import SwiftUI

// Welcome view for first-run experience
struct WelcomeView: View {
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)
                
                Text("Welcome to ImageIntact")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Your reliable photo backup companion")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 20)
            
            // What it does
            VStack(alignment: .leading, spacing: 16) {
                Text("What ImageIntact Does:")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                VStack(alignment: .leading, spacing: 12) {
                    FeatureRow(icon: "checkmark.shield", 
                              title: "Safe Backup", 
                              description: "Verifies every file with checksums to ensure perfect copies")
                    
                    FeatureRow(icon: "arrow.triangle.branch", 
                              title: "Multiple Destinations", 
                              description: "Copy to up to 4 locations simultaneously for redundancy")
                    
                    FeatureRow(icon: "bolt", 
                              title: "Fast & Smart", 
                              description: "Uses SHA-256 checksums for reliable verification")
                    
                    FeatureRow(icon: "shield.lefthalf.filled", 
                              title: "Never Lose Data", 
                              description: "Never deletes files - quarantines mismatched files safely")
                }
            }
            .padding(.horizontal, 20)
            
            Divider()
            
            // How to use
            VStack(alignment: .leading, spacing: 16) {
                Text("How to Use:")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                VStack(alignment: .leading, spacing: 8) {
                    HowToRow(number: 1, text: "Select your source folder (where your photos are)")
                    HowToRow(number: 2, text: "Choose one or more destination folders for backup")
                    HowToRow(number: 3, text: "Click 'Run Backup' to start the process")
                    HowToRow(number: 4, text: "Watch the progress and let ImageIntact work safely")
                }
            }
            .padding(.horizontal, 20)
            
            Spacer()
            
            // Bottom buttons
            HStack(spacing: 16) {
                Button("Show Help") {
                    isPresented = false
                    NotificationCenter.default.post(name: NSNotification.Name("ShowHelp"), object: nil)
                }
                .buttonStyle(.borderless)
                
                Spacer()
                
                Button("Get Started") {
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(width: 500, height: 650)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// Feature row for welcome view
struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
    }
}

// How-to row for welcome view
struct HowToRow: View {
    let number: Int
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.accentColor)
                .frame(width: 16, alignment: .leading)
            
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer()
        }
    }
}