import SwiftUI

@main
struct SnipbookApp: App {
    @State private var store = LibraryStore()

    init() {
        // Lets `swift run` show a Dock icon and menu bar like the bundled .app does.
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        Window("Snipbook", id: "main") {
            ContentView(store: store)
                .frame(minWidth: 900, minHeight: 520)
                #if DEBUG
                .onAppear { DebugSnapshot.scheduleIfRequested(store: store) }
                #endif
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    store.flushSaves()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    // Pick up changes made in Finder or another editor.
                    store.reload()
                }
        }
        .defaultSize(width: 1200, height: 760)
        .commands { SnipbookCommands(store: store) }
    }
}

struct SnipbookCommands: Commands {
    let store: LibraryStore

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Snippet") { store.createSnippet(language: store.lastLanguage) }
                .keyboardShortcut("n")
            Menu("New Snippet In") {
                ForEach(Language.all) { language in
                    Button(language.name) { store.createSnippet(language: language) }
                }
            }
            Button("New Folder") { store.createFolder() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Divider()
            Button("Choose Library Folder…") { store.chooseLibrary() }
            Button("Reveal Library in Finder") { store.reveal(store.root) }
            Button("Reload Library") { store.reload() }
                .keyboardShortcut("r")
        }

        CommandMenu("Snippet") {
            let snippet = store.selectedSnippet
            Button(snippet?.isLocked == true ? "Unlock" : "Lock") {
                if let snippet { store.toggleLock(snippet) }
            }
            .keyboardShortcut("l")
            .disabled(snippet == nil)

            Button("Copy Contents") { if let snippet { store.copyToPasteboard(snippet) } }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(snippet == nil)

            Button("Duplicate") { if let snippet { store.duplicate(snippet) } }
                .keyboardShortcut("d")
                .disabled(snippet == nil)

            Button("Reveal in Finder") { if let snippet { store.reveal(snippet.url) } }
                .disabled(snippet == nil)

            Divider()

            // No shortcut on purpose: ⌘⌫ means "delete to start of line" while editing.
            Button("Move to Trash") { if let snippet { store.trash(snippet) } }
                .disabled(snippet == nil || snippet?.isLocked == true)
        }
    }
}
