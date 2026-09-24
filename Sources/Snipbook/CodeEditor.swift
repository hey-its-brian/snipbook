import AppKit
import Highlightr
import SwiftUI

/// NSTextView backed by Highlightr's CodeAttributedString, which re-colors text as you type.
struct CodeEditor: NSViewRepresentable {
    let fileID: String
    let text: String
    let language: String
    let isEditable: Bool
    var showLineNumbers = true
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

        let ruler = LineNumberRuler(textView: textView)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = showLineNumbers
        textView.applyTheme()

        context.coordinator.textView = textView
        context.coordinator.storage = storage
        context.coordinator.fileID = fileID
        textView.string = text
        textView.isEditable = isEditable
        ruler.refresh()
        DispatchQueue.main.async { scrollView.scrollToTopLeft() }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onChange = onChange
        guard let textView = coordinator.textView, let storage = coordinator.storage else { return }

        if storage.language != language { storage.language = language }
        textView.isEditable = isEditable
        if scrollView.rulersVisible != showLineNumbers { scrollView.rulersVisible = showLineNumbers }

        let switchedFile = coordinator.fileID != fileID
        coordinator.fileID = fileID
        if textView.string != text {
            textView.string = text
            if switchedFile {
                textView.undoManager?.removeAllActions()
                DispatchQueue.main.async { scrollView.scrollToTopLeft() }
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
            (textView.enclosingScrollView?.verticalRulerView as? LineNumberRuler)?.refresh()
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
        (enclosingScrollView?.verticalRulerView as? LineNumberRuler)?.refresh()
    }

    override var string: String {
        didSet { (enclosingScrollView?.verticalRulerView as? LineNumberRuler)?.refresh() }
    }
}

/// Line numbers in a gutter left of the editor. Numbers count real lines (newlines), so they stay
/// correct however the text is laid out.
final class LineNumberRuler: NSRulerView {
    private weak var textView: CodeTextView?
    private let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)

    init(textView: CodeTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        clipsToBounds = true
        ruleThickness = 36
    }

    required init(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    /// Widens the gutter to fit the largest line number. Called when the text changes, never while
    /// drawing: resizing mid-draw re-tiles the scroll view and shifts the text sideways.
    func refresh() {
        let lines = max(1, (textView?.string ?? "").reduce(1) { $1 == "\n" ? $0 + 1 : $0 })
        let wanted = max(28, CGFloat(String(lines).count) * 7.5 + 16)
        if abs(ruleThickness - wanted) > 0.5 { ruleThickness = wanted }
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView, let layout = textView.layoutManager, let container = textView.textContainer else { return }
        let background = textView.backgroundColor
        background.setFill()
        bounds.fill()

        let text = textView.string as NSString
        let isDark = textView.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: (isDark ? NSColor.white : NSColor.black).withAlphaComponent(0.35),
        ]

        let visible = textView.visibleRect
        let glyphs = layout.glyphRange(forBoundingRect: visible, in: container)
        let chars = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        var line = text.substring(to: chars.location).components(separatedBy: "\n").count
        let inset = textView.textContainerInset.height
        let offset = convert(NSPoint.zero, from: textView).y

        func draw(_ number: Int, atLineTop y: CGFloat, height: CGFloat) {
            let label = "\(number)" as NSString
            let size = label.size(withAttributes: attrs)
            let top = offset + inset + y + (height - size.height) / 2
            label.draw(at: NSPoint(x: ruleThickness - size.width - 8, y: top), withAttributes: attrs)
        }

        var index = chars.location
        while index < NSMaxRange(chars) {
            let lineRange = text.lineRange(for: NSRange(location: index, length: 0))
            let glyph = layout.glyphIndexForCharacter(at: lineRange.location)
            let fragment = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            draw(line, atLineTop: fragment.minY, height: fragment.height)
            line += 1
            index = NSMaxRange(lineRange)
        }
        // The empty last line after a trailing newline (or an empty snippet).
        let extra = layout.extraLineFragmentRect
        if !extra.isEmpty, extra.minY <= visible.maxY {
            draw(line, atLineTop: extra.minY, height: extra.height)
        }
    }
}

extension NSScrollView {
    /// Scrolls to the top-left corner. `NSView.scroll(.zero)` would ignore the content inset the
    /// line-number gutter adds, sliding the first characters of every line under the gutter.
    func scrollToTopLeft() {
        let clip = contentView
        let far = NSRect(origin: NSPoint(x: -1e7, y: -1e7), size: clip.bounds.size)
        clip.scroll(to: clip.constrainBoundsRect(far).origin)
        reflectScrolledClipView(clip)
    }
}
