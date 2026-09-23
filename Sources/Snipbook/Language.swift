import SwiftUI

/// A language the library understands. The file extension decides the language,
/// so snippets stay plain files that any editor or `grep` can read.
struct Language: Identifiable, Hashable {
    /// highlight.js language name used for syntax coloring.
    let id: String
    let name: String
    /// Extension used when creating a snippet in this language.
    let ext: String
    /// Other extensions that map to this language.
    var aliases: [String] = []
    let tint: Color

    static let all: [Language] = [
        Language(id: "ruby", name: "Ruby", ext: "rb", aliases: ["rake", "gemspec", "ru"], tint: .red),
        Language(id: "erb", name: "Rails ERB", ext: "erb", tint: .pink),
        Language(id: "bash", name: "Bash", ext: "sh", aliases: ["bash", "zsh", "command"], tint: .green),
        Language(id: "sql", name: "SQL", ext: "sql", tint: .blue),
        Language(id: "javascript", name: "JavaScript", ext: "js", aliases: ["mjs", "cjs", "jsx"], tint: .yellow),
        Language(id: "typescript", name: "TypeScript", ext: "ts", aliases: ["tsx"], tint: .blue),
        Language(id: "xml", name: "HTML", ext: "html", aliases: ["htm", "xml", "svg"], tint: .orange),
        Language(id: "css", name: "CSS", ext: "css", tint: .purple),
        Language(id: "scss", name: "SCSS", ext: "scss", aliases: ["sass"], tint: .purple),
        Language(id: "python", name: "Python", ext: "py", tint: .cyan),
        Language(id: "c", name: "C", ext: "c", aliases: ["h"], tint: .gray),
        Language(id: "cpp", name: "C++", ext: "cpp", aliases: ["hpp", "cc", "cxx", "hh"], tint: .teal),
        Language(id: "arduino", name: "Arduino", ext: "ino", tint: .teal),
        Language(id: "swift", name: "Swift", ext: "swift", tint: .orange),
        Language(id: "yaml", name: "YAML", ext: "yml", aliases: ["yaml"], tint: .indigo),
        Language(id: "json", name: "JSON", ext: "json", tint: .indigo),
        Language(id: "ini", name: "INI / TOML", ext: "ini", aliases: ["toml", "cfg", "conf"], tint: .mint),
        Language(id: "markdown", name: "Markdown", ext: "md", aliases: ["markdown"], tint: .brown),
        Language(id: "plaintext", name: "Plain Text", ext: "txt", tint: .secondary),
    ]

    static let plainText = all.last!

    private static let byExtension: [String: Language] = {
        var map: [String: Language] = [:]
        for language in all {
            for ext in [language.ext] + language.aliases { map[ext] = language }
        }
        return map
    }()

    static func forExtension(_ ext: String) -> Language {
        byExtension[ext.lowercased()] ?? plainText
    }

    static func == (lhs: Language, rhs: Language) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
