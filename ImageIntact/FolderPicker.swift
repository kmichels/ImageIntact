import SwiftUI
import AppKit

struct FolderPicker: View {
    var title: String
    @Binding var selectedURL: URL?

    var body: some View {
        HStack {
            Button(title) {
                selectFolder()
            }
            if let url = selectedURL {
                Text(url.lastPathComponent).font(.subheadline)
            }
        }
    }

    func selectFolder() {
        let dialog = NSOpenPanel()
        dialog.canChooseFiles = false
        dialog.canChooseDirectories = true
        dialog.allowsMultipleSelection = false

        if dialog.runModal() == .OK {
            selectedURL = dialog.url
        }
    }
}
