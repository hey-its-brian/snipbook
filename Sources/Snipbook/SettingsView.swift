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
