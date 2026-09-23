import SwiftUI

struct ContentView: View {
    @Bindable var store: LibraryStore

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } content: {
            SnippetListView(store: store)
                .navigationSplitViewColumnWidth(min: 240, ideal: 300)
        } detail: {
            if let snippet = store.selectedSnippet {
                SnippetDetailView(store: store, snippet: snippet)
            } else {
                ContentUnavailableView("No Snippet Selected", systemImage: "curlybraces",
                                       description: Text("Pick a snippet, or press ⌘N to create one."))
            }
        }
        .searchable(text: $store.searchText, placement: .toolbar, prompt: "Search snippets")
        .alert("Snipbook", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @Bindable var store: LibraryStore
    @State private var renameText = ""

    var body: some View {
        List(selection: $store.sidebarSelection) {
            Section("Library") {
                Label("All Snippets", systemImage: "tray.full")
                    .badge(store.snippets.count)
                    .tag(SidebarItem.all)
                    .dropDestination(for: URL.self) { urls, _ in store.receiveDrop(of: urls, into: store.root) }
                Label("Locked", systemImage: "lock")
                    .badge(store.lockedCount)
                    .tag(SidebarItem.locked)
            }
            Section("Folders") {
                OutlineGroup(store.folders, children: \.children) { folder in
                    Label(folder.name, systemImage: "folder")
                        .badge(store.snippets.filter { $0.folderPath == folder.id }.count)
                        .tag(SidebarItem.folder(folder.id))
                        .dropDestination(for: URL.self) { urls, _ in store.receiveDrop(of: urls, into: folder.url) }
                        .contextMenu { folderMenu(folder) }
                }
            }
        }
        .listStyle(.sidebar)
        .contextMenu {
            Button("New Folder") { store.createFolder(in: store.root) }
        }
        .toolbar {
            ToolbarItem {
                Button { store.createFolder() } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
                .help("New folder inside the selected folder")
            }
        }
        .alert("Rename Folder", isPresented: Binding(
            get: { store.folderPendingRename != nil },
            set: { if !$0 { store.folderPendingRename = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let url = store.folderPendingRename { store.renameFolder(url, to: renameText) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .onChange(of: store.folderPendingRename) { _, url in
            renameText = url?.lastPathComponent ?? ""
        }
    }

    @ViewBuilder
    private func folderMenu(_ folder: FolderNode) -> some View {
        Button("New Snippet Here") {
            store.sidebarSelection = .folder(folder.id)
            store.createSnippet(language: store.lastLanguage)
        }
        Button("New Subfolder") { store.createFolder(in: folder.url) }
        Divider()
        Button("Rename…") { store.folderPendingRename = folder.url }
        Button("Reveal in Finder") { store.reveal(folder.url) }
        Divider()
        Button("Move to Trash", role: .destructive) { store.trashFolder(folder.url) }
    }
}

// MARK: - Snippet list

struct SnippetListView: View {
    @Bindable var store: LibraryStore

    var body: some View {
        let showFolder = store.sidebarSelection == .all || store.sidebarSelection == .locked
        List(store.visibleSnippets, selection: $store.selectedSnippetID) { snippet in
            SnippetRow(snippet: snippet, folder: showFolder ? store.relativeFolder(of: snippet) : nil)
                .draggable(snippet.url)
                .contextMenu { SnippetMenu(store: store, snippet: snippet) }
        }
        .overlay {
            if store.visibleSnippets.isEmpty {
                if store.searchText.isEmpty {
                    ContentUnavailableView("No Snippets", systemImage: "doc.text",
                                           description: Text("Press ⌘N to add one here."))
                } else {
                    ContentUnavailableView.search(text: store.searchText)
                }
            }
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItem {
                Menu {
                    ForEach(Language.all) { language in
                        Button(language.name) { store.createSnippet(language: language) }
                    }
                } label: {
                    Label("New Snippet", systemImage: "square.and.pencil")
                } primaryAction: {
                    store.createSnippet(language: store.lastLanguage)
                }
                .help("New \(store.lastLanguage.name) snippet (click the arrow for other languages)")
            }
        }
    }

    private var title: String {
        switch store.sidebarSelection {
        case .locked: "Locked"
        case .folder(let path): URL(fileURLWithPath: path).lastPathComponent
        case .all, .none: "All Snippets"
        }
    }
}

struct SnippetRow: View {
    let snippet: Snippet
    let folder: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(snippet.title).font(.headline).lineLimit(1)
                if snippet.isLocked {
                    Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(preview)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack(spacing: 6) {
                LanguageBadge(language: snippet.language)
                if let folder, !folder.isEmpty {
                    Label(folder, systemImage: "folder").font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
        }
        .padding(.vertical, 3)
    }

    private var preview: String {
        let lines = snippet.content.split(separator: "\n", omittingEmptySubsequences: true).prefix(2)
        return lines.isEmpty ? "Empty" : lines.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
    }
}

struct LanguageBadge: View {
    let language: Language

    var body: some View {
        Text(language.name)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(language.tint.opacity(0.18), in: Capsule())
            .foregroundStyle(language.tint)
    }
}

struct SnippetMenu: View {
    let store: LibraryStore
    let snippet: Snippet

    var body: some View {
        Button("Copy Contents") { store.copyToPasteboard(snippet) }
        Button(snippet.isLocked ? "Unlock" : "Lock") { store.toggleLock(snippet) }
        Button("Duplicate") { store.duplicate(snippet) }
        Menu("Move To") {
            Button("Library Root") { store.move(snippet, toFolder: store.root) }
            Divider()
            ForEach(store.allFoldersFlat) { folder in
                Button(store.relativeFolder(ofPath: folder.id)) { store.move(snippet, toFolder: folder.url) }
            }
        }
        .disabled(snippet.isLocked)
        Button("Reveal in Finder") { store.reveal(snippet.url) }
        Divider()
        Button("Move to Trash", role: .destructive) { store.trash(snippet) }
            .disabled(snippet.isLocked)
    }
}

// MARK: - Detail

struct SnippetDetailView: View {
    @Bindable var store: LibraryStore
    let snippet: Snippet
    @State private var title = ""
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                TextField("Title", text: $title)
                    .textFieldStyle(.plain)
                    .font(.title2.weight(.semibold))
                    .focused($titleFocused)
                    .disabled(snippet.isLocked)
                    .onSubmit(commitTitle)
                    .layoutPriority(1)

                Picker("Language", selection: Binding(
                    get: { snippet.language },
                    set: { store.setLanguage($0, for: snippet) }
                )) {
                    ForEach(Language.all) { Text($0.name).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                .disabled(snippet.isLocked)

                Button { store.copyToPasteboard(snippet) } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .labelStyle(.iconOnly)
                .help("Copy snippet (⇧⌘C)")

                Toggle(isOn: Binding(
                    get: { snippet.isLocked },
                    set: { store.setLocked($0, for: snippet) }
                )) {
                    Label(snippet.isLocked ? "Locked" : "Unlocked",
                          systemImage: snippet.isLocked ? "lock.fill" : "lock.open")
                }
                .toggleStyle(.button)
                .labelStyle(.iconOnly)
                .tint(snippet.isLocked ? .orange : nil)
                .help("Lock prevents edits, renames, moves, and deletion (⌘L)")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if snippet.isLocked {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                    Text("Locked. Unlock to edit. The file is also locked in Finder.")
                    Spacer()
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(.yellow.opacity(0.12))
            }

            Divider()

            CodeEditor(fileID: snippet.id,
                       text: snippet.content,
                       language: snippet.language.id,
                       isEditable: !snippet.isLocked) { newText in
                store.updateContent(of: snippet.id, to: newText)
            }
        }
        .navigationTitle(snippet.title)
        .onAppear { title = snippet.title }
        .onChange(of: snippet.id) { _, _ in title = snippet.title }
        .onChange(of: titleFocused) { _, focused in if !focused { commitTitle() } }
    }

    private func commitTitle() {
        if title.trimmingCharacters(in: .whitespaces).isEmpty {
            title = snippet.title
        } else if title != snippet.title {
            store.rename(snippet, to: title)
        }
    }
}
