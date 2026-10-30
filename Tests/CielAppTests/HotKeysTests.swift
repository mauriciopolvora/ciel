import Carbon
import Foundation
import Testing

@testable import CielApp

@MainActor @Suite
struct HotKeysTests {
    private let f13 = Shortcut(keyCode: UInt32(kVK_F13), modifiers: UInt32(controlKey))
    private let f14 = Shortcut(keyCode: UInt32(kVK_F14), modifiers: UInt32(controlKey))

    @Test(arguments: HotKeyCommand.allCases)
    func anUpdatedShortcutIsLiveAndSaved(command: HotKeyCommand) throws {
        try withEmptyDefaults { defaults in
            let registrar = FakeHotKeyRegistrar()
            var pressed: [HotKeyCommand] = []
            let hotKeys = HotKeys(
                defaults: defaults, registrar: registrar, onPress: { pressed.append($0) }, onChange: {})
            try hotKeys.update(command, to: f13)
            registrar.press(f13)
            #expect(pressed == [command])
            let reloaded = HotKeys(
                defaults: defaults, registrar: FakeHotKeyRegistrar(), onPress: { _ in }, onChange: {})
            #expect(reloaded.shortcut(for: command) == f13)
        }
    }

    @Test func aRejectedShortcutKeepsThePreviousOneLive() throws {
        try withEmptyDefaults { defaults in
            let registrar = FakeHotKeyRegistrar()
            var pressed: [HotKeyCommand] = []
            let hotKeys = HotKeys(
                defaults: defaults, registrar: registrar, onPress: { pressed.append($0) }, onChange: {})
            try hotKeys.update(.window(.maximize), to: f13)
            let saved = defaults.data(forKey: "shortcuts")
            registrar.refused = [f14]
            #expect(throws: HotKeyError.unavailable) { try hotKeys.update(.window(.maximize), to: f14) }
            registrar.press(f13)
            #expect(pressed == [.window(.maximize)])
            #expect(hotKeys.shortcut(for: .window(.maximize)) == f13)
            #expect(defaults.data(forKey: "shortcuts") == saved)
        }
    }

    @Test func theLauncherShortcutCannotBeCleared() {
        withEmptyDefaults { defaults in
            let registrar = FakeHotKeyRegistrar()
            var pressed: [HotKeyCommand] = []
            let hotKeys = HotKeys(
                defaults: defaults, registrar: registrar, onPress: { pressed.append($0) }, onChange: {})
            #expect(throws: HotKeyError.required) { try hotKeys.update(.launcher, to: nil) }
            registrar.press(Shortcut.launcher)
            #expect(pressed == [.launcher])
        }
    }

    @Test func aClearedShortcutStopsFiring() throws {
        try withEmptyDefaults { defaults in
            let registrar = FakeHotKeyRegistrar()
            var pressed: [HotKeyCommand] = []
            let hotKeys = HotKeys(
                defaults: defaults, registrar: registrar, onPress: { pressed.append($0) }, onChange: {})
            try hotKeys.update(.window(.center), to: f13)
            try hotKeys.update(.window(.center), to: nil)
            registrar.press(f13)
            #expect(pressed.isEmpty)
            #expect(hotKeys.shortcut(for: .window(.center)) == nil)
        }
    }

    @Test func whileRecordingAPressGoesToTheRecorder() throws {
        try withEmptyDefaults { defaults in
            let registrar = FakeHotKeyRegistrar()
            var pressed: [HotKeyCommand] = []
            var recorded: [Shortcut] = []
            let hotKeys = HotKeys(
                defaults: defaults, registrar: registrar, onPress: { pressed.append($0) }, onChange: {})
            try hotKeys.update(.window(.leftHalf), to: f13)
            hotKeys.recordingHandler = { recorded.append($0) }
            registrar.press(f13)
            #expect(recorded == [f13])
            #expect(pressed.isEmpty)
        }
    }

    @Test func aReleaseReachesTheReleaseHandlerEvenWhileRecording() throws {
        try withEmptyDefaults { defaults in
            let registrar = FakeHotKeyRegistrar()
            var pressed: [HotKeyCommand] = []
            var released: [HotKeyCommand] = []
            let hotKeys = HotKeys(
                defaults: defaults, registrar: registrar, onPress: { pressed.append($0) },
                onRelease: { released.append($0) }, onChange: {})
            try hotKeys.update(.dictation, to: f13)
            registrar.press(f13)
            registrar.release(f13)
            #expect(pressed == [.dictation])
            #expect(released == [.dictation])
            registrar.press(f13)
            hotKeys.recordingHandler = { _ in }
            registrar.release(f13)
            #expect(pressed == [.dictation, .dictation])
            #expect(released == [.dictation, .dictation])
        }
    }

    @Test func dictationHasNoDefaultShortcut() {
        withEmptyDefaults { defaults in
            let hotKeys = HotKeys(
                defaults: defaults, registrar: FakeHotKeyRegistrar(), onPress: { _ in }, onChange: {})
            #expect(hotKeys.shortcut(for: .dictation) == nil)
        }
    }

    @Test func releasingHotKeysUnregistersEveryShortcut() throws {
        try withEmptyDefaults { defaults in
            let registrar = FakeHotKeyRegistrar()
            var hotKeys: HotKeys? = HotKeys(
                defaults: defaults, registrar: registrar, onPress: { _ in }, onChange: {})
            try hotKeys?.update(.window(.maximize), to: f13)
            #expect(registrar.liveShortcuts.count == 2)
            hotKeys = nil
            #expect(registrar.liveShortcuts.isEmpty)
        }
    }
}

@MainActor final class FakeHotKeyRegistrar: HotKeyRegistrar {
    var refused: [Shortcut] = []
    private var live: [Int: (shortcut: Shortcut, handler: @MainActor (HotKeyEvent) -> Void)] = [:]
    private var nextID = 0

    var liveShortcuts: [Shortcut] { live.values.map(\.shortcut) }

    func register(_ shortcut: Shortcut, handler: @escaping @MainActor (HotKeyEvent) -> Void) throws -> Cleanup
    {
        if refused.contains(shortcut) { throw HotKeyError.unavailable }
        let id = nextID
        nextID += 1
        live[id] = (shortcut, handler)
        return Cleanup { [weak self] in MainActor.assumeIsolated { _ = self?.live.removeValue(forKey: id) } }
    }

    func press(_ shortcut: Shortcut) { send(.pressed, to: shortcut) }

    func release(_ shortcut: Shortcut) { send(.released, to: shortcut) }

    private func send(_ event: HotKeyEvent, to shortcut: Shortcut) {
        for registration in live.values where registration.shortcut == shortcut {
            registration.handler(event)
        }
    }
}

func withEmptyDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
    let suite = "ciel.saved-data.test." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    try body(defaults)
}
