enum ModifierKey: UInt32, CaseIterable, Sendable {
    case rightCommand = 54
    case rightOption = 61
    case function = 63

    var display: String {
        switch self {
        case .rightCommand: "Right ⌘"
        case .rightOption: "Right ⌥"
        case .function: "fn"
        }
    }

    var flag: UInt {
        switch self {
        case .rightCommand: 0x10
        case .rightOption: 0x40
        case .function: 0x80_0000
        }
    }
}

struct ModifierGesture: Sendable {
    private enum State { case up, down, interrupted }

    let key: ModifierKey
    private var state = State.up

    init(key: ModifierKey) { self.key = key }

    mutating func flagsChanged(_ flags: UInt, othersHeld: Bool = false) -> HotKeyEvent? {
        let held = Self.heldKeys(flags)
        let isDown = held & key.flag != 0
        let isAlone = held == key.flag
        switch state {
        case .up:
            if isAlone, !othersHeld {
                state = .down
                return .pressed
            }
            if isDown { state = .interrupted }
        case .down:
            if !isDown {
                state = .up
                return .released
            }
            if !isAlone {
                state = .interrupted
                return .cancelled
            }
        case .interrupted:
            if !isDown { state = .up }
        }
        return nil
    }

    mutating func interrupt() -> HotKeyEvent? {
        guard state == .down else { return nil }
        state = .interrupted
        return .cancelled
    }

    mutating func reset() -> HotKeyEvent? {
        defer { state = .up }
        return state == .down ? .cancelled : nil
    }

    private static let sides: [(either: UInt, left: UInt, right: UInt)] = [
        (0x2_0000, 0x02, 0x04), (0x4_0000, 0x01, 0x2000), (0x8_0000, 0x20, 0x40), (0x10_0000, 0x08, 0x10),
    ]

    /// Events posted by software can carry Shift, Control, Option or Command without a side, so a
    /// side-less flag still counts as a held key.
    private static func heldKeys(_ flags: UInt) -> UInt {
        var held = flags & ModifierKey.function.flag
        for side in sides where flags & side.either != 0 {
            let sided = flags & (side.left | side.right)
            held |= sided == 0 ? side.either : sided
        }
        return held
    }
}
