import AppKit
import Carbon
import Testing

@testable import CielApp

@MainActor @Suite
struct OnboardingTests {
    private let optionCommandSpace = Shortcut(
        keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey | optionKey))
    private let shiftCommandSpace = Shortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey | shiftKey))

    @Test func spotlightKeepsItsShippedShortcutsUntilTheyAreChanged() {
        let shipped = SpotlightShortcuts { nil }
        #expect(shipped.active.count == 2)
        #expect(shipped.owns(SpotlightShortcuts.commandSpace) && shipped.owns(optionCommandSpace))
        let changed = SpotlightShortcuts {
            [
                "64": [
                    "enabled": true,
                    "value": ["parameters": [32, 49, 1 << 20 | 1 << 17], "type": "standard"],
                ],
                "65": ["enabled": false],
            ]
        }
        #expect(changed.active.map(\.shortcut) == [shiftCommandSpace])
        #expect(!changed.owns(SpotlightShortcuts.commandSpace))
    }

    @Test func aShortcutSpotlightHoldsIsSavedOnlyAfterSpotlightLetsGo() {
        withOnboarding { onboarding, hotKeys, system in
            onboarding.spotlightGuide.choose(SpotlightShortcuts.commandSpace)
            #expect(hotKeys.shortcut(for: .launcher) == .launcher)
            #expect(onboarding.spotlightGuide.held == SpotlightShortcuts.commandSpace)
            #expect(system.opened == [SpotlightShortcuts.keyboardSettings])
            onboarding.tick()
            #expect(hotKeys.shortcut(for: .launcher) == .launcher)
            system.symbolicHotKeys = ["64": ["enabled": false]]
            onboarding.tick()
            #expect(hotKeys.shortcut(for: .launcher) == SpotlightShortcuts.commandSpace)
            #expect(onboarding.spotlightGuide.held == nil)
        }
    }

    @Test func aFreeShortcutIsSavedAtOnce() {
        withOnboarding { onboarding, hotKeys, system in
            onboarding.spotlightGuide.choose(shiftCommandSpace)
            #expect(hotKeys.shortcut(for: .launcher) == shiftCommandSpace)
            #expect(onboarding.spotlightGuide.held == nil)
            #expect(system.opened.isEmpty)
        }
    }

    @Test func grantingAccessFinishesOnboarding() {
        withOnboarding { onboarding, _, system in
            var finished = false
            onboarding.onFinish = { finished = true }
            onboarding.show(.access)
            onboarding.tick()
            #expect(!finished)
            system.trusted = true
            onboarding.tick()
            #expect(finished)
            #expect(!onboarding.helper.isShown)
        }
    }

    @Test func theDragCardCarriesTheAppBundle() {
        let item = DragCard(frame: NSRect(origin: .zero, size: DragCard.size)).draggingItem()
        #expect((item.item as? NSURL) as URL? == Bundle.main.bundleURL)
    }

    private func withOnboarding(_ body: (OnboardingController, HotKeys, FakeSystem) -> Void) {
        withEmptyDefaults { defaults in
            let system = FakeSystem()
            let hotKeys = HotKeys(
                defaults: defaults, registrar: FakeHotKeyRegistrar(), onPress: { _ in }, onChange: {})
            let onboarding = OnboardingController(
                hotKeys: hotKeys, spotlight: SpotlightShortcuts { system.symbolicHotKeys },
                isTrusted: { system.trusted }, open: { system.opened.append($0) })
            body(onboarding, hotKeys, system)
        }
    }
}

@MainActor final class FakeSystem {
    var symbolicHotKeys: [String: Any]?
    var trusted = false
    var opened: [URL] = []
}
