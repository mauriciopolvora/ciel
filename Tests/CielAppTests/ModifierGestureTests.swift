import Testing

@testable import CielApp

struct ModifierGestureTests {
    private static let alone: [ModifierKey: UInt] = [
        .rightCommand: 0x10_0010, .rightOption: 0x8_0040, .function: 0x80_0000,
    ]
    private static let leftShift: UInt = 0x2_0002
    private static let leftCommand: UInt = 0x10_0008
    private static let capsLock: UInt = 0x1_0000

    @Test(arguments: ModifierKey.allCases)
    func theKeyAlonePressesAndReleases(key: ModifierKey) {
        var gesture = ModifierGesture(key: key)
        #expect(gesture.flagsChanged(Self.alone[key]!) == .pressed)
        #expect(gesture.flagsChanged(0x100) == .released)
    }

    @Test(arguments: ModifierKey.allCases)
    func anotherKeyWhileHeldCancelsAndTheReleaseIsSilent(key: ModifierKey) {
        var gesture = ModifierGesture(key: key)
        #expect(gesture.flagsChanged(Self.alone[key]!) == .pressed)
        #expect(gesture.interrupt() == .cancelled)
        #expect(gesture.interrupt() == nil)
        #expect(gesture.flagsChanged(0x100) == nil)
        #expect(gesture.flagsChanged(Self.alone[key]!) == .pressed)
    }

    @Test(arguments: ModifierKey.allCases)
    func anotherModifierWhileHeldCancels(key: ModifierKey) {
        var gesture = ModifierGesture(key: key)
        #expect(gesture.flagsChanged(Self.alone[key]!) == .pressed)
        #expect(gesture.flagsChanged(Self.alone[key]! | Self.leftShift) == .cancelled)
        #expect(gesture.flagsChanged(Self.leftShift) == nil)
        #expect(gesture.flagsChanged(0x100) == nil)
    }

    @Test(arguments: ModifierKey.allCases)
    func theKeyAddedToAHeldModifierNeverPresses(key: ModifierKey) {
        var gesture = ModifierGesture(key: key)
        #expect(gesture.flagsChanged(Self.leftShift) == nil)
        #expect(gesture.flagsChanged(Self.alone[key]! | Self.leftShift) == nil)
        #expect(gesture.flagsChanged(Self.alone[key]!) == nil)
        #expect(gesture.flagsChanged(0x100) == nil)
        #expect(gesture.flagsChanged(Self.alone[key]!) == .pressed)
    }

    @Test(arguments: ModifierKey.allCases)
    func theKeyPressedWhileAnotherKeyIsHeldNeverPresses(key: ModifierKey) {
        var gesture = ModifierGesture(key: key)
        #expect(gesture.flagsChanged(Self.alone[key]!, othersHeld: true) == nil)
        #expect(gesture.flagsChanged(0x100) == nil)
        #expect(gesture.flagsChanged(Self.alone[key]!) == .pressed)
    }

    @Test func leftCommandIsNotRightCommand() {
        var gesture = ModifierGesture(key: .rightCommand)
        #expect(gesture.flagsChanged(Self.leftCommand) == nil)
        #expect(gesture.flagsChanged(Self.leftCommand | 0x10) == nil)
        #expect(gesture.flagsChanged(0x100) == nil)
    }

    @Test func capsLockDoesNotCountAsAHeldKey() {
        var gesture = ModifierGesture(key: .rightCommand)
        #expect(gesture.flagsChanged(Self.alone[.rightCommand]! | Self.capsLock) == .pressed)
        #expect(gesture.flagsChanged(Self.capsLock) == .released)
    }

    @Test func aCommandFlagWithoutASideStillCancels() {
        var gesture = ModifierGesture(key: .rightOption)
        #expect(gesture.flagsChanged(Self.alone[.rightOption]!) == .pressed)
        #expect(gesture.flagsChanged(Self.alone[.rightOption]! | 0x10_0000) == .cancelled)
    }

    @Test func sleepCancelsAHeldKey() {
        var gesture = ModifierGesture(key: .function)
        #expect(gesture.flagsChanged(Self.alone[.function]!) == .pressed)
        #expect(gesture.reset() == .cancelled)
        #expect(gesture.flagsChanged(0x100) == nil)
        #expect(gesture.flagsChanged(Self.alone[.function]!) == .pressed)
    }
}
