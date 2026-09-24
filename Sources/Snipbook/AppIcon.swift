import AppKit

/// The icon concepts drawn by `Resources/icon/render.swift`, selectable in Settings.
enum AppIconChoice: String, CaseIterable, Identifiable {
    case midnight, braces, folder, notebook

    var id: String { rawValue }

    var title: String {
        switch self {
        case .midnight: "Midnight"
        case .braces: "Braces"
        case .folder: "Folder"
        case .notebook: "Notebook"
        }
    }

    var image: NSImage? {
        Bundle.module.url(forResource: "icon-\(rawValue)", withExtension: "png", subdirectory: "AppIcons")
            .flatMap(NSImage.init(contentsOf:))
    }
}

@MainActor
enum AppIconManager {
    /// Midnight is the icon baked into the bundle, so choosing it removes any override.
    /// - Parameter updateBundle: also set a custom Finder icon on Snipbook.app, so the Dock and
    ///   Finder show the choice while the app is closed. Only needed when the choice changes.
    static func apply(_ choice: AppIconChoice, updateBundle: Bool) {
        let image = choice == .midnight ? nil : choice.image
        NSApp.applicationIconImage = image

        let bundlePath = Bundle.main.bundlePath
        guard updateBundle, bundlePath.hasSuffix(".app") else { return }
        NSWorkspace.shared.setIcon(image, forFile: bundlePath, options: [])
    }

    /// Called at launch. Rebuilding or reinstalling the app replaces the bundle and drops the custom
    /// Finder icon, so re-apply it when the bundle and the saved choice disagree.
    static func syncOnLaunch(_ choice: AppIconChoice) {
        let hasCustomIcon = FileManager.default.fileExists(atPath: Bundle.main.bundlePath + "/Icon\r")
        apply(choice, updateBundle: hasCustomIcon != (choice != .midnight))
    }
}
