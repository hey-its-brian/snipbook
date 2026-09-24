import AppKit
import Carbon.HIToolbox
import Observation
import SwiftUI

/// Spotlight-style snippet picker opened by the global shortcut.
///
/// macOS only routes key presses to the active app, so the panel activates Snipbook while it is
/// open (hiding the main window so it doesn't jump in front of your work), then hands focus back to
/// the app you came from before pasting.
@MainActor
final class QuickSearchController: NSObject, NSWindowDelegate {
    static let shared = QuickSearchController()

    var store: LibraryStore?
    private var panel: QuickSearchPanel?
    private let model = QuickSearchModel()
    /// The app to return to (nil when Quick Search was opened from inside Snipbook).
    private var previousApp: NSRunningApplication?
    /// Snipbook windows made transparent while the panel is up, so activating Snipbook doesn't
    /// throw them in front of your work. (Ordering them out would make SwiftUI treat the app as
    /// having no windows.)
    private var fadedWindows: [NSWindow] = []
    /// True between asking macOS to activate Snipbook and it becoming active.
    private var isActivating = false
    private var activationObserver: NSObjectProtocol?

    func toggle() {
        if panel?.isVisible == true { close() } else { show() }
    }

    func show(query: String = "") {
        guard let store else { return }
        let panel = self.panel ?? makePanel(store: store)
        self.panel = panel
        store.reload()
        model.reset(query: query, store: store)
        position(panel)

        if !NSApp.isActive {
            previousApp = NSWorkspace.shared.frontmostApplication
            fadedWindows = NSApp.windows.filter { $0.isVisible && $0 !== panel && $0.level == .normal }
            for window in fadedWindows {
                window.alphaValue = 0
                window.ignoresMouseEvents = true
            }
            isActivating = true
            activationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.finishActivation() }
            }
            NSApp.activate(ignoringOtherApps: true)
        }
        panel.makeKeyAndOrderFront(nil)
    }

    private func finishActivation() {
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
        activationObserver = nil
        // Let AppKit finish picking a key window, then take focus back for the panel.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.panel?.makeKeyAndOrderFront(nil)
            self.isActivating = false
        }
    }

    /// - Parameter returnFocus: reactivate the app Quick Search was opened from. False when the
    ///   user clicked into another app, which already has focus.
    func close(returnFocus: Bool = true) {
        guard panel?.isVisible == true else { return }
        panel?.orderOut(nil)
        let previous = previousApp
        let windows = fadedWindows
        previousApp = nil
        fadedWindows = []
        if returnFocus, let previous { previous.activate() }
        // Restore once the other app is back in front, so the windows reappear behind it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            for window in windows {
                window.alphaValue = 1
                window.ignoresMouseEvents = false
            }
        }
    }

    /// Copies the snippet, closes the panel, and (if allowed) pastes into the app underneath.
    func choose(_ snippet: Snippet, paste: Bool) {
        guard let store else { return }
        store.copyToPasteboard([snippet])
        close()
        guard paste, store.pasteAfterQuickSearch, AXIsProcessTrusted() else { return }
        // Give the previous app a moment to become active again so ⌘V reaches it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            let source = CGEventSource(stateID: .combinedSessionState)
            for keyDown in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: keyDown)
                event?.flags = .maskCommand
                event?.post(tap: .cghidEventTap)
            }
        }
    }

    private func makePanel(store: LibraryStore) -> QuickSearchPanel {
        let panel = QuickSearchPanel(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 460),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.close() }
        panel.contentView = NSHostingView(rootView: QuickSearchView(
            store: store,
            model: model,
            onChoose: { [weak self] snippet, paste in self?.choose(snippet, paste: paste) },
            onCancel: { [weak self] in self?.close() }
        ))
        return panel
    }

    /// Upper third of the screen the pointer is on, like Spotlight.
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2,
                                     y: frame.maxY - frame.height * 0.22 - size.height))
    }

    // Clicking anywhere else dismisses it; that app already has focus, so don't take it back.
    func windowDidResignKey(_ notification: Notification) {
        // Finishing activation briefly moves key focus to another Snipbook window; that isn't a click away.
        if isActivating { return }
        close(returnFocus: false)
    }
}

final class QuickSearchPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

@MainActor
@Observable
final class QuickSearchModel {
    var query = ""
    var selectedID: String?
    /// Bumped on every show so the view re-focuses the search field.
    var focusToken = 0

    func reset(query: String, store: LibraryStore) {
        self.query = query
        selectedID = Self.results(in: store, query: query).first?.id
        focusToken += 1
    }

    /// Title matches first (prefix before substring), then tags, language, and contents.
    static func results(in store: LibraryStore, query raw: String) -> [Snippet] {
        let query = raw.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return Array(store.snippets.prefix(100)) }
        let tagQuery = query.hasPrefix("#") ? String(query.dropFirst()) : query
        func score(_ s: Snippet) -> Int? {
            if s.title.range(of: query, options: [.caseInsensitive, .anchored]) != nil { return 0 }
            if s.title.localizedCaseInsensitiveContains(query) { return 1 }
            if s.tags.contains(where: { $0.localizedCaseInsensitiveContains(tagQuery) }) { return 2 }
            if s.language.name.localizedCaseInsensitiveContains(query) { return 3 }
            if s.content.localizedCaseInsensitiveContains(query) { return 4 }
            return nil
        }
        let scored: [(snippet: Snippet, score: Int)] = store.snippets.compactMap { s in
            score(s).map { (s, $0) }
        }
        let sorted = scored.sorted { a, b in
            if a.score != b.score { return a.score < b.score }
            return a.snippet.title.localizedStandardCompare(b.snippet.title) == .orderedAscending
        }
        return sorted.prefix(100).map(\.snippet)
    }
}

struct QuickSearchView: View {
    let store: LibraryStore
    @Bindable var model: QuickSearchModel
    let onChoose: (Snippet, Bool) -> Void
    let onCancel: () -> Void
    @FocusState private var fieldFocused: Bool

    var body: some View {
        let results = QuickSearchModel.results(in: store, query: model.query)
        let selected = results.first { $0.id == model.selectedID }

        VStack(spacing: 0) {
            searchField(results: results, selected: selected)
            Divider()
            HStack(spacing: 0) {
                resultsList(results)
                Divider()
                preview(selected)
            }
            Divider()
            footer
        }
        .frame(width: 760, height: 460)
        .background(.regularMaterial)
        .onChange(of: model.query) { _, _ in
            model.selectedID = QuickSearchModel.results(in: store, query: model.query).first?.id
        }
        .onChange(of: model.focusToken) { _, _ in fieldFocused = true }
        .onAppear { fieldFocused = true }
    }

    private func searchField(results: [Snippet], selected: Snippet?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.title2).foregroundStyle(.secondary)
            TextField("Search snippets", text: $model.query)
                .textFieldStyle(.plain)
                .font(.title2)
                .focused($fieldFocused)
                .onKeyPress(.downArrow) { move(1, in: results); return .handled }
                .onKeyPress(.upArrow) { move(-1, in: results); return .handled }
                .onKeyPress(.escape) { onCancel(); return .handled }
                .onKeyPress(.return, phases: .down) { press in
                    if let selected { onChoose(selected, !press.modifiers.contains(.command)) }
                    return .handled
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func resultsList(_ results: [Snippet]) -> some View {
        ScrollViewReader { proxy in
            List(results, selection: $model.selectedID) { snippet in
                QuickSearchRow(snippet: snippet).id(snippet.id)
            }
            .listStyle(.sidebar)
            .contextMenu(forSelectionType: String.self) { _ in
                EmptyView()
            } primaryAction: { ids in
                if let id = ids.first, let snippet = store.snippet(withID: id) { onChoose(snippet, true) }
            }
            .onChange(of: model.selectedID) { _, id in
                if let id { proxy.scrollTo(id) }
            }
        }
        .frame(width: 280)
        .overlay {
            if results.isEmpty { Text("No matches").foregroundStyle(.secondary) }
        }
    }

    @ViewBuilder
    private func preview(_ selected: Snippet?) -> some View {
        if let selected {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(selected.title).font(.headline).lineLimit(1)
                    Spacer()
                    if selected.isLocked { Image(systemName: "lock.fill").foregroundStyle(.secondary) }
                    Text(store.relativeFolder(of: selected)).font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                CodeEditor(fileID: selected.id, text: selected.content, language: selected.language.id,
                           isEditable: false, showLineNumbers: store.showLineNumbers) { _ in }
            }
        } else {
            Color.clear
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            hint("↩", pasteHint)
            hint("⌘↩", "Copy only")
            hint("↑↓", "Choose")
            hint("⎋", "Close")
            Spacer()
            if store.pasteAfterQuickSearch && !AXIsProcessTrusted() {
                Text("Auto-paste needs Accessibility access (see Settings)")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var pasteHint: String {
        store.pasteAfterQuickSearch && AXIsProcessTrusted() ? "Paste" : "Copy"
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key).font(.caption.monospaced()).padding(.horizontal, 5).padding(.vertical, 1)
                .background(Color.secondary.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func move(_ delta: Int, in results: [Snippet]) {
        guard !results.isEmpty else { return }
        let index = results.firstIndex { $0.id == model.selectedID } ?? -1
        let next = min(max(index + delta, 0), results.count - 1)
        model.selectedID = results[next].id
    }
}

private struct QuickSearchRow: View {
    let snippet: Snippet

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(snippet.title).lineLimit(1)
            HStack(spacing: 6) {
                LanguageBadge(language: snippet.language)
                if !snippet.tags.isEmpty {
                    Text(snippet.tags.map { "#" + $0 }.joined(separator: " "))
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
