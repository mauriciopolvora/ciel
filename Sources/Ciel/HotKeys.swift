import AppKit
import Carbon

struct Shortcut: Codable, Equatable, Sendable {
    let keyCode: UInt32
    let modifiers: UInt32
    var display: String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        return result + Self.keyName(keyCode)
    }
    static let launcher = Shortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey))
    static func from(_ event: NSEvent) -> Shortcut? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command) || flags.contains(.control) || flags.contains(.option) else {
            return nil
        }
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        return Shortcut(keyCode: UInt32(event.keyCode), modifiers: mods)
    }
    static func keyName(_ code: UInt32) -> String {
        let special: [UInt32: String] = [
            49: "Space", 36: "↩", 48: "⇥", 51: "⌫", 53: "⎋", 123: "←", 124: "→", 125: "↓", 126: "↑",
        ]
        if let name = special[code] { return name }
        // Read the current keyboard layout, rather than assuming US key positions.
        if let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        {
            let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue()
            let layout = UnsafeRawPointer(CFDataGetBytePtr(data)).assumingMemoryBound(
                to: UCKeyboardLayout.self)
            var dead: UInt32 = 0
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(
                layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, 4, &length, &chars)
            if status == noErr, length > 0 {
                return String(utf16CodeUnits: chars, count: length).uppercased()
            }
        }
        return "Key \(code)"
    }
}

@MainActor final class HotKeys {
    var recordingHandler: ((Shortcut) -> Void)?
    private let resources = HotKeyResources()
    private var handlers: [UInt32: () -> Void] = [:]
    private var ids: [String: UInt32] = [:]
    private var nextID: UInt32 = 1
    private(set) var shortcuts: [String: Shortcut] = [:]
    private(set) var registrationErrors: [String] = []
    nonisolated static let signature: OSType = 0x4A55_4D50  // JUMP

    init() {
        if let data = UserDefaults.standard.data(forKey: "shortcuts"),
            let saved = try? JSONDecoder().decode([String: Shortcut].self, from: data)
        {
            shortcuts = saved
        }
        if shortcuts["launcher"] == nil { shortcuts["launcher"] = .launcher }
        var type = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                var identifier = EventHotKeyID()
                let status = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
                guard status == noErr, identifier.signature == HotKeys.signature else {
                    return OSStatus(eventNotHandledErr)
                }
                let owner = Unmanaged<HotKeys>.fromOpaque(context).takeUnretainedValue()
                // Carbon sends application-target events through the main event loop.
                return MainActor.assumeIsolated {
                    if let recording = owner.recordingHandler,
                        let name = owner.ids.first(where: { $0.value == identifier.id })?.key,
                        let shortcut = owner.shortcuts[name]
                    {
                        recording(shortcut)
                        return noErr
                    }
                    owner.handlers[identifier.id]?()
                    return noErr
                }
            }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &resources.eventHandler)
    }

    func bind(_ name: String, handler: @escaping () -> Void) {
        if ids[name] == nil {
            ids[name] = nextID
            nextID += 1
        }
        handlers[ids[name]!] = handler
        if let shortcut = shortcuts[name] {
            do { try register(name, shortcut) } catch {
                registrationErrors.append("\(name): \(error.localizedDescription)")
            }
        }
    }

    func update(_ name: String, shortcut: Shortcut?) throws {
        if let shortcut {
            if shortcuts.contains(where: { $0.key != name && $0.value == shortcut }) {
                throw HotKeyError.duplicate
            }
            // Register before removing the previous hotkey, so failure leaves it working.
            if shortcut == shortcuts[name], resources.refs[name] != nil { return }
            try register(name, shortcut)
            shortcuts[name] = shortcut
        } else {
            if let ref = resources.refs.removeValue(forKey: name) { UnregisterEventHotKey(ref) }
            shortcuts.removeValue(forKey: name)
        }
        UserDefaults.standard.set(try JSONEncoder().encode(shortcuts), forKey: "shortcuts")
    }

    private func register(_ name: String, _ shortcut: Shortcut) throws {
        guard let id = ids[name] else { return }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode, shortcut.modifiers, EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { throw HotKeyError.unavailable }
        if let old = resources.refs[name] { UnregisterEventHotKey(old) }
        resources.refs[name] = ref
    }

}

/// HotKeys confines this handle owner to the main actor. The handles clean up
/// when the owner is released, without an isolated class reading them in deinit.
private final class HotKeyResources {
    var refs: [String: EventHotKeyRef] = [:]
    var eventHandler: EventHandlerRef?

    deinit {
        for ref in refs.values { UnregisterEventHotKey(ref) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}

enum HotKeyError: LocalizedError {
    case duplicate, unavailable
    var errorDescription: String? {
        switch self {
        case .duplicate: return "This shortcut is already assigned in Ciel."
        case .unavailable: return "This shortcut is used by macOS or another app. Choose another."
        }
    }
}

final class ShortcutRecorder: NSButton {
    var onRecord: ((Shortcut?) -> Void)?
    var onBegin: (() -> Void)?
    var onEnd: (() -> Void)?
    var shortcut: Shortcut? { didSet { updateTitle() } }
    private(set) var recording = false
    override var acceptsFirstResponder: Bool { true }
    init(shortcut: Shortcut?, onRecord: @escaping (Shortcut?) -> Void) {
        self.shortcut = shortcut
        self.onRecord = onRecord
        super.init(frame: .zero)
        bezelStyle = .rounded
        font = .systemFont(ofSize: 12, weight: .medium)
        target = self
        action = #selector(start)
        updateTitle()
        toolTip = "Click to record. Press Escape to cancel, or Delete to clear."
    }
    required init?(coder: NSCoder) { fatalError() }
    private func updateTitle() { title = recording ? "Press shortcut…" : shortcut?.display ?? "Set shortcut" }
    @objc private func start() {
        window?.makeFirstResponder(self)
        recording = true
        updateTitle()
        onBegin?()
    }
    override func resignFirstResponder() -> Bool {
        recording = false
        updateTitle()
        onEnd?()
        return super.resignFirstResponder()
    }
    func accept(_ shortcut: Shortcut) {
        recording = false
        onEnd?()
        onRecord?(shortcut)
        updateTitle()
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event)
        return true
    }
    override func keyDown(with event: NSEvent) {
        guard recording else {
            super.keyDown(with: event)
            return
        }
        if event.keyCode == 53 {
            recording = false
            onEnd?()
            updateTitle()
            return
        }
        if event.keyCode == 51 {
            recording = false
            onEnd?()
            onRecord?(nil)
            updateTitle()
            return
        }
        guard let recorded = Shortcut.from(event) else {
            NSSound.beep()
            return
        }
        accept(recorded)
    }
}
