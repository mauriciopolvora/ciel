import CielCore
import CoreGraphics
import Foundation

final class LauncherPlacementTests {
    private let screen = CGRect(x: 0, y: 0, width: 1600, height: 1000)

    func testSnapAtGuideIntersection() throws {
        let original = CGRect(x: 495, y: 458, width: 640, height: 68)
        let snap = LauncherPlacement.snap(original, screen: screen, headerHeight: 68)
        try expectEqual(snap.frame, CGRect(x: 480, y: 466, width: 640, height: 68))
        try expectEqual(snap.xGuide, 800)
        try expectEqual(snap.yGuide, 500)
    }

    func testFreePlacementAndDistance() throws {
        let near = CGRect(x: 495, y: 458, width: 640, height: 68)
        let free = LauncherPlacement.snap(near, screen: screen, headerHeight: 68, enabled: false)
        try expectEqual(free.frame, near)
        try expectNil(free.xGuide)
        try expectNil(free.yGuide)
        let far = CGRect(x: 530, y: 516, width: 640, height: 68)
        let snap = LauncherPlacement.snap(far, screen: screen, headerHeight: 68)
        try expectEqual(snap.frame, far)
        try expectNil(snap.xGuide)
        try expectNil(snap.yGuide)
    }

    func testNarrowScreenAndEdges() throws {
        let narrow = CGRect(x: -1024, y: 50, width: 1024, height: 700)
        let snap = LauncherPlacement.snap(
            CGRect(x: -1088, y: 141, width: 640, height: 68),
            screen: narrow, headerHeight: 68)
        try expectEqual(snap.frame.minX, narrow.minX)
        try expectNil(snap.xGuide)  // Quarter guide would leave the box outside this display.
        try expectTrue(narrow.contains(snap.frame))
        let outside = LauncherPlacement.snap(
            CGRect(x: 1500, y: -100, width: 640, height: 404),
            screen: screen, headerHeight: 68, enabled: false)
        try expectEqual(outside.frame, CGRect(x: 960, y: 0, width: 640, height: 404))
    }

    func testInputAnchorSurvivesResultResizing() throws {
        let expanded = CGRect(x: 200, y: 100, width: 640, height: 404)
        let placement = LauncherPlacement(frame: expanded, screen: screen, headerHeight: 68)
        let empty = placement.frame(size: CGSize(width: 640, height: 68), screen: screen, headerHeight: 68)
        try expectEqual(empty.minX, expanded.minX, accuracy: 0.001)
        try expectEqual(empty.maxY, expanded.maxY, accuracy: 0.001)
        let reopened = placement.frame(size: expanded.size, screen: screen, headerHeight: 68)
        try expectEqual(reopened.minY, expanded.minY, accuracy: 0.001)
        let low = LauncherPlacement(
            frame: CGRect(x: 200, y: 0, width: 640, height: 68), screen: screen, headerHeight: 68)
        let tall = low.frame(size: expanded.size, screen: screen, headerHeight: 68)
        try expectTrue(screen.contains(tall))
        try expectEqual(low.frame(size: empty.size, screen: screen, headerHeight: 68).minY, 0)
    }

    func testDisplayChangeAndPersistence() throws {
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
        try expectEqual(reopened.placement(for: "display-A"), placement)
        try expectEqual(reopened.placement(for: "display-B"), other)
        try expectNil(reopened.placement(for: "unknown-display"))
        let resized = CGRect(x: -1200, y: -200, width: 1200, height: 800)
        try expectTrue(
            resized.contains(placement.frame(size: original.size, screen: resized, headerHeight: 68)))
    }

    func testInvalidSavedPlacementFallsBack() throws {
        let suite = "ciel.placement.test." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(
            Data("{\"display\":{\"horizontal\":5,\"vertical\":0.5}}".utf8), forKey: "launcher.placements")
        try expectNil(LauncherPlacementStore(defaults: defaults).placement(for: "display"))
        defaults.set(Data("invalid".utf8), forKey: "launcher.placements")
        try expectNil(LauncherPlacementStore(defaults: defaults).placement(for: "display"))
    }
}
