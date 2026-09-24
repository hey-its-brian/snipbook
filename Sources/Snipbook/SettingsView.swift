import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Bindable var store: LibraryStore

    var body: some View {
        Form {
            Section {
                LabeledContent("Location") {
                    Text(displayPath(store.root))
                        .truncationMode(.middle)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
                HStack {
                    Spacer()
                    Button("Reveal in Finder") { store.reveal(store.root) }
                    Button("Change…") { store.chooseLibrary() }
                }
            } header: {
                Text("Library")
            } footer: {
                Text("When you change the location you can move your existing snippets along, or leave them where they are.")
                    .settingsFootnote()
            }

            Section("New Snippets") {
                Picker("Save new snippets in", selection: $store.newSnippetDestination) {
                    Text("Folder selected in sidebar").tag(NewSnippetDestination.selected)
                    Text("Library root").tag(NewSnippetDestination.root)
                    Divider()
                    ForEach(store.allFoldersFlat) { folder in
                        let relative = store.relativeFolder(ofPath: folder.id)
                        Text(relative).tag(NewSnippetDestination.folder(relative))
                    }
                    if missingDestination {
                        Text("\(String(store.newSnippetDestination.dropFirst("folder:".count))) (missing)")
                            .tag(store.newSnippetDestination)
                    }
                }
                if missingDestination {
                    Text("That folder no longer exists, so new snippets go to the folder selected in the sidebar.")
                        .settingsFootnote()
                }
                Toggle("Show snippets from subfolders when a folder is selected", isOn: $store.includeSubfolders)
            }

            Section("Editor") {
                Toggle("Show line numbers", isOn: $store.showLineNumbers)
            }

            Section {
                LabeledContent("Shortcut") { ShortcutRecorder() }
                Toggle("Paste into the front app after choosing a snippet", isOn: $store.pasteAfterQuickSearch)
                if store.pasteAfterQuickSearch && !axTrusted {
                    HStack {
                        Label("Pasting needs Accessibility access for Snipbook. Until then, snippets are copied only.",
                              systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Grant Access…") {
                            let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                            _ = AXIsProcessTrustedWithOptions(prompt)
                        }
                    }
                    .font(.callout)
                }
                Toggle("Open Snipbook at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { setLaunchAtLogin($0) }
                ))
            } header: {
                Text("Quick Search")
            } footer: {
                Text("Press the shortcut in any app to search your snippets. Return pastes, ⌘Return only copies. Opening at login keeps the shortcut available.")
                    .settingsFootnote()
            }

            Section {
                HStack(spacing: 14) {
                    ForEach(AppIconChoice.allCases) { choice in
                        IconTile(choice: choice, isSelected: store.appIcon == choice) {
                            store.appIcon = choice
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            } header: {
                Text("App Icon")
            } footer: {
                Text("Changes the icon in the Dock and Finder.")
                    .settingsFootnote()
            }
        }
        .formStyle(.grouped)
        .frame(width: 540)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear(perform: refreshStatus)
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in refreshStatus() }
    }

    @State private var axTrusted = AXIsProcessTrusted()
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    /// Permission and login-item state can change in System Settings while this window is open.
    private func refreshStatus() {
        axTrusted = AXIsProcessTrusted()
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            store.errorMessage = "Could not change the login item.\n\n\(error.localizedDescription)"
        }
        refreshStatus()
    }

    private var missingDestination: Bool {
        let setting = store.newSnippetDestination
        guard setting.hasPrefix("folder:") else { return false }
        let relative = String(setting.dropFirst("folder:".count))
        return !store.allFoldersFlat.contains { store.relativeFolder(ofPath: $0.id) == relative }
    }

    private func displayPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
    }
}

/// Click, then press the new shortcut. Escape cancels.
private struct ShortcutRecorder: View {
    @State private var recording = false
    @State private var monitor: Any?
    private let center = HotKeyCenter.shared

    var body: some View {
        HStack(spacing: 8) {
            Button(recording ? "Type shortcut…" : (center.shortcut?.display ?? "None")) {
                recording ? stop() : start()
            }
            .frame(minWidth: 110)
            if center.shortcut != nil {
                Button("Clear") { center.update(nil) }
            }
            if center.shortcut != .defaultQuickSearch {
                Button("Reset") { center.update(.defaultQuickSearch) }
            }
            if center.registrationFailed {
                Text("Unavailable").foregroundStyle(.red).font(.callout)
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        center.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {  // Escape
                stop()
            } else if let shortcut = KeyShortcut(event: event) {
                center.update(shortcut)
                stop()
            } else {
                NSSound.beep()
            }
            return nil
        }
    }

    private func stop() {
        guard recording else { return }
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        center.resume()
    }
}

private struct IconTile: View {
    let choice: AppIconChoice
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Group {
                    if let image = choice.image {
                        Image(nsImage: image).resizable().interpolation(.high)
                    } else {
                        Color.secondary.opacity(0.2)
                    }
                }
                .frame(width: 72, height: 72)
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 3)
                )
                Text(choice.title)
                    .font(.callout)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private extension Text {
    func settingsFootnote() -> some View {
        font(.callout).foregroundStyle(.secondary)
    }
}
