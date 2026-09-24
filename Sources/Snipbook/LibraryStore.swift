import AppKit
import Observation

struct FolderNode: Identifiable, Hashable {
    let url: URL
    /// nil for a leaf so OutlineGroup hides the disclosure triangle.
    var children: [FolderNode]?
    var id: String { url.path }
    var name: String { url.lastPathComponent }
}

struct Snippet: Identifiable, Hashable {
    let url: URL
    var content: String
    var isLocked: Bool
    var id: String { url.path }
    var title: String { url.deletingPathExtension().lastPathComponent }
    var language: Language { Language.forExtension(url.pathExtension) }
    var folderPath: String { url.deletingLastPathComponent().path }
}

enum SidebarItem: Hashable {
    case all
    case locked
    case folder(String)
}

/// Where new snippets are created. Stored in UserDefaults as a string:
/// "selected", "root", or "folder:<path relative to the library root>".
enum NewSnippetDestination {
    static let selected = "selected"
    static let root = "root"
    static func folder(_ relativePath: String) -> String { "folder:" + relativePath }
}

/// Owns the on-disk library. Folders are real directories, snippets are real files,
/// and "locked" is the Finder Locked flag (uchg), so the lock is enforced by macOS itself.
@MainActor
@Observable
final class LibraryStore {
    static let defaultRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Snippets", isDirectory: true)

    private enum Keys {
        static let libraryPath = "libraryPath"
        static let newSnippetDestination = "newSnippetDestination"
        static let includeSubfolders = "includeSubfolders"
        static let appIcon = "appIcon"
    }

    private(set) var root: URL
    private(set) var folders: [FolderNode] = []
    private(set) var snippets: [Snippet] = []
    /// Snippet count per folder path, including everything in its subfolders.
    private(set) var folderCounts: [String: Int] = [:]

    var sidebarSelection: SidebarItem? = .all {
        didSet { if sidebarSelection != oldValue { pruneSelectionToVisible() } }
    }
    var selection = Set<String>()
    var searchText = ""
    var errorMessage: String?
    var folderPendingRename: URL?
    var lastLanguage: Language = .all[0]

    // MARK: Settings

    var newSnippetDestination: String {
        didSet { defaults.set(newSnippetDestination, forKey: Keys.newSnippetDestination) }
    }
    /// When a folder is selected, also list snippets from its subfolders.
    var includeSubfolders: Bool {
        didSet { defaults.set(includeSubfolders, forKey: Keys.includeSubfolders) }
    }
    var appIcon: AppIconChoice {
        didSet {
            defaults.set(appIcon.rawValue, forKey: Keys.appIcon)
            AppIconManager.apply(appIcon, updateBundle: true)
        }
    }

    @ObservationIgnored private var dirty = Set<String>()
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    /// Snippet IDs being dragged, so dropping one row of a multi-selection moves them all.
    @ObservationIgnored private var dragIDs = Set<String>()
    @ObservationIgnored private let fm = FileManager.default
    @ObservationIgnored private let defaults: UserDefaults

    private static let maxFileSize = 1_000_000

    /// - Parameters:
    ///   - root: library folder to open; defaults to the saved setting or `~/Snippets`.
    ///   - defaults: settings store (tests pass a throwaway suite).
    init(root explicitRoot: URL? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let explicitRoot {
            root = explicitRoot
        } else if let saved = defaults.string(forKey: Keys.libraryPath) {
            root = URL(fileURLWithPath: saved, isDirectory: true)
        } else {
            root = Self.defaultRoot
        }
        newSnippetDestination = defaults.string(forKey: Keys.newSnippetDestination) ?? NewSnippetDestination.selected
        includeSubfolders = defaults.object(forKey: Keys.includeSubfolders) as? Bool ?? true
        appIcon = defaults.string(forKey: Keys.appIcon).flatMap(AppIconChoice.init(rawValue:)) ?? .midnight

        if explicitRoot == nil, !fm.fileExists(atPath: root.path) {
            SeedLibrary.install(at: root)
        }
        reload()
    }

    // MARK: - Derived state

    func snippet(withID id: String) -> Snippet? {
        snippets.first { $0.id == id }
    }

    func snippets(withIDs ids: Set<String>) -> [Snippet] {
        snippets.filter { ids.contains($0.id) }
    }

    var selectedSnippets: [Snippet] { snippets(withIDs: selection) }

    /// The snippet shown in the editor: only when exactly one is selected.
    var selectedSnippet: Snippet? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return snippet(withID: id)
    }

    var lockedCount: Int { snippets.filter(\.isLocked).count }

    var visibleSnippets: [Snippet] {
        var list: [Snippet]
        switch sidebarSelection {
        case .locked:
            list = snippets.filter(\.isLocked)
        case .folder(let path):
            list = snippets.filter {
                $0.folderPath == path || (includeSubfolders && $0.folderPath.hasPrefix(path + "/"))
            }
        case .all, .none:
            list = snippets
        }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            list = list.filter {
                $0.title.localizedCaseInsensitiveContains(query)
                    || $0.language.name.localizedCaseInsensitiveContains(query)
                    || $0.content.localizedCaseInsensitiveContains(query)
            }
        }
        return list
    }

    /// Folder selected in the sidebar, or the library root.
    var currentFolderURL: URL {
        if case .folder(let path) = sidebarSelection { return URL(fileURLWithPath: path, isDirectory: true) }
        return root
    }

    /// Where ⌘N puts a new snippet, per the Settings choice.
    var newSnippetFolderURL: URL {
        let setting = newSnippetDestination
        if setting == NewSnippetDestination.root { return root }
        if setting.hasPrefix("folder:") {
            let url = root.appendingPathComponent(String(setting.dropFirst("folder:".count)), isDirectory: true)
            if isDirectory(url) { return url.standardizedFileURL }
        }
        return currentFolderURL
    }

    func relativeFolder(of snippet: Snippet) -> String {
        relativeFolder(ofPath: snippet.folderPath)
    }

    func relativeFolder(ofPath path: String, from base: String? = nil) -> String {
        let basePath = base ?? root.path
        guard path.hasPrefix(basePath) else { return path }
        return String(path.dropFirst(basePath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// Folder shown under a list row: nil when the row is directly in the selected folder.
    func folderLabel(for snippet: Snippet) -> String? {
        switch sidebarSelection {
        case .folder(let path):
            return snippet.folderPath == path ? nil : relativeFolder(ofPath: snippet.folderPath, from: path)
        default:
            let label = relativeFolder(of: snippet)
            return label.isEmpty ? nil : label
        }
    }

    var allFoldersFlat: [FolderNode] {
        func walk(_ nodes: [FolderNode]) -> [FolderNode] {
            nodes.flatMap { [$0] + walk($0.children ?? []) }
        }
        return walk(folders)
    }

    // MARK: - Loading

    func reload() {
        flushSaves()
        root = root.standardizedFileURL
        folders = loadFolders(in: root)

        var found: [Snippet] = []
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey]
        if let walker = fm.enumerator(at: root, includingPropertiesForKeys: keys,
                                      options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            for case let url as URL in walker {
                let values = try? url.resourceValues(forKeys: Set(keys))
                if values?.isDirectory == true { continue }
                if (values?.fileSize ?? 0) > Self.maxFileSize { continue }
                if let snippet = loadSnippet(at: url.standardizedFileURL) { found.append(snippet) }
            }
        }
        snippets = found.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

        var counts: [String: Int] = [:]
        let rootPrefix = root.path + "/"
        for snippet in snippets {
            var dir = snippet.url.deletingLastPathComponent()
            while dir.path.hasPrefix(rootPrefix) {
                counts[dir.path, default: 0] += 1
                dir = dir.deletingLastPathComponent()
            }
        }
        folderCounts = counts

        let ids = Set(snippets.map(\.id))
        let kept = selection.intersection(ids)
        if kept != selection { selection = kept }
        if case .folder(let path) = sidebarSelection, !isDirectory(URL(fileURLWithPath: path)) {
            sidebarSelection = .all
        }
    }

    private func loadFolders(in dir: URL) -> [FolderNode] {
        let items = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey],
                                                 options: [.skipsHiddenFiles])) ?? []
        return items
            .filter { isDirectory($0) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { url in
                let kids = loadFolders(in: url)
                return FolderNode(url: url.standardizedFileURL, children: kids.isEmpty ? nil : kids)
            }
    }

    private func loadSnippet(at url: URL) -> Snippet? {
        // Anything that is not UTF-8 text (images, binaries) is not a snippet.
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return Snippet(url: url, content: content, isLocked: isLocked(url))
    }

    private func isLocked(_ url: URL) -> Bool {
        let attrs = try? fm.attributesOfItem(atPath: url.path)
        return (attrs?[.immutable] as? Bool) ?? false
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return fm.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    // MARK: - Editing and saving

    func updateContent(of id: String, to text: String) {
        guard let index = snippets.firstIndex(where: { $0.id == id }), !snippets[index].isLocked else { return }
        guard snippets[index].content != text else { return }
        snippets[index].content = text
        dirty.insert(id)
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.flushSaves()
        }
    }

    /// Writes pending edits. Called before anything that renames, moves, or locks a file
    /// so a delayed save can never resurrect a file at its old path.
    func flushSaves() {
        saveTask?.cancel()
        for id in dirty {
            guard let snippet = snippet(withID: id), !snippet.isLocked else { continue }
            do {
                try snippet.content.write(to: snippet.url, atomically: true, encoding: .utf8)
            } catch {
                report("Could not save \"\(snippet.title)\".", error)
            }
        }
        dirty.removeAll()
    }

    // MARK: - Creating

    func createSnippet(language: Language, in folder: URL? = nil) {
        flushSaves()
        lastLanguage = language
        let destination = (folder ?? newSnippetFolderURL).standardizedFileURL
        let url = uniqueURL(in: destination, name: "Untitled." + language.ext)
        do {
            try "".write(to: url, atomically: true, encoding: .utf8)
            searchText = ""
            reveal(inSidebar: destination)
            reload()
            selection = [url.standardizedFileURL.path]
        } catch {
            report("Could not create a snippet.", error)
        }
    }

    /// Makes sure a snippet created in `folder` is visible in the list.
    private func reveal(inSidebar folder: URL) {
        let path = folder.path
        switch sidebarSelection {
        case .all:
            return
        case .folder(let selected) where selected == path || (includeSubfolders && path.hasPrefix(selected + "/")):
            return
        default:
            sidebarSelection = path == root.path ? .all : .folder(path)
        }
    }

    func duplicate(_ items: [Snippet]) {
        flushSaves()
        var created = Set<String>()
        for snippet in items {
            let target = uniqueURL(in: snippet.url.deletingLastPathComponent(),
                                   name: "\(snippet.title) copy.\(snippet.url.pathExtension)")
            do {
                try snippet.content.write(to: target, atomically: true, encoding: .utf8)
                created.insert(target.standardizedFileURL.path)
            } catch {
                report("Could not duplicate \"\(snippet.title)\".", error)
            }
        }
        reload()
        if !created.isEmpty { selection = created }
    }

    // MARK: - Renaming and moving snippets

    func rename(_ snippet: Snippet, to newTitle: String) {
        let title = sanitized(newTitle)
        guard !title.isEmpty, title != snippet.title else { return }
        let target = snippet.url.deletingLastPathComponent()
            .appendingPathComponent(title).appendingPathExtension(snippet.url.pathExtension)
        relocateOne(snippet, to: target)
    }

    func setLanguage(_ language: Language, for snippet: Snippet) {
        guard language != snippet.language else { return }
        lastLanguage = language
        relocateOne(snippet, to: snippet.url.deletingPathExtension().appendingPathExtension(language.ext))
    }

    private func relocateOne(_ snippet: Snippet, to target: URL) {
        guard !snippet.isLocked else {
            errorMessage = "\"\(snippet.title)\" is locked. Unlock it before renaming it or changing its language."
            return
        }
        flushSaves()
        if fm.fileExists(atPath: target.path) {
            errorMessage = "A snippet named \"\(target.lastPathComponent)\" already exists there."
            return
        }
        do {
            try fm.moveItem(at: snippet.url, to: target)
            let wasSelected = selection.contains(snippet.id)
            reload()
            if wasSelected {
                selection.remove(snippet.id)
                selection.insert(target.standardizedFileURL.path)
            }
        } catch {
            report("Could not rename \"\(snippet.title)\".", error)
        }
    }

    /// Moves snippets into `folder`. Name clashes get a numbered name instead of failing.
    /// Locked snippets stay put, since macOS refuses to move them.
    @discardableResult
    func move(_ items: [Snippet], toFolder folder: URL) -> Bool {
        flushSaves()
        let folderPath = folder.standardizedFileURL.path
        var skippedLocked: [String] = []
        var movedAny = false
        var newSelection = selection
        for snippet in items where snippet.folderPath != folderPath {
            if snippet.isLocked {
                skippedLocked.append(snippet.title)
                continue
            }
            let target = uniqueURL(in: folder, name: snippet.url.lastPathComponent)
            do {
                try fm.moveItem(at: snippet.url, to: target)
                movedAny = true
                if newSelection.remove(snippet.id) != nil {
                    newSelection.insert(target.standardizedFileURL.path)
                }
            } catch {
                report("Could not move \"\(snippet.title)\".", error)
            }
        }
        reload()
        selection = newSelection.intersection(Set(snippets.map(\.id)))
        pruneSelectionToVisible()
        if !skippedLocked.isEmpty {
            errorMessage = "Locked snippets were not moved: \(skippedLocked.joined(separator: ", ")). Unlock them first."
        }
        return movedAny
    }

    /// Drops selected snippets the list no longer shows (after switching folders or moving them away).
    private func pruneSelectionToVisible() {
        let visible = Set(visibleSnippets.map(\.id))
        let kept = selection.intersection(visible)
        if kept != selection { selection = kept }
    }

    // MARK: - Locking, copying, trashing

    func setLocked(_ locked: Bool, for items: [Snippet]) {
        flushSaves()
        for snippet in items where snippet.isLocked != locked {
            do {
                try fm.setAttributes([.immutable: locked], ofItemAtPath: snippet.url.path)
                if let index = snippets.firstIndex(where: { $0.id == snippet.id }) {
                    snippets[index].isLocked = isLocked(snippet.url)
                }
            } catch {
                report("Could not change the lock on \"\(snippet.title)\".", error)
            }
        }
    }

    /// Locks everything unless everything is already locked, in which case it unlocks.
    func toggleLock(_ items: [Snippet]) {
        setLocked(!items.allSatisfy(\.isLocked), for: items)
    }

    func copyToPasteboard(_ items: [Snippet]) {
        guard !items.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(items.map(\.content).joined(separator: "\n\n"), forType: .string)
    }

    func trash(_ items: [Snippet]) {
        flushSaves()
        let locked = items.filter(\.isLocked).map(\.title)
        for snippet in items where !snippet.isLocked {
            do {
                try fm.trashItem(at: snippet.url, resultingItemURL: nil)
            } catch {
                report("Could not move \"\(snippet.title)\" to the Trash.", error)
            }
        }
        reload()
        if !locked.isEmpty {
            errorMessage = "Locked snippets were kept: \(locked.joined(separator: ", ")). Unlock them before moving them to the Trash."
        }
    }

    func reveal(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func reveal(_ url: URL) { reveal([url]) }

    // MARK: - Drag and drop

    /// Drag payload for a snippet row: the file URL, so rows can also be dragged out to Finder.
    /// Dragging a selected row carries the whole selection.
    func dragItem(for snippet: Snippet) -> NSItemProvider {
        dragIDs = selection.contains(snippet.id) ? selection : [snippet.id]
        return NSItemProvider(object: snippet.url as NSURL)
    }

    /// Kept for tests: same bookkeeping as `dragItem(for:)`.
    func beginDrag(_ snippet: Snippet) -> URL {
        dragIDs = selection.contains(snippet.id) ? selection : [snippet.id]
        return snippet.url
    }

    func beginDrag(folder: FolderNode) -> URL {
        noteDragStarted(folder: folder.url)
        return folder.url
    }

    func noteDragStarted(folder: URL) {
        dragIDs = []
    }

    /// Moves the snippets recorded by `dragItem(for:)` when the drop carried no readable URLs.
    func dropPendingDrag(into folder: URL) {
        let items = snippets(withIDs: dragIDs)
        dragIDs = []
        if !items.isEmpty { move(items, toFolder: folder) }
    }

    func isInLibrary(_ url: URL) -> Bool {
        Self.normalized(url).path.hasPrefix(root.path + "/")
    }

    /// Drops can deliver file reference URLs (file:///.file/id=...); turn them back into paths.
    nonisolated static func normalized(_ url: URL) -> URL {
        ((url as NSURL).filePathURL ?? url).standardizedFileURL
    }

    /// Handles drops onto a folder (or the root). Snippets and folders from the library are moved;
    /// files from elsewhere are imported as copies.
    @discardableResult
    func receiveDrop(of urls: [URL], into folder: URL) -> Bool {
        flushSaves()
        let folder = folder.standardizedFileURL
        let rootPrefix = root.path + "/"
        var snippetIDs = Set<String>()
        var didSomething = false

        for url in urls where url.isFileURL {
            let source = Self.normalized(url)
            if source.path.hasPrefix(rootPrefix) {
                if snippet(withID: source.path) != nil {
                    snippetIDs.formUnion(dragIDs.contains(source.path) ? dragIDs : [source.path])
                } else if isDirectory(source) {
                    didSomething = moveFolder(source, into: folder) || didSomething
                }
            } else {
                let target = uniqueURL(in: folder, name: source.lastPathComponent)
                do {
                    try fm.copyItem(at: source, to: target)
                    try? fm.setAttributes([.immutable: false], ofItemAtPath: target.path)
                    didSomething = true
                } catch {
                    report("Could not import \"\(source.lastPathComponent)\".", error)
                }
            }
        }
        dragIDs = []
        if !snippetIDs.isEmpty {
            didSomething = move(snippets(withIDs: snippetIDs), toFolder: folder) || didSomething
        } else {
            reload()
        }
        return didSomething
    }

    // MARK: - Folder operations

    func createFolder(in parent: URL? = nil) {
        let parent = parent ?? currentFolderURL
        let url = uniqueURL(in: parent, name: "New Folder", isDirectory: true)
        do {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            reload()
            sidebarSelection = .folder(url.standardizedFileURL.path)
            folderPendingRename = url.standardizedFileURL
        } catch {
            report("Could not create a folder.", error)
        }
    }

    func renameFolder(_ folder: URL, to newName: String) {
        let name = sanitized(newName)
        guard !name.isEmpty, name != folder.lastPathComponent else { return }
        let target = folder.deletingLastPathComponent().appendingPathComponent(name, isDirectory: true)
        if fm.fileExists(atPath: target.path) {
            errorMessage = "A folder named \"\(name)\" already exists there."
            return
        }
        relocateFolder(folder, to: target)
    }

    /// Nests `folder` inside `destination`. Refuses to move a folder into itself.
    @discardableResult
    func moveFolder(_ folder: URL, into destination: URL) -> Bool {
        let source = folder.standardizedFileURL
        let destination = destination.standardizedFileURL
        guard source.deletingLastPathComponent().path != destination.path else { return false }
        if destination.path == source.path || destination.path.hasPrefix(source.path + "/") {
            errorMessage = "A folder can't be moved inside itself."
            return false
        }
        return relocateFolder(source, to: uniqueURL(in: destination, name: source.lastPathComponent, isDirectory: true))
    }

    @discardableResult
    private func relocateFolder(_ folder: URL, to target: URL) -> Bool {
        flushSaves()
        let oldPath = folder.standardizedFileURL.path
        let newPath = target.standardizedFileURL.path
        do {
            try fm.moveItem(at: folder, to: target)
        } catch {
            report("Could not move the folder \"\(folder.lastPathComponent)\".", error)
            return false
        }
        // Carry selections and the new-snippet setting along to the folder's new location.
        // Reload first so the rebased paths exist when the selection is checked against the list.
        var newSidebar = sidebarSelection
        if case .folder(let path) = sidebarSelection, let moved = rebase(path, from: oldPath, to: newPath) {
            newSidebar = .folder(moved)
        }
        let newSelection = Set(selection.map { rebase($0, from: oldPath, to: newPath) ?? $0 })
        if newSnippetDestination.hasPrefix("folder:") {
            let old = root.appendingPathComponent(String(newSnippetDestination.dropFirst("folder:".count))).standardizedFileURL.path
            if let moved = rebase(old, from: oldPath, to: newPath) {
                newSnippetDestination = NewSnippetDestination.folder(relativeFolder(ofPath: moved))
            }
        }
        reload()
        sidebarSelection = newSidebar
        selection = newSelection.intersection(Set(snippets.map(\.id)))
        return true
    }

    func trashFolder(_ folder: URL) {
        let path = folder.path
        if snippets.contains(where: { $0.isLocked && $0.id.hasPrefix(path + "/") }) {
            errorMessage = "\"\(folder.lastPathComponent)\" contains locked snippets. Unlock them before moving the folder to the Trash."
            return
        }
        flushSaves()
        do {
            try fm.trashItem(at: folder, resultingItemURL: nil)
            reload()
        } catch {
            report("Could not move the folder to the Trash.", error)
        }
    }

    // MARK: - Library location

    /// Asks for a new library folder, then whether to bring the current snippets along.
    func chooseLibrary() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use as Library"
        panel.message = "Choose a folder for your snippet library."
        panel.directoryURL = root.deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let newRoot = url.standardizedFileURL
        guard newRoot.path != root.path else { return }

        var moveExisting = false
        if libraryHasContent {
            let alert = NSAlert()
            alert.messageText = "Move your snippets to the new library?"
            alert.informativeText = """
                Move Snippets: everything in "\(root.lastPathComponent)" (folders, snippets, and lock state) moves into "\(newRoot.lastPathComponent)".

                Don't Move: Snipbook opens "\(newRoot.lastPathComponent)" and leaves your current library where it is. You can switch back any time.
                """
            alert.addButton(withTitle: "Move Snippets")
            alert.addButton(withTitle: "Don't Move")
            alert.addButton(withTitle: "Cancel")
            switch alert.runModal() {
            case .alertFirstButtonReturn: moveExisting = true
            case .alertSecondButtonReturn: moveExisting = false
            default: return
            }
        }
        switchLibrary(to: newRoot, moveExisting: moveExisting)
    }

    private var libraryHasContent: Bool {
        let items = (try? fm.contentsOfDirectory(atPath: root.path)) ?? []
        return items.contains { $0 != ".DS_Store" }
    }

    func switchLibrary(to newRoot: URL, moveExisting: Bool) {
        let newRoot = newRoot.standardizedFileURL
        guard newRoot.path != root.path else { return }
        if moveExisting {
            if newRoot.path.hasPrefix(root.path + "/") || root.path.hasPrefix(newRoot.path + "/") {
                errorMessage = "The new library can't be inside the current one (or the other way around) when moving snippets."
                return
            }
            moveLibraryContents(to: newRoot)
        }
        root = newRoot
        defaults.set(newRoot.path, forKey: Keys.libraryPath)
        sidebarSelection = .all
        selection = []
        reload()
    }

    /// Moves every top-level item into `newRoot`. Locked files are unlocked for the move
    /// (macOS refuses to move them, especially across volumes) and locked again afterwards.
    private func moveLibraryContents(to newRoot: URL) {
        flushSaves()
        let oldRoot = root
        let lockedRelative = snippets.filter(\.isLocked).map { relativeFolder(ofPath: $0.id) }
        for rel in lockedRelative {
            try? fm.setAttributes([.immutable: false], ofItemAtPath: oldRoot.appendingPathComponent(rel).path)
        }

        var renamed: [String: String] = [:]
        var failed: [String] = []
        let items = (try? fm.contentsOfDirectory(at: oldRoot, includingPropertiesForKeys: nil)) ?? []
        for item in items where item.lastPathComponent != ".DS_Store" {
            let name = item.lastPathComponent
            let target = uniqueURL(in: newRoot, name: name, isDirectory: isDirectory(item))
            do {
                try fm.moveItem(at: item, to: target)
                renamed[name] = target.lastPathComponent
            } catch {
                failed.append(name)
            }
        }

        for rel in lockedRelative {
            var parts = rel.split(separator: "/").map(String.init)
            let path: String
            if let first = parts.first, let newFirst = renamed[first] {
                parts[0] = newFirst
                path = newRoot.appendingPathComponent(parts.joined(separator: "/")).path
            } else {
                path = oldRoot.appendingPathComponent(rel).path
            }
            try? fm.setAttributes([.immutable: true], ofItemAtPath: path)
        }

        if !failed.isEmpty {
            errorMessage = "Some items could not be moved and were left in \"\(oldRoot.path)\": \(failed.joined(separator: ", "))."
        }
    }

    // MARK: - Helpers

    /// `name` inside `dir`, numbered ("Name 2.rb") if that name is taken.
    private func uniqueURL(in dir: URL, name: String, isDirectory: Bool = false) -> URL {
        let ext = isDirectory ? "" : (name as NSString).pathExtension
        let base = ext.isEmpty ? name : (name as NSString).deletingPathExtension
        func make(_ stem: String) -> URL {
            dir.appendingPathComponent(ext.isEmpty ? stem : "\(stem).\(ext)", isDirectory: isDirectory)
        }
        var candidate = make(base)
        var n = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = make("\(base) \(n)")
            n += 1
        }
        return candidate
    }

    /// Rewrites `path` if it is `old` or inside it.
    private func rebase(_ path: String, from old: String, to new: String) -> String? {
        if path == old { return new }
        if path.hasPrefix(old + "/") { return new + path.dropFirst(old.count) }
        return nil
    }

    private func sanitized(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func report(_ message: String, _ error: Error) {
        errorMessage = "\(message)\n\n\(error.localizedDescription)"
    }
}
