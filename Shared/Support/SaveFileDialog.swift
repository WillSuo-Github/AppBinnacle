#if os(macOS)
import AppKit

@MainActor
enum SaveFileDialog {
    static func save(filename: String, content: String) {
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = filename
        savePanel.canCreateDirectories = true
        if savePanel.runModal() == .OK, let url = savePanel.url {
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
#endif
