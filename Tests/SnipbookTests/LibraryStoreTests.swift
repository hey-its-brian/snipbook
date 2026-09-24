import XCTest
@testable import Snipbook

@MainActor
final class LibraryStoreTests: XCTestCase {
    private var temp: URL!
    private var root: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private let fm = FileManager.default

    override func setUp() async throws {
        temp = fm.temporaryDirectory.appendingPathComponent("snipbook-tests-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL
        root = temp.appendingPathComponent("Library", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        suiteName = "snipbook-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        // Locked files can't be deleted, so unlock everything first.
        if let walker = fm.enumerator(at: temp, includingPropertiesForKeys: nil) {
            for case let url as URL in walker.allObjects {
                try? fm.setAttributes([.immutable: false], ofItemAtPath: url.path)
            }
        }
        try? fm.removeItem(at: temp)
        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: Helpers

    @discardableResult
    private func write(_ relative: String, _ content: String = "code", in base: URL? = nil) throws -> URL {
        let url = (base ?? root).appendingPathComponent(relative)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func lock(_ url: URL) throws {
        try fm.setAttributes([.immutable: true], ofItemAtPath: url.path)
    }

    private func isLocked(_ url: URL) -> Bool {
        (try? fm.attributesOfItem(atPath: url.path)[.immutable] as? Bool) ?? false
    }

    private func path(_ relative: String) -> String {
        root.appendingPathComponent(relative).standardizedFileURL.path
    }

    private func makeStore() -> LibraryStore {
        LibraryStore(root: root, defaults: defaults)
    }

    // MARK: Counts and listing

    func testFolderCountsIncludeSubfolders() throws {
        try write("A/x.rb")
        try write("A/B/y.rb")
        try write("A/B/C/z.sh")
        try write("D/w.sql")
        try write("top.js")
        let store = makeStore()

        XCTAssertEqual(store.folderCounts[path("A")], 3)
        XCTAssertEqual(store.folderCounts[path("A/B")], 2)
        XCTAssertEqual(store.folderCounts[path("A/B/C")], 1)
        XCTAssertEqual(store.folderCounts[path("D")], 1)
        XCTAssertEqual(store.snippets.count, 5)
    }

    func testFolderListingRespectsSubfolderSetting() throws {
        try write("A/x.rb")
        try write("A/B/y.rb")
        let store = makeStore()
        store.sidebarSelection = .folder(path("A"))

        XCTAssertEqual(Set(store.visibleSnippets.map(\.title)), ["x", "y"])
        XCTAssertEqual(store.folderLabel(for: store.visibleSnippets.first { $0.title == "y" }!), "B")

        store.includeSubfolders = false
        XCTAssertEqual(store.visibleSnippets.map(\.title), ["x"])
    }

    // MARK: Dragging snippets

    func testDraggingASelectedRowMovesTheWholeSelection() throws {
        let x = try write("A/x.rb")
        let y = try write("A/y.rb")
        try write("A/z.rb")
        try fm.createDirectory(at: root.appendingPathComponent("D"), withIntermediateDirectories: true)
        let store = makeStore()
        store.selection = [path("A/x.rb"), path("A/y.rb")]

        let payload = store.beginDrag(store.snippet(withID: path("A/x.rb"))!)
        XCTAssertTrue(store.receiveDrop(of: [payload], into: root.appendingPathComponent("D")))

        XCTAssertFalse(fm.fileExists(atPath: x.path))
        XCTAssertFalse(fm.fileExists(atPath: y.path))
        XCTAssertTrue(fm.fileExists(atPath: path("D/x.rb")))
        XCTAssertTrue(fm.fileExists(atPath: path("D/y.rb")))
        XCTAssertTrue(fm.fileExists(atPath: path("A/z.rb")))
        XCTAssertEqual(store.selection, [path("D/x.rb"), path("D/y.rb")])
    }

    func testMovingSelectedSnippetsOutOfTheViewedFolderDeselectsThem() throws {
        try write("A/x.rb")
        try write("A/y.rb")
        try fm.createDirectory(at: root.appendingPathComponent("D"), withIntermediateDirectories: true)
        let store = makeStore()
        store.sidebarSelection = .folder(path("A"))
        store.selection = [path("A/x.rb"), path("A/y.rb")]

        store.move(store.selectedSnippets, toFolder: root.appendingPathComponent("D"))

        XCTAssertTrue(store.selection.isEmpty, "moved rows are no longer in the list, so nothing stays selected")
    }

    func testDraggingAnUnselectedRowMovesOnlyThatRow() throws {
        try write("A/x.rb")
        try write("A/y.rb")
        try fm.createDirectory(at: root.appendingPathComponent("D"), withIntermediateDirectories: true)
        let store = makeStore()
        store.selection = [path("A/x.rb")]

        let payload = store.beginDrag(store.snippet(withID: path("A/y.rb"))!)
        store.receiveDrop(of: [payload], into: root.appendingPathComponent("D"))

        XCTAssertTrue(fm.fileExists(atPath: path("A/x.rb")))
        XCTAssertTrue(fm.fileExists(atPath: path("D/y.rb")))
    }

    func testMoveRenamesOnClashInsteadOfOverwriting() throws {
        try write("A/x.rb", "from A")
        try write("D/x.rb", "from D")
        let store = makeStore()

        store.move([store.snippet(withID: path("A/x.rb"))!], toFolder: root.appendingPathComponent("D"))

        XCTAssertEqual(try String(contentsOfFile: path("D/x.rb"), encoding: .utf8), "from D")
        XCTAssertEqual(try String(contentsOfFile: path("D/x 2.rb"), encoding: .utf8), "from A")
    }

    func testLockedSnippetsStayPutWhenMoved() throws {
        let locked = try write("A/locked.rb")
        try write("A/free.rb")
        try lock(locked)
        try fm.createDirectory(at: root.appendingPathComponent("D"), withIntermediateDirectories: true)
        let store = makeStore()

        store.move(store.snippets, toFolder: root.appendingPathComponent("D"))

        XCTAssertTrue(fm.fileExists(atPath: locked.path))
        XCTAssertTrue(fm.fileExists(atPath: path("D/free.rb")))
        XCTAssertNotNil(store.errorMessage)
    }

    func testDroppingAFinderFileImportsACopy() throws {
        let outside = try write("outside.sh", "echo hi", in: temp)
        let store = makeStore()

        store.receiveDrop(of: [outside], into: root)

        XCTAssertTrue(fm.fileExists(atPath: outside.path), "original must be left alone")
        XCTAssertTrue(fm.fileExists(atPath: path("outside.sh")))
    }

    // MARK: Dragging folders

    func testDroppingAFolderOnAnotherNestsIt() throws {
        try write("A/B/y.rb")
        try fm.createDirectory(at: root.appendingPathComponent("D"), withIntermediateDirectories: true)
        let store = makeStore()
        store.sidebarSelection = .folder(path("A/B"))
        store.selection = [path("A/B/y.rb")]
        store.newSnippetDestination = NewSnippetDestination.folder("A/B")

        let folder = store.allFoldersFlat.first { $0.id == path("A/B") }!
        XCTAssertTrue(store.receiveDrop(of: [store.beginDrag(folder: folder)], into: root.appendingPathComponent("D")))

        XCTAssertTrue(fm.fileExists(atPath: path("D/B/y.rb")))
        XCTAssertEqual(store.folderCounts[path("D")], 1)
        XCTAssertNil(store.folderCounts[path("A")])
        XCTAssertEqual(store.sidebarSelection, .folder(path("D/B")))
        XCTAssertEqual(store.selection, [path("D/B/y.rb")])
        XCTAssertEqual(store.newSnippetDestination, NewSnippetDestination.folder("D/B"))
    }

    func testFolderCannotMoveIntoItself() throws {
        try write("A/B/y.rb")
        let store = makeStore()

        XCTAssertFalse(store.moveFolder(root.appendingPathComponent("A"), into: root.appendingPathComponent("A/B")))
        XCTAssertTrue(fm.fileExists(atPath: path("A/B/y.rb")))
        XCTAssertNotNil(store.errorMessage)
    }

    func testDroppingAFolderOnTheRootUnnestsIt() throws {
        try write("A/B/y.rb")
        let store = makeStore()

        store.moveFolder(root.appendingPathComponent("A/B"), into: root)

        XCTAssertTrue(fm.fileExists(atPath: path("B/y.rb")))
    }

    func testMovingAFolderKeepsLockedFilesLocked() throws {
        let locked = try write("A/B/locked.rb")
        try lock(locked)
        let store = makeStore()

        XCTAssertTrue(store.moveFolder(root.appendingPathComponent("A/B"), into: root))
        XCTAssertTrue(isLocked(URL(fileURLWithPath: path("B/locked.rb"))))
    }

    // MARK: Multi-select actions

    func testBulkLockAndUnlock() throws {
        try write("a.rb")
        try write("b.rb")
        let store = makeStore()

        store.toggleLock(store.snippets)
        XCTAssertTrue(store.snippets.allSatisfy(\.isLocked))
        XCTAssertTrue(isLocked(URL(fileURLWithPath: path("a.rb"))))

        store.toggleLock(store.snippets)
        XCTAssertFalse(store.snippets.contains(where: \.isLocked))
    }

    func testToggleLockOnAMixedSelectionLocksEverything() throws {
        let a = try write("a.rb")
        try write("b.rb")
        try lock(a)
        let store = makeStore()

        store.toggleLock(store.snippets)
        XCTAssertTrue(store.snippets.allSatisfy(\.isLocked))
    }

    // MARK: New snippet destination

    func testNewSnippetsGoToTheConfiguredFolder() throws {
        try fm.createDirectory(at: root.appendingPathComponent("Inbox"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("Other"), withIntermediateDirectories: true)
        let store = makeStore()
        store.sidebarSelection = .folder(path("Other"))

        store.newSnippetDestination = NewSnippetDestination.folder("Inbox")
        store.createSnippet(language: Language.forExtension("rb"))
        XCTAssertTrue(fm.fileExists(atPath: path("Inbox/Untitled.rb")))
        XCTAssertEqual(store.sidebarSelection, .folder(path("Inbox")), "switches to where the snippet went")

        store.newSnippetDestination = NewSnippetDestination.root
        store.createSnippet(language: Language.forExtension("sh"))
        XCTAssertTrue(fm.fileExists(atPath: path("Untitled.sh")))

        store.newSnippetDestination = NewSnippetDestination.selected
        store.sidebarSelection = .folder(path("Other"))
        store.createSnippet(language: Language.forExtension("sql"))
        XCTAssertTrue(fm.fileExists(atPath: path("Other/Untitled.sql")))
    }

    func testMissingDestinationFallsBackToSelectedFolder() throws {
        try fm.createDirectory(at: root.appendingPathComponent("Other"), withIntermediateDirectories: true)
        let store = makeStore()
        store.newSnippetDestination = NewSnippetDestination.folder("Gone")
        store.sidebarSelection = .folder(path("Other"))

        XCTAssertEqual(store.newSnippetFolderURL.path, path("Other"))
    }

    // MARK: Switching libraries

    func testSwitchingWithMoveBringsEverythingAndKeepsLocks() throws {
        let locked = try write("Bash/locked.sh")
        try lock(locked)
        try write("Ruby/Rails/model.rb")
        try write("top.sql")
        try write(".git/HEAD", "ref: main")
        let newRoot = temp.appendingPathComponent("NewLibrary", isDirectory: true)
        try fm.createDirectory(at: newRoot, withIntermediateDirectories: true)
        try write("Bash/existing.sh", in: newRoot)
        let store = makeStore()

        store.switchLibrary(to: newRoot, moveExisting: true)

        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.root.path, newRoot.standardizedFileURL.path)
        // "Bash" already existed in the destination, so the moved one is numbered.
        let movedLocked = newRoot.appendingPathComponent("Bash 2/locked.sh")
        XCTAssertTrue(fm.fileExists(atPath: movedLocked.path))
        XCTAssertTrue(isLocked(movedLocked))
        XCTAssertTrue(fm.fileExists(atPath: newRoot.appendingPathComponent("Ruby/Rails/model.rb").path))
        XCTAssertTrue(fm.fileExists(atPath: newRoot.appendingPathComponent("top.sql").path))
        XCTAssertTrue(fm.fileExists(atPath: newRoot.appendingPathComponent(".git/HEAD").path))
        XCTAssertEqual((try fm.contentsOfDirectory(atPath: root.path)).filter { $0 != ".DS_Store" }, [])
        XCTAssertEqual(store.snippets.count, 4)
        XCTAssertEqual(defaults.string(forKey: "libraryPath"), newRoot.standardizedFileURL.path)
    }

    func testSwitchingWithoutMoveLeavesTheOldLibrary() throws {
        try write("keep.rb")
        let newRoot = temp.appendingPathComponent("Empty", isDirectory: true)
        try fm.createDirectory(at: newRoot, withIntermediateDirectories: true)
        let store = makeStore()

        store.switchLibrary(to: newRoot, moveExisting: false)

        XCTAssertTrue(fm.fileExists(atPath: path("keep.rb")))
        XCTAssertEqual(store.snippets.count, 0)
    }

    func testCannotMoveLibraryIntoItself() throws {
        try write("keep.rb")
        let store = makeStore()

        store.switchLibrary(to: root.appendingPathComponent("Nested"), moveExisting: true)

        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(store.root.path, root.path)
        XCTAssertTrue(fm.fileExists(atPath: path("keep.rb")))
    }

    // MARK: Tags

    private func tags(of relative: String) -> [String] {
        (try? URL(fileURLWithPath: path(relative)).resourceValues(forKeys: [.tagNamesKey]))?.tagNames ?? []
    }

    func testTagsAreFinderTagsAndCounted() throws {
        try write("a.rb")
        try write("b.rb")
        let store = makeStore()

        store.addTag("#rails ", to: store.snippets)
        store.addTag("Snippets", to: [store.snippet(withID: path("a.rb"))!])

        XCTAssertEqual(tags(of: "a.rb").sorted(), ["Snippets", "rails"])
        XCTAssertEqual(store.tagCounts, ["rails": 2, "Snippets": 1])
        store.sidebarSelection = .tag("Snippets")
        XCTAssertEqual(store.visibleSnippets.map(\.title), ["a"])
    }

    func testAddingATagReusesExistingCasing() throws {
        try write("a.rb")
        try write("b.rb")
        let store = makeStore()
        store.addTag("Rails", to: [store.snippet(withID: path("a.rb"))!])

        store.addTag("rails", to: [store.snippet(withID: path("b.rb"))!])

        XCTAssertEqual(store.allTags, ["Rails"])
    }

    func testTaggingALockedSnippetKeepsItLocked() throws {
        let locked = try write("locked.rb")
        try lock(locked)
        let store = makeStore()

        store.addTag("keep", to: store.snippets)

        XCTAssertEqual(tags(of: "locked.rb"), ["keep"])
        XCTAssertTrue(isLocked(locked))
        XCTAssertNil(store.errorMessage)
    }

    func testSavingContentKeepsTags() throws {
        try write("a.rb", "old")
        let store = makeStore()
        store.addTag("keep", to: store.snippets)

        store.updateContent(of: path("a.rb"), to: "new")
        store.flushSaves()

        XCTAssertEqual(try String(contentsOfFile: path("a.rb"), encoding: .utf8), "new")
        XCTAssertEqual(tags(of: "a.rb"), ["keep"])
    }

    func testMovingAndDuplicatingKeepTags() throws {
        try write("A/a.rb")
        try fm.createDirectory(at: root.appendingPathComponent("D"), withIntermediateDirectories: true)
        let store = makeStore()
        store.addTag("keep", to: store.snippets)

        store.move(store.snippets, toFolder: root.appendingPathComponent("D"))
        store.duplicate(store.snippets)

        XCTAssertEqual(tags(of: "D/a.rb"), ["keep"])
        XCTAssertEqual(tags(of: "D/a copy.rb"), ["keep"])
    }

    func testRenameTagMergesAndDeleteRemovesEverywhere() throws {
        try write("a.rb")
        try write("b.rb")
        let store = makeStore()
        store.addTag("js", to: [store.snippet(withID: path("a.rb"))!])
        store.addTag("javascript", to: store.snippets)

        store.renameTag("js", to: "javascript")
        XCTAssertEqual(tags(of: "a.rb"), ["javascript"], "merged without a duplicate")
        XCTAssertEqual(store.tagCounts, ["javascript": 2])

        store.deleteTag("javascript")
        XCTAssertTrue(store.allTags.isEmpty)
        XCTAssertEqual(tags(of: "b.rb"), [])
    }

    func testNewSnippetInTagViewGetsTheTag() throws {
        try write("a.rb")
        let store = makeStore()
        store.addTag("inbox", to: store.snippets)
        store.sidebarSelection = .tag("inbox")

        store.createSnippet(language: Language.forExtension("sh"))

        XCTAssertEqual(tags(of: "Untitled.sh"), ["inbox"])
        XCTAssertEqual(store.sidebarSelection, .tag("inbox"))
        XCTAssertEqual(store.visibleSnippets.count, 2)
    }

    func testDroppingSnippetsOnATagTagsTheWholeSelection() throws {
        try write("a.rb")
        try write("b.rb")
        try write("c.rb")
        let store = makeStore()
        store.selection = [path("a.rb"), path("b.rb")]

        _ = store.dragItem(for: store.snippet(withID: path("a.rb"))!)
        store.receiveTagDrop(of: [], tag: "picked")

        XCTAssertEqual(store.tagCounts["picked"], 2)
        XCTAssertEqual(tags(of: "c.rb"), [])
    }

    func testSearchMatchesTags() throws {
        try write("a.rb")
        try write("b.rb")
        let store = makeStore()
        store.addTag("deploy", to: [store.snippet(withID: path("b.rb"))!])

        store.searchText = "#deploy"
        XCTAssertEqual(store.visibleSnippets.map(\.title), ["b"])
    }

    // MARK: Quick Search

    func testQuickSearchRanksTitleMatchesFirst() throws {
        try write("zeta.sh", "grep something")
        try write("grep tricks.sh", "rg")
        try write("alpha grep.sh", "x")
        let store = makeStore()

        let titles = QuickSearchModel.results(in: store, query: "grep").map(\.title)

        XCTAssertEqual(titles, ["grep tricks", "alpha grep", "zeta"])
    }
}
