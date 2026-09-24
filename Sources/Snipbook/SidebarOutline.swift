import AppKit
import SwiftUI

/// The sidebar, built on NSOutlineView. SwiftUI's drag modifiers on List rows swallow the clicks that
/// select a row and never deliver drops onto rows, so AppKit handles selection and drag and drop here.
struct SidebarOutline: NSViewRepresentable {
    let store: LibraryStore

    func makeCoordinator() -> Coordinator { Coordinator(store: store) }

    func makeNSView(context: Context) -> NSScrollView {
        let outline = NSOutlineView()
        outline.style = .sourceList
        outline.headerView = nil
        outline.floatsGroupRows = false
        outline.allowsMultipleSelection = false
        outline.allowsEmptySelection = true
        outline.autoresizesOutlineColumn = false
        outline.indentationPerLevel = 14

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

        outline.dataSource = context.coordinator
        outline.delegate = context.coordinator
        outline.registerForDraggedTypes([.fileURL])
        outline.setDraggingSourceOperationMask(.move, forLocal: true)
        outline.setDraggingSourceOperationMask(.copy, forLocal: false)
        outline.draggingDestinationFeedbackStyle = .sourceList

        let menu = NSMenu()
        menu.delegate = context.coordinator
        outline.menu = menu

        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false

        context.coordinator.outline = outline
        context.coordinator.refresh()
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        // Reading these here makes SwiftUI call updateNSView again when they change.
        let snapshot = Coordinator.Snapshot(
            folders: store.folders,
            counts: store.folderCounts,
            total: store.snippets.count,
            locked: store.lockedCount
        )
        _ = store.sidebarSelection
        context.coordinator.refresh(snapshot)
    }

    // MARK: - Nodes

    final class Node: NSObject {
        enum Kind: Equatable {
            case header(String)
            case all
            case locked
            case folder(FolderNode)
        }

        let kind: Kind
        var children: [Node] = []

        init(_ kind: Kind, children: [Node] = []) {
            self.kind = kind
            self.children = children
        }

        var sidebarItem: SidebarItem? {
            switch kind {
            case .all: .all
            case .locked: .locked
            case .folder(let folder): .folder(folder.id)
            case .header: nil
            }
        }

        var folderURL: URL? {
            if case .folder(let folder) = kind { return folder.url }
            return nil
        }
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
        struct Snapshot: Equatable {
            var folders: [FolderNode]
            var counts: [String: Int]
            var total: Int
            var locked: Int
        }

        let store: LibraryStore
        weak var outline: NSOutlineView?
        private var roots: [Node] = []
        private var allNode: Node!
        private var lastSnapshot: Snapshot?
        /// Folder paths the user has expanded, restored after each reload.
        private var expanded = Set<String>()
        private var isSyncingSelection = false

        init(store: LibraryStore) { self.store = store }

        func refresh(_ snapshot: Snapshot? = nil) {
            guard let outline else { return }
            let snapshot = snapshot ?? Snapshot(folders: store.folders, counts: store.folderCounts,
                                                total: store.snippets.count, locked: store.lockedCount)
            if snapshot != lastSnapshot {
                lastSnapshot = snapshot
                rebuild()
                outline.reloadData()
                for root in roots { outline.expandItem(root) }
                restoreExpansion(roots)
            }
            syncSelection()
        }

        private func rebuild() {
            func folderNodes(_ folders: [FolderNode]) -> [Node] {
                folders.map { Node(.folder($0), children: folderNodes($0.children ?? [])) }
            }
            allNode = Node(.all)
            roots = [
                Node(.header("Library"), children: [allNode, Node(.locked)]),
                Node(.header("Folders"), children: folderNodes(store.folders)),
            ]
        }

        private func restoreExpansion(_ nodes: [Node]) {
            guard let outline else { return }
            for node in nodes {
                if case .folder(let folder) = node.kind, expanded.contains(folder.id) {
                    outline.expandItem(node)
                }
                restoreExpansion(node.children)
            }
        }

        /// Selects the row matching the store, expanding its parents so it is visible.
        private func syncSelection() {
            guard let outline else { return }
            let target = store.sidebarSelection
            let current = outline.selectedRow >= 0 ? (outline.item(atRow: outline.selectedRow) as? Node)?.sidebarItem : nil
            guard current != target else { return }
            isSyncingSelection = true
            defer { isSyncingSelection = false }
            guard let target, let path = findPath(to: target, in: roots) else {
                outline.deselectAll(nil)
                return
            }
            for ancestor in path.dropLast() { outline.expandItem(ancestor) }
            let row = outline.row(forItem: path.last)
            if row >= 0 {
                outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                outline.scrollRowToVisible(row)
            }
        }

        private func findPath(to item: SidebarItem, in nodes: [Node]) -> [Node]? {
            for node in nodes {
                if node.sidebarItem == item { return [node] }
                if let rest = findPath(to: item, in: node.children) { return [node] + rest }
            }
            return nil
        }

        private func node(_ item: Any?) -> Node? { item as? Node }

        // MARK: Data source

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            node(item)?.children.count ?? roots.count
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            node(item)?.children[index] ?? roots[index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            !(node(item)?.children.isEmpty ?? true)
        }

        // MARK: Delegate

        // Headers are plain rows rather than group rows: source lists draw group-row text almost invisibly faint.
        func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool { false }

        func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
            if case .header = node(item)?.kind { return 26 }
            return 24
        }

        func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
            node(item)?.sidebarItem != nil
        }

        func outlineView(_ outlineView: NSOutlineView, shouldShowOutlineCellForItem item: Any) -> Bool {
            if case .header = node(item)?.kind { return false }
            return true
        }

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let node = node(item) else { return nil }
            if case .header(let title) = node.kind {
                let id = NSUserInterfaceItemIdentifier("header")
                let cell = outlineView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView ?? HeaderCell(id: id)
                cell.textField?.stringValue = title
                return cell
            }
            let id = NSUserInterfaceItemIdentifier("row")
            let cell = outlineView.makeView(withIdentifier: id, owner: nil) as? RowCell ?? RowCell(id: id)
            switch node.kind {
            case .all:
                cell.configure(title: "All Snippets", symbol: "tray.full", count: store.snippets.count)
            case .locked:
                cell.configure(title: "Locked", symbol: "lock", count: store.lockedCount)
            case .folder(let folder):
                cell.configure(title: folder.name, symbol: "folder", count: store.folderCounts[folder.id] ?? 0)
            case .header:
                break
            }
            return cell
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !isSyncingSelection, let outline else { return }
            let item = outline.selectedRow >= 0 ? node(outline.item(atRow: outline.selectedRow))?.sidebarItem : nil
            if let item, item != store.sidebarSelection {
                store.sidebarSelection = item
            }
        }

        func outlineViewItemDidExpand(_ notification: Notification) {
            if let url = node(notification.userInfo?["NSObject"])?.folderURL { expanded.insert(url.path) }
        }

        func outlineViewItemDidCollapse(_ notification: Notification) {
            if let url = node(notification.userInfo?["NSObject"])?.folderURL { expanded.remove(url.path) }
        }

        // MARK: Drag source (folders)

        func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
            guard let url = node(item)?.folderURL else { return nil }
            store.noteDragStarted(folder: url)
            return url as NSURL
        }

        // MARK: Drop target

        func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo,
                         proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
            // Dropping between rows retargets onto the folder being hovered.
            let target = node(item)
            if index != NSOutlineViewDropOnItemIndex {
                if case .folder = target?.kind {
                    outlineView.setDropItem(target, dropChildIndex: NSOutlineViewDropOnItemIndex)
                } else {
                    return []
                }
            }
            guard let destination = destinationURL(for: target) else { return [] }

            // Drags from inside Snipbook (sidebar folders, snippet rows) are moves. The snippet list
            // hands over its URLs lazily, so they may not be readable yet; that's fine for internal drags.
            if info.draggingSource != nil {
                let urls = fileURLs(from: info)
                let intoItself = urls.contains { url in
                    destination.path == url.path || destination.path.hasPrefix(url.path + "/")
                }
                return intoItself ? [] : .move
            }
            // Files from Finder are imported as copies.
            return fileURLs(from: info).isEmpty ? [] : .copy
        }

        func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo,
                         item: Any?, childIndex index: Int) -> Bool {
            guard let destination = destinationURL(for: node(item)) else { return false }
            let urls = fileURLs(from: info)
            let isInternal = info.draggingSource != nil
            // Defer so the drag session finishes before any alert appears.
            DispatchQueue.main.async { [store] in
                if urls.isEmpty, isInternal {
                    store.dropPendingDrag(into: destination)
                } else {
                    store.receiveDrop(of: urls, into: destination)
                }
            }
            return !urls.isEmpty || isInternal
        }

        private func destinationURL(for node: Node?) -> URL? {
            switch node?.kind {
            case .folder(let folder): folder.url
            case .all: store.root
            default: nil
            }
        }

        private func fileURLs(from info: NSDraggingInfo) -> [URL] {
            let objects = info.draggingPasteboard.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]
            ) as? [URL] ?? []
            // SwiftUI's list provides its URL lazily: until then the pasteboard yields an empty URL.
            return objects.filter { !$0.path.isEmpty }.map(LibraryStore.normalized)
        }

        // MARK: Context menu

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let outline else { return }
            let clicked = outline.clickedRow >= 0 ? node(outline.item(atRow: outline.clickedRow)) : nil
            if let url = clicked?.folderURL {
                menu.addItem(action("New Snippet Here") { [store] in
                    store.createSnippet(language: store.lastLanguage, in: url)
                })
                menu.addItem(action("New Subfolder") { [store] in store.createFolder(in: url) })
                menu.addItem(.separator())
                menu.addItem(action("Rename…") { [store] in store.folderPendingRename = url })
                menu.addItem(action("Reveal in Finder") { [store] in store.reveal(url) })
                menu.addItem(.separator())
                menu.addItem(action("Move to Trash") { [store] in store.trashFolder(url) })
            } else {
                menu.addItem(action("New Folder") { [store] in store.createFolder(in: store.root) })
            }
        }

        private func action(_ title: String, _ handler: @escaping () -> Void) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: #selector(ClosureTarget.invoke), keyEquivalent: "")
            let target = ClosureTarget(handler)
            item.target = target
            item.representedObject = target  // keeps the target alive as long as the item
            return item
        }
    }
}

// MARK: - Cells

private final class ClosureTarget: NSObject {
    let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    @objc func invoke() { handler() }
}

private final class HeaderCell: NSTableCellView {
    init(id: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        identifier = id
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }
}

private final class RowCell: NSTableCellView {
    private let badge = NSTextField(labelWithString: "")

    init(id: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        identifier = id

        let icon = NSImageView()
        let label = NSTextField(labelWithString: "")
        label.lineBreakMode = .byTruncatingTail
        badge.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        badge.textColor = .secondaryLabelColor
        badge.alignment = .right
        for view in [icon, label, badge] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        imageView = icon
        textField = label
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        badge.setContentCompressionResistancePriority(.required, for: .horizontal)
        badge.setContentHuggingPriority(.required, for: .horizontal)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            badge.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 6),
            badge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            badge.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func configure(title: String, symbol: String, count: Int) {
        textField?.stringValue = title
        imageView?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        imageView?.contentTintColor = .controlAccentColor
        badge.stringValue = count > 0 ? "\(count)" : ""
    }
}
