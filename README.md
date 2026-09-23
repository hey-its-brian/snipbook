# Snipbook

A native macOS code snippet manager, inspired by SnippetsLab.

- **Syntax coloring** for Ruby, Rails ERB, Bash, SQL, JavaScript, TypeScript, HTML, CSS/SCSS, Python, C, C++, Arduino, Swift, YAML, JSON, INI/TOML and Markdown (via [Highlightr](https://github.com/raspu/Highlightr) / highlight.js). Follows light and dark mode.
- **Per-snippet locking.** Lock uses the Finder "Locked" flag (`uchg`), so macOS itself refuses edits, renames, moves and deletes until you unlock.
- **Folder organization.** Nested folders, drag snippets onto folders, drag files in from Finder to import them.
- Search across titles, languages and contents; copy a snippet with one click (⇧⌘C).

## Your library is just files

Snippets live in `~/Snippets` as plain files in real folders. The file extension sets the language (`.rb`, `.sh`, `.sql`, ...). That means you can `grep` them, put the folder under git, or sync it with iCloud Drive. Use **File > Choose Library Folder...** to point Snipbook somewhere else. A starter set of snippets is created the first time the folder does not exist.

## Build

Requires macOS 14+ and Xcode (the Command Line Tools alone lack SwiftUI's macro plugin).

```bash
./scripts/build-app.sh            # builds build/Snipbook.app
./scripts/build-app.sh --install  # also copies it to /Applications
```

The script uses `/Applications/Xcode.app` even if `xcode-select` points at the Command Line Tools. For quick iteration: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run`.

## Shortcuts

| Action | Keys |
| --- | --- |
| New snippet | ⌘N |
| New folder | ⇧⌘N |
| Lock / unlock | ⌘L |
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
| `CodeEditor.swift` | NSTextView with live highlighting |
| `Language.swift` | Extension to language table |
| `SeedLibrary.swift` | Starter snippets |
| `DebugSnapshot.swift` | Debug-only window snapshot for UI checks |
