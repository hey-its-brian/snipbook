import AppKit
import Carbon.HIToolbox
import Observation

/// A keyboard shortcut as Carbon wants it, plus the label shown in Settings.
struct KeyShortcut: Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var display: String

    /// ⌥⇧Space. (⇧⌘Space was the first choice, but other apps commonly claim it.)
    static let defaultQuickSearch = KeyShortcut(
        keyCode: UInt32(kVK_Space),
        carbonModifiers: UInt32(optionKey | shiftKey),
        display: "⌥⇧Space"
    )

    /// Builds a shortcut from a key press. Needs ⌘, ⌃, or ⌥ so plain typing never triggers it.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.intersection([.command, .control, .option]).isEmpty else { return nil }
        var carbon: UInt32 = 0
        var label = ""
        if flags.contains(.control) { carbon |= UInt32(controlKey); label += "⌃" }
        if flags.contains(.option) { carbon |= UInt32(optionKey); label += "⌥" }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey); label += "⇧" }
        if flags.contains(.command) { carbon |= UInt32(cmdKey); label += "⌘" }
        keyCode = UInt32(event.keyCode)
        carbonModifiers = carbon
        display = label + Self.keyName(event)
    }

    init(keyCode: UInt32, carbonModifiers: UInt32, display: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.display = display
    }

    private static func keyName(_ event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Escape: return "⎋"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default:
            let chars = event.charactersIgnoringModifiers ?? "?"
            return chars.uppercased()
        }
    }
}

/// Owns the system-wide Quick Search shortcut. Carbon hot keys work without Accessibility permission.
@MainActor
@Observable
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private enum Keys {
        static let code = "quickSearchKeyCode"
        static let modifiers = "quickSearchModifiers"
        static let display = "quickSearchDisplay"
    }

    /// nil means the shortcut is turned off.
    private(set) var shortcut: KeyShortcut?
    private(set) var registrationFailed = false

    @ObservationIgnored var onPress: (() -> Void)?
    @ObservationIgnored private var hotKeyRef: EventHotKeyRef?
    @ObservationIgnored private var handlerRef: EventHandlerRef?

    private init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Keys.code) == nil {
            shortcut = .defaultQuickSearch
        } else if let display = defaults.string(forKey: Keys.display), !display.isEmpty {
            shortcut = KeyShortcut(keyCode: UInt32(defaults.integer(forKey: Keys.code)),
                                   carbonModifiers: UInt32(defaults.integer(forKey: Keys.modifiers)),
                                   display: display)
        }
    }

    func start() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { HotKeyCenter.shared.onPress?() }
            return noErr
        }, 1, &spec, nil, &handlerRef)
        register()
    }

    func update(_ newValue: KeyShortcut?) {
        shortcut = newValue
        let defaults = UserDefaults.standard
        defaults.set(Int(newValue?.keyCode ?? 0), forKey: Keys.code)
        defaults.set(Int(newValue?.carbonModifiers ?? 0), forKey: Keys.modifiers)
        defaults.set(newValue?.display ?? "", forKey: Keys.display)
        register()
    }

    /// While recording a new shortcut, the old one must not fire.
    func suspend() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    func resume() { register() }

    private func register() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        registrationFailed = false
        guard let shortcut else { return }
        let id = EventHotKeyID(signature: OSType(0x534E_4950), id: 1)  // "SNIP"
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers, id,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        registrationFailed = status != noErr
    }
}
