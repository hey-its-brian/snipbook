#if DEBUG
import AppKit

/// Debug builds only. Renders a window to a PNG, then quits, so UI can be checked from a script:
///
///     -snapshotPath out.png           where to write the image (required)
///     -snapshotSelect "A|B"           select snippets by title (several = multi-select)
///     -snapshotFolder "Ruby & Rails"  select a sidebar folder by path relative to the library
///     -snapshotSettings YES           capture the Settings window instead
///     -snapshotDark YES               force dark mode
@MainActor
enum DebugSnapshot {
    static func scheduleIfRequested(store: LibraryStore) {
        let defaults = UserDefaults.standard
        guard let path = defaults.string(forKey: "snapshotPath") else { return }
        if defaults.bool(forKey: "snapshotDark") { NSApp.appearance = NSAppearance(named: .darkAqua) }
        let wantsSettings = defaults.bool(forKey: "snapshotSettings")

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if let folder = defaults.string(forKey: "snapshotFolder") {
                store.sidebarSelection = .folder(store.root.appendingPathComponent(folder).standardizedFileURL.path)
            }
            if let titles = defaults.string(forKey: "snapshotSelect")?.split(separator: "|").map(String.init) {
                let matches = store.snippets.filter { titles.contains($0.title) }
                if defaults.string(forKey: "snapshotFolder") == nil, matches.count == 1 {
                    store.sidebarSelection = .folder(matches[0].folderPath)
                }
                store.selection = Set(matches.map(\.id))
            }
            if wantsSettings {
                // Same as choosing Snipbook > Settings… (⌘,).
                if let appMenu = NSApp.mainMenu?.items.first?.submenu,
                   let index = appMenu.items.firstIndex(where: { $0.keyEquivalent == "," }) {
                    appMenu.performActionForItem(at: index)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                let visible = NSApp.windows.filter(\.isVisible)
                let window = visible.first { $0.title.hasSuffix("Settings") == wantsSettings }
                guard let view = (window ?? visible.first)?.contentView?.superview,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                NSApp.terminate(nil)
            }
        }
    }
}
#endif
