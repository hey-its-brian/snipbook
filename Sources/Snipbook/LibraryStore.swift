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

/// Owns the on-disk library. Folders are real directories, snippets are real files,
/// and "locked" is the Finder Locked flag (uchg), so the lock is enforced by macOS itself.
@MainActor
@Observable
final class LibraryStore {
    static let defaultRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Snippets", isDirectory: true)

    private(set) var root: URL
    private(set) var folders: [FolderNode] = []
    private(set) var snippets: [Snippet] = []

    var sidebarSelection: SidebarItem? = .all
    var selectedSnippetID: String?
    var searchText = ""
    var errorMessage: String?
    var folderPendingRename: URL?
    var lastLanguage: Language = .all[0]

    @ObservationIgnored private var dirty = Set<String>()
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private let fm = FileManager.default

    private static let maxFileSize = 1_000_000
    private static let libraryPathKey = "libraryPath"

    init() {
        if let saved = UserDefaults.standard.string(forKey: Self.libraryPathKey) {
            root = URL(fileURLWithPath: saved, isDirectory: true)
        } else {
            root = Self.defaultRoot
        }
        if !fm.fileExists(atPath: root.path) {
            SeedLibrary.install(at: root)
        }
        reload()
    }

    // MARK: - Derived state

    var selectedSnippet: Snippet? {
        guard let id = selectedSnippetID else { return nil }
        return snippets.first { $0.id == id }
    }

    var lockedCount: Int { snippets.filter(\.isLocked).count }

    var visibleSnippets: [Snippet] {
        var list: [Snippet]
        switch sidebarSelection {
        case .locked: list = snippets.filter(\.isLocked)
        case .folder(let path): list = snippets.filter { $0.folderPath == path }
        case .all, .none: list = snippets
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

    /// Where "New Snippet" and "New Folder" land.
    var currentFolderURL: URL {
        if case .folder(let path) = sidebarSelection { return URL(fileURLWithPath: path, isDirectory: true) }
        return root
    }

    /// Folder path relative to the library root, for display in list rows.
    func relativeFolder(of snippet: Snippet) -> String {
        relativeFolder(ofPath: snippet.folderPath)
    }

    func relativeFolder(ofPath path: String) -> String {
        let rootPath = root.standardizedFileURL.path
        guard path.hasPrefix(rootPath) else { return path }
        return String(path.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
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

        if let id = selectedSnippetID, !snippets.contains(where: { $0.id == id }) {
            selectedSnippetID = nil
        }
        if case .folder(let path) = sidebarSelection, !fm.fileExists(atPath: path) {
            sidebarSelection = .all
        }
    }

    private func loadFolders(in dir: URL) -> [FolderNode] {
        let items = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey],
                                                 options: [.skipsHiddenFiles])) ?? []
        return items
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
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
            guard let snippet = snippets.first(where: { $0.id == id }), !snippet.isLocked else { continue }
            do {
                try snippet.content.write(to: snippet.url, atomically: true, encoding: .utf8)
            } catch {
                report("Could not save \"\(snippet.title)\".", error)
            }
        }
        dirty.removeAll()
    }

    // MARK: - Snippet operations

    func createSnippet(language: Language) {
        flushSaves()
        lastLanguage = language
        let url = uniqueURL(in: currentFolderURL, base: "Untitled", ext: language.ext)
        do {
            try "".write(to: url, atomically: true, encoding: .utf8)
            reload()
            selectedSnippetID = url.standardizedFileURL.path
        } catch {
            report("Could not create a snippet.", error)
        }
    }

    func rename(_ snippet: Snippet, to newTitle: String) {
        let title = sanitized(newTitle)
        guard !title.isEmpty, title != snippet.title else { return }
        let target = snippet.url.deletingLastPathComponent()
            .appendingPathComponent(title).appendingPathExtension(snippet.url.pathExtension)
        moveSnippet(snippet, to: target)
    }

    func setLanguage(_ language: Language, for snippet: Snippet) {
        guard language != snippet.language else { return }
        lastLanguage = language
        let target = snippet.url.deletingPathExtension().appendingPathExtension(language.ext)
        moveSnippet(snippet, to: target)
    }

    func move(_ snippet: Snippet, toFolder folder: URL) {
        guard snippet.folderPath != folder.standardizedFileURL.path else { return }
        moveSnippet(snippet, to: folder.appendingPathComponent(snippet.url.lastPathComponent))
    }

    private func moveSnippet(_ snippet: Snippet, to target: URL) {
        guard !snippet.isLocked else {
            errorMessage = "\"\(snippet.title)\" is locked. Unlock it before renaming, moving, or changing its language."
            return
        }
        flushSaves()
        if fm.fileExists(atPath: target.path) {
            errorMessage = "A snippet named \"\(target.lastPathComponent)\" already exists there."
            return
        }
        do {
            try fm.moveItem(at: snippet.url, to: target)
            let wasSelected = selectedSnippetID == snippet.id
            reload()
            if wasSelected { selectedSnippetID = target.standardizedFileURL.path }
        } catch {
            report("Could not move \"\(snippet.title)\".", error)
        }
    }

    func setLocked(_ locked: Bool, for snippet: Snippet) {
        flushSaves()
        do {
            try fm.setAttributes([.immutable: locked], ofItemAtPath: snippet.url.path)
            if let index = snippets.firstIndex(where: { $0.id == snippet.id }) {
                snippets[index].isLocked = isLocked(snippet.url)
            }
        } catch {
            report("Could not change the lock on \"\(snippet.title)\".", error)
        }
    }

    func toggleLock(_ snippet: Snippet) { setLocked(!snippet.isLocked, for: snippet) }

    func duplicate(_ snippet: Snippet) {
        flushSaves()
        let target = uniqueURL(in: snippet.url.deletingLastPathComponent(),
                               base: "\(snippet.title) copy", ext: snippet.url.pathExtension)
        do {
            try snippet.content.write(to: target, atomically: true, encoding: .utf8)
            reload()
            selectedSnippetID = target.standardizedFileURL.path
        } catch {
            report("Could not duplicate \"\(snippet.title)\".", error)
        }
    }

    func trash(_ snippet: Snippet) {
        guard !snippet.isLocked else {
            errorMessage = "\"\(snippet.title)\" is locked. Unlock it before moving it to the Trash."
            return
        }
        flushSaves()
        do {
            try fm.trashItem(at: snippet.url, resultingItemURL: nil)
            reload()
        } catch {
            report("Could not move \"\(snippet.title)\" to the Trash.", error)
        }
    }

    func copyToPasteboard(_ snippet: Snippet) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(snippet.content, forType: .string)
    }

    /// Handles drops onto a folder: library files are moved, files from elsewhere are imported as copies.
    func receiveDrop(of urls: [URL], into folder: URL) -> Bool {
        flushSaves()
        let rootPath = root.path
        var didSomething = false
        for url in urls where url.isFileURL {
            let source = url.standardizedFileURL
            if source.path.hasPrefix(rootPath + "/") {
                if let snippet = snippets.first(where: { $0.id == source.path }) {
                    move(snippet, toFolder: folder)
                    didSomething = true
                }
            } else {
                let target = uniqueURL(in: folder, base: source.deletingPathExtension().lastPathComponent,
                                       ext: source.pathExtension)
                do {
                    try fm.copyItem(at: source, to: target)
                    try? fm.setAttributes([.immutable: false], ofItemAtPath: target.path)
                    didSomething = true
                } catch {
                    report("Could not import \"\(source.lastPathComponent)\".", error)
                }
            }
        }
        reload()
        return didSomething
    }

    // MARK: - Folder operations

    func createFolder(in parent: URL? = nil) {
        let parent = parent ?? currentFolderURL
        let url = uniqueURL(in: parent, base: "New Folder", ext: "")
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
        flushSaves()
        let target = folder.deletingLastPathComponent().appendingPathComponent(name, isDirectory: true)
        if fm.fileExists(atPath: target.path) {
            errorMessage = "A folder named \"\(name)\" already exists there."
            return
        }
        do {
            try fm.moveItem(at: folder, to: target)
            let oldPath = folder.path
            reload()
            if case .folder(let path) = sidebarSelection, path == oldPath {
                sidebarSelection = .folder(target.standardizedFileURL.path)
            }
        } catch {
            report("Could not rename the folder.", error)
        }
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

    func chooseLibrary() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use as Library"
        panel.directoryURL = root
        guard panel.runModal() == .OK, let url = panel.url else { return }
        flushSaves()
        root = url
        UserDefaults.standard.set(url.path, forKey: Self.libraryPathKey)
        sidebarSelection = .all
        selectedSnippetID = nil
        reload()
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Helpers

    private func uniqueURL(in dir: URL, base: String, ext: String) -> URL {
        func make(_ name: String) -> URL {
            let url = dir.appendingPathComponent(name, isDirectory: ext.isEmpty)
            return ext.isEmpty ? url : url.appendingPathExtension(ext)
        }
        var candidate = make(base)
        var n = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = make("\(base) \(n)")
            n += 1
        }
        return candidate
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
