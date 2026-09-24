# Snipbook

A native macOS code snippet manager, inspired by SnippetsLab.

- **Syntax coloring** for Ruby, Rails ERB, Bash, SQL, JavaScript, TypeScript, HTML, CSS/SCSS, Python, C, C++, Arduino, Swift, YAML, JSON, INI/TOML and Markdown (via [Highlightr](https://github.com/raspu/Highlightr) / highlight.js). Follows light and dark mode.
- **Per-snippet locking.** Lock uses the Finder "Locked" flag (`uchg`), so macOS itself refuses edits, renames, moves and deletes until you unlock.
- **Folder organization.** Nested folders with recursive snippet counts. Drag snippets onto folders, drag folders onto folders to nest them (or onto All Snippets to move them to the top level), and drag files in from Finder to import them.
- **Multi-select** with ⌘-click and ⇧-click: lock, unlock, copy, move, duplicate or trash many snippets at once, or drag the whole selection onto a folder.
- **Settings** (⌘,): library location (with the choice to move your snippets or leave them), default folder for new snippets, whether folders list their subfolders' snippets, and a choice of four app icons.
- **Tags** are real macOS Finder tags, so they also show in Finder and Spotlight. A Tags section in the sidebar filters by tag (drop snippets on a tag to apply it), tag chips sit under each snippet's title, and multi-select can add or remove tags in bulk. Locked snippets can still be tagged.
- **Quick Search** (⌥⇧Space from any app, changeable in Settings): type to find a snippet, Return pastes it into the app you were in, ⌘Return only copies. Auto-paste needs Accessibility permission for Snipbook.
- **Line numbers** in the editor (toggle in Settings).
- Search across titles, tags (`#tag`), languages and contents; copy a snippet with one click (⇧⌘C).

## Your library is just files

Snippets live in `~/Snippets` as plain files in real folders. The file extension sets the language (`.rb`, `.sh`, `.sql`, ...). That means you can `grep` them, put the folder under git, or sync it with iCloud Drive. Use **Settings > Library > Change...** (or File > Choose Library Folder...) to point Snipbook somewhere else; you can move your existing snippets along or leave them where they are. Lock state survives the move. A starter set of snippets is created the first time the folder does not exist.

## Build

Requires macOS 14+ and Xcode (the Command Line Tools alone lack SwiftUI's macro plugin).

```bash
./scripts/build-app.sh            # builds build/Snipbook.app
./scripts/build-app.sh --install  # also copies it to /Applications
```

The script signs with your Apple Development certificate when one is in the keychain (falling back to ad hoc). A stable signature matters because macOS ties Snipbook's Accessibility permission, used for auto-paste, to it. The script uses `/Applications/Xcode.app` even if `xcode-select` points at the Command Line Tools. For quick iteration: `swift run`. Run the tests with `swift test`; they exercise the file operations (moves, nesting, counts, library moves with locked files) against a temporary library.

## Shortcuts

| Action | Keys |
| --- | --- |
| Quick Search (from any app) | ⌥⇧Space |
| New snippet | ⌘N |
| New folder | ⇧⌘N |
| Settings | ⌘, |
| Lock / unlock (whole selection) | ⌘L |
| Copy contents | ⇧⌘C |
| Duplicate | ⌘D |
| Find in snippet | ⌘F |
| Reload library | ⌘R |

## Layout

| File | Purpose |
| --- | --- |
| `SnipbookApp.swift` | App entry, menus and shortcuts |
| `LibraryStore.swift` | Reads and writes the library on disk; locking, moves, autosave |
| `Views.swift` | Sidebar, snippet list, detail view |
| `CodeEditor.swift` | NSTextView with live highlighting and a line-number ruler |
| `Language.swift` | Extension to language table |
| `SettingsView.swift` | Settings window, including the shortcut recorder |
| `SidebarOutline.swift` | Sidebar (NSOutlineView): folders, tags, drag and drop |
| `QuickSearch.swift` | Quick Search panel and paste-back |
| `HotKey.swift` | Global shortcut (Carbon `RegisterEventHotKey`) |
| `AppIcon.swift` | Icon choices; sets the Dock icon and the app bundle's Finder icon |
| `SeedLibrary.swift` | Starter snippets |
| `DebugSnapshot.swift` | Debug-only window snapshot for UI checks |
