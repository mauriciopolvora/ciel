import AppKit
import Carbon
import CielCore

struct Shortcut: Codable, Equatable, Sendable {
    let keyCode: UInt32
    let modifiers: UInt32
    var modifierKey: ModifierKey? { modifiers == 0 ? ModifierKey(rawValue: keyCode) : nil }
    var display: String {
        if let modifierKey { return modifierKey.display }
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        return result + Self.keyName(keyCode)
    }
    static let launcher = Shortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey))
    static func modifier(_ key: ModifierKey) -> Shortcut { Shortcut(keyCode: key.rawValue, modifiers: 0) }
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

enum HotKeyCommand: Hashable, Sendable {
    case launcher
    case window(WindowAction)
    case dictation

    static var allCases: [HotKeyCommand] {
        [.launcher] + WindowAction.allCases.map(Self.window) + [.dictation]
    }

    var storageKey: String {
        switch self {
        case .launcher: "launcher"
        case .window(let action): action.id
        case .dictation: "dictation"
        }
    }
}

enum HotKeyEvent: Sendable {
    case pressed, released, cancelled
}

@MainActor protocol HotKeyRegistrar {
    func register(_ shortcut: Shortcut, handler: @escaping @MainActor (HotKeyEvent) -> Void) throws -> Cleanup
}

@MainActor final class HotKeys {
    var recordingHandler: ((Shortcut) -> Void)?
    private(set) var registrationErrors: [String] = []
    private var shortcuts: [String: Shortcut] = [:]
    private var registrations: [HotKeyCommand: Cleanup] = [:]
    private let defaults: UserDefaults
    private let registrar: any HotKeyRegistrar
    private let onPress: (HotKeyCommand) -> Void
    private let onRelease: (HotKeyCommand) -> Void
    private let onCancel: (HotKeyCommand) -> Void
    private let onChange: () -> Void

    init(
        defaults: UserDefaults = .standard, registrar: any HotKeyRegistrar,
        onPress: @escaping (HotKeyCommand) -> Void, onRelease: @escaping (HotKeyCommand) -> Void = { _ in },
        onCancel: @escaping (HotKeyCommand) -> Void = { _ in }, onChange: @escaping () -> Void
    ) {
        self.defaults = defaults
        self.registrar = registrar
        self.onPress = onPress
        self.onRelease = onRelease
        self.onCancel = onCancel
        self.onChange = onChange
        if let data = defaults.data(forKey: "shortcuts"),
            let saved = try? JSONDecoder().decode([String: Shortcut].self, from: data)
        {
            shortcuts = saved
        }
        if shortcuts[HotKeyCommand.launcher.storageKey] == nil {
            shortcuts[HotKeyCommand.launcher.storageKey] = .launcher
        }
        for command in HotKeyCommand.allCases {
            guard let shortcut = shortcuts[command.storageKey] else { continue }
            do { try register(command, shortcut) } catch {
                registrationErrors.append("\(command.storageKey): \(error.localizedDescription)")
            }
        }
    }

    func shortcut(for command: HotKeyCommand) -> Shortcut? { shortcuts[command.storageKey] }

    func isLive(_ command: HotKeyCommand) -> Bool { registrations[command] != nil }

    func retryUnregistered() {
        for command in HotKeyCommand.allCases where registrations[command] == nil {
            guard let shortcut = shortcuts[command.storageKey] else { continue }
            try? register(command, shortcut)
        }
    }

    func update(_ command: HotKeyCommand, to shortcut: Shortcut?) throws {
        if let shortcut {
            if shortcuts.contains(where: { $0.key != command.storageKey && $0.value == shortcut }) {
                throw HotKeyError.duplicate
            }
            if shortcut == shortcuts[command.storageKey], registrations[command] != nil { return }
            try register(command, shortcut)
        } else {
            guard command != .launcher else { throw HotKeyError.required }
            registrations[command] = nil
        }
        shortcuts[command.storageKey] = shortcut
        defaults.set(try JSONEncoder().encode(shortcuts), forKey: "shortcuts")
        onChange()
    }

    private func register(_ command: HotKeyCommand, _ shortcut: Shortcut) throws {
        registrations[command] = try registrar.register(shortcut) { [weak self] event in
            self?.handle(command, event)
        }
    }

    private func handle(_ command: HotKeyCommand, _ event: HotKeyEvent) {
        switch event {
        case .released: onRelease(command)
        case .cancelled: onCancel(command)
        case .pressed:
            guard let recordingHandler else { return onPress(command) }
            if let shortcut = shortcuts[command.storageKey], shortcut.modifierKey == nil {
                recordingHandler(shortcut)
            }
        }
    }
}

@MainActor final class SystemHotKeyRegistrar: HotKeyRegistrar {
    nonisolated static let signature: OSType = "CIEL".utf8.reduce(0) { $0 << 8 | OSType($1) }
    private var handlers: [UInt32: @MainActor (HotKeyEvent) -> Void] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: Cleanup?

    init() {
        var types = [kEventHotKeyPressed, kEventHotKeyReleased].map {
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32($0))
        }
        var handler: EventHandlerRef?
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                var identifier = EventHotKeyID()
                let status = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
                guard status == noErr, identifier.signature == SystemHotKeyRegistrar.signature else {
                    return OSStatus(eventNotHandledErr)
                }
                let owner = Unmanaged<SystemHotKeyRegistrar>.fromOpaque(context).takeUnretainedValue()
                let kind: HotKeyEvent =
                    GetEventKind(event) == UInt32(kEventHotKeyReleased) ? .released : .pressed
                // Carbon sends application-target events through the main event loop.
                return MainActor.assumeIsolated {
                    owner.handlers[identifier.id]?(kind)
                    return noErr
                }
            }, types.count, &types, Unmanaged.passUnretained(self).toOpaque(), &handler)
        if let handler { eventHandler = Cleanup { RemoveEventHandler(handler) } }
    }

    func register(_ shortcut: Shortcut, handler: @escaping @MainActor (HotKeyEvent) -> Void) throws -> Cleanup
    {
        if let key = shortcut.modifierKey {
            guard WindowController.isTrusted else { throw HotKeyError.needsAccess }
            let monitor = ModifierKeyMonitor(key: key, handler: handler)
            return Cleanup { MainActor.assumeIsolated { monitor.stop() } }
        }
        let id = nextID
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode, shortcut.modifiers, EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { throw HotKeyError.unavailable }
        nextID += 1
        handlers[id] = handler
        return Cleanup { UnregisterEventHotKey(ref) }
    }
}

/// Global NSEvent key monitors need Accessibility access, and unlike Carbon hot keys they never swallow the key.
@MainActor private final class ModifierKeyMonitor {
    private var gesture: ModifierGesture
    private let handler: @MainActor (HotKeyEvent) -> Void
    private var monitors: [Any] = []
    private var sleep: Cleanup?

    init(key: ModifierKey, handler: @escaping @MainActor (HotKeyEvent) -> Void) {
        gesture = ModifierGesture(key: key)
        self.handler = handler
        let events: NSEvent.EventTypeMask = [
            .flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown,
        ]
        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] event in
                MainActor.assumeIsolated { self?.handle(event) }
            },
            NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
                MainActor.assumeIsolated { self?.handle(event) }
                return event
            },
        ].compactMap { $0 }
        sleep = NSWorkspace.shared.notificationCenter.observe(NSWorkspace.willSleepNotification) {
            [weak self] in self?.send(self?.gesture.reset())
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        sleep = nil
    }

    private func handle(_ event: NSEvent) {
        send(
            event.type == .flagsChanged
                ? gesture.flagsChanged(event.modifierFlags.rawValue) : gesture.interrupt())
    }

    private func send(_ event: HotKeyEvent?) {
        if let event { handler(event) }
    }
}

enum HotKeyError: LocalizedError {
    case duplicate, unavailable, required, needsAccess
    var errorDescription: String? {
        switch self {
        case .duplicate: return "This shortcut is already assigned in Ciel."
        case .unavailable: return "This shortcut is used by macOS or another app. Choose another."
        case .required: return "Choose a launcher shortcut."
        case .needsAccess: return "A single key shortcut needs access. Choose Allow Access."
        }
    }
}

final class ShortcutRecorder: NSButton {
    var onRecord: ((Shortcut?) -> Void)?
    var onBegin: (() -> Void)?
    var onEnd: (() -> Void)?
    var shortcut: Shortcut? { didSet { updateTitle() } }
    var acceptsModifierKey = false
    private(set) var recording = false
    private var gestures = ModifierKey.allCases.map(ModifierGesture.init)
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
        gestures = ModifierKey.allCases.map(ModifierGesture.init)
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
    override func flagsChanged(with event: NSEvent) {
        guard recording, acceptsModifierKey else { return super.flagsChanged(with: event) }
        for index in gestures.indices {
            if gestures[index].flagsChanged(event.modifierFlags.rawValue) == .released {
                return accept(.modifier(gestures[index].key))
            }
        }
    }
    override func keyDown(with event: NSEvent) {
        guard recording else {
            super.keyDown(with: event)
            return
        }
        for index in gestures.indices { _ = gestures[index].interrupt() }
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
