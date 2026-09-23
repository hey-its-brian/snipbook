#if DEBUG
import AppKit

/// Debug builds only: `-snapshotPath out.png [-snapshotSelect "Title"] [-snapshotDark YES]`
/// renders the main window to a PNG, so UI can be checked without screen recording permission.
@MainActor
enum DebugSnapshot {
    static func scheduleIfRequested(store: LibraryStore) {
        let defaults = UserDefaults.standard
        guard let path = defaults.string(forKey: "snapshotPath") else { return }
        if defaults.bool(forKey: "snapshotDark") { NSApp.appearance = NSAppearance(named: .darkAqua) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if let title = defaults.string(forKey: "snapshotSelect"),
               let snippet = store.snippets.first(where: { $0.title == title }) {
                store.sidebarSelection = .folder(snippet.folderPath)
                store.selectedSnippetID = snippet.id
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                guard let window = NSApp.windows.first(where: { $0.isVisible }),
                      let view = window.contentView?.superview,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                NSApp.terminate(nil)
            }
        }
    }
}
#endif
