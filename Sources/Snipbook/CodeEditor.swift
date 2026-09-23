import AppKit
import Highlightr
import SwiftUI

/// NSTextView backed by Highlightr's CodeAttributedString, which re-colors text as you type.
struct CodeEditor: NSViewRepresentable {
    let fileID: String
    let text: String
    let language: String
    let isEditable: Bool
    let onChange: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    func makeNSView(context: Context) -> NSScrollView {
        let storage = CodeAttributedString()
        storage.language = language
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let huge = CGFloat.greatestFiniteMagnitude
        let container = NSTextContainer(size: NSSize(width: huge, height: huge))
        container.widthTracksTextView = false
        layout.addTextContainer(container)

        let textView = CodeTextView(frame: .zero, textContainer: container)
        textView.highlightr = storage.highlightr
        textView.minSize = .zero
        textView.maxSize = NSSize(width: huge, height: huge)
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width, .height]
        textView.textContainerInset = NSSize(width: 10, height: 12)
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.smartInsertDeleteEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.delegate = context.coordinator

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        textView.applyTheme()

        context.coordinator.textView = textView
        context.coordinator.storage = storage
        context.coordinator.fileID = fileID
        textView.string = text
        textView.isEditable = isEditable
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onChange = onChange
        guard let textView = coordinator.textView, let storage = coordinator.storage else { return }

        if storage.language != language { storage.language = language }
        textView.isEditable = isEditable

        let switchedFile = coordinator.fileID != fileID
        coordinator.fileID = fileID
        if textView.string != text {
            textView.string = text
            if switchedFile {
                textView.undoManager?.removeAllActions()
                textView.scroll(.zero)
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onChange: (String) -> Void
        var fileID = ""
        weak var textView: CodeTextView?
        var storage: CodeAttributedString?

        init(onChange: @escaping (String) -> Void) { self.onChange = onChange }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            onChange(textView.string)
        }
    }
}

final class CodeTextView: NSTextView {
    var highlightr: Highlightr?
    static let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTheme()
    }

    /// Follows the system light/dark setting.
    func applyTheme() {
        guard let highlightr else { return }
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        _ = highlightr.setTheme(to: isDark ? "atom-one-dark" : "atom-one-light")
        highlightr.theme.setCodeFont(Self.font)
        // setCodeFont does not notify, so reassign to trigger a full re-highlight with the new font.
        let theme = highlightr.theme
        highlightr.theme = theme

        let background = highlightr.theme.themeBackgroundColor ?? .textBackgroundColor
        backgroundColor = background
        enclosingScrollView?.backgroundColor = background
        insertionPointColor = isDark ? .white : .black
        typingAttributes[.font] = Self.font
    }
}
