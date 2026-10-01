import CielCore
import CoreGraphics
import Foundation
import Testing

@Suite
struct LauncherPlacementTests {
    private let screen = CGRect(x: 0, y: 0, width: 1600, height: 1000)

    @Test
    func testSnapAtGuideIntersection() {
        let original = CGRect(x: 495, y: 458, width: 640, height: 68)
        let snap = LauncherPlacement.snap(original, screen: screen, headerHeight: 68)
        #expect(snap.frame == CGRect(x: 480, y: 466, width: 640, height: 68))
        #expect(snap.xGuide == 800)
        #expect(snap.yGuide == 500)
    }

    @Test
    func testFreePlacementAndDistance() {
        let near = CGRect(x: 495, y: 458, width: 640, height: 68)
        let free = LauncherPlacement.snap(near, screen: screen, headerHeight: 68, enabled: false)
        #expect(free.frame == near)
        #expect(free.xGuide == nil)
        #expect(free.yGuide == nil)
        let far = CGRect(x: 530, y: 516, width: 640, height: 68)
        let snap = LauncherPlacement.snap(far, screen: screen, headerHeight: 68)
        #expect(snap.frame == far)
        #expect(snap.xGuide == nil)
        #expect(snap.yGuide == nil)
    }

    @Test
    func testNarrowScreenAndEdges() {
        let narrow = CGRect(x: -1024, y: 50, width: 1024, height: 700)
        let snap = LauncherPlacement.snap(
            CGRect(x: -1088, y: 141, width: 640, height: 68),
            screen: narrow, headerHeight: 68)
        #expect(snap.frame.minX == narrow.minX)
        #expect(snap.xGuide == nil)  // Quarter guide would leave the box outside this display.
        #expect(narrow.contains(snap.frame))
        let outside = LauncherPlacement.snap(
            CGRect(x: 1500, y: -100, width: 640, height: 404),
            screen: screen, headerHeight: 68, enabled: false)
        #expect(outside.frame == CGRect(x: 960, y: 0, width: 640, height: 404))
    }

    @Test
    func testInputAnchorSurvivesResultResizing() {
        let expanded = CGRect(x: 200, y: 100, width: 640, height: 404)
        let placement = LauncherPlacement(frame: expanded, screen: screen, headerHeight: 68)
        let empty = placement.frame(size: CGSize(width: 640, height: 68), screen: screen, headerHeight: 68)
        #expect(abs(empty.minX - expanded.minX) <= 0.001)
        #expect(abs(empty.maxY - expanded.maxY) <= 0.001)
        let reopened = placement.frame(size: expanded.size, screen: screen, headerHeight: 68)
        #expect(abs(reopened.minY - expanded.minY) <= 0.001)
        let low = LauncherPlacement(
            frame: CGRect(x: 200, y: 0, width: 640, height: 68), screen: screen, headerHeight: 68)
        let tall = low.frame(size: expanded.size, screen: screen, headerHeight: 68)
        #expect(screen.contains(tall))
        #expect(low.frame(size: empty.size, screen: screen, headerHeight: 68).minY == 0)
    }

    @Test
    func testDisplayChangeAndPersistence() {
        let suite = "ciel.placement.test." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let original = CGRect(x: 300, y: 600, width: 640, height: 68)
        let placement = LauncherPlacement(frame: original, screen: screen, headerHeight: 68)
        let store = LauncherPlacementStore(defaults: defaults)
        store.save(placement, for: "display-A")
        let other = LauncherPlacement(
            frame: CGRect(x: 700, y: 100, width: 640, height: 68), screen: screen, headerHeight: 68)
        store.save(other, for: "display-B")
        let reopened = LauncherPlacementStore(defaults: UserDefaults(suiteName: suite)!)
        #expect(reopened.placement(for: "display-A") == placement)
        #expect(reopened.placement(for: "display-B") == other)
        #expect(reopened.placement(for: "unknown-display") == nil)
        let resized = CGRect(x: -1200, y: -200, width: 1200, height: 800)
        #expect(resized.contains(placement.frame(size: original.size, screen: resized, headerHeight: 68)))
    }

    @Test
    func testInvalidSavedPlacementFallsBack() {
        let suite = "ciel.placement.test." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(
            Data("{\"display\":{\"horizontal\":5,\"vertical\":0.5}}".utf8), forKey: "launcher.placements")
        #expect(LauncherPlacementStore(defaults: defaults).placement(for: "display") == nil)
        defaults.set(Data("invalid".utf8), forKey: "launcher.placements")
        #expect(LauncherPlacementStore(defaults: defaults).placement(for: "display") == nil)
    }
}
