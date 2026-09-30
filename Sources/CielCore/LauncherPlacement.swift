import CoreGraphics
import Foundation

/// Store the input's top edge as a relative position, independently of result height.
public struct LauncherPlacement: Codable, Equatable {
    public let horizontal: CGFloat
    public let vertical: CGFloat

    public init(frame: CGRect, screen: CGRect, headerHeight: CGFloat) {
        horizontal = Self.fraction(frame.minX - screen.minX, span: screen.width - frame.width)
        vertical = Self.fraction(screen.maxY - frame.maxY, span: screen.height - headerHeight)
    }

    public func frame(size: CGSize, screen: CGRect, headerHeight: CGFloat) -> CGRect {
        let anchor = CGPoint(
            x: screen.minX + horizontal * max(0, screen.width - size.width),
            y: screen.maxY - vertical * max(0, screen.height - headerHeight))
        return Self.frame(anchor: anchor, size: size, screen: screen)
    }

    public static func frame(anchor: CGPoint, size: CGSize, screen: CGRect) -> CGRect {
        CGRect(
            x: max(screen.minX, min(anchor.x, screen.maxX - size.width)),
            y: max(screen.minY, min(anchor.y - size.height, screen.maxY - size.height)),
            width: size.width, height: size.height)
    }

    public static let guideFractions: [CGFloat] = [0.25, 0.5, 0.75]

    public static func snap(
        _ frame: CGRect, screen: CGRect, headerHeight: CGFloat,
        enabled: Bool = true, distance: CGFloat = 24
    ) -> LauncherSnap {
        var anchor = CGPoint(x: frame.minX, y: frame.maxY)
        var xGuide: CGFloat?
        var yGuide: CGFloat?
        if enabled {
            let xs = guideFractions.map { screen.minX + screen.width * $0 }.filter {
                $0 - frame.width / 2 >= screen.minX && $0 + frame.width / 2 <= screen.maxX
            }
            let ys = guideFractions.map { screen.minY + screen.height * $0 }.filter {
                $0 + headerHeight / 2 <= screen.maxY && $0 + headerHeight / 2 - frame.height >= screen.minY
            }
            if let x = xs.min(by: { abs($0 - frame.midX) < abs($1 - frame.midX) }),
                abs(x - frame.midX) <= distance
            {
                anchor.x = x - frame.width / 2
                xGuide = x
            }
            let inputCenter = frame.maxY - headerHeight / 2
            if let y = ys.min(by: { abs($0 - inputCenter) < abs($1 - inputCenter) }),
                abs(y - inputCenter) <= distance
            {
                anchor.y = y + headerHeight / 2
                yGuide = y
            }
        }
        return LauncherSnap(
            frame: Self.frame(anchor: anchor, size: frame.size, screen: screen),
            xGuide: xGuide, yGuide: yGuide)
    }

    private static func fraction(_ value: CGFloat, span: CGFloat) -> CGFloat {
        span > 0 ? max(0, min(1, value / span)) : 0
    }
}

public struct LauncherSnap {
    public let frame: CGRect
    public let xGuide: CGFloat?
    public let yGuide: CGFloat?
}

public final class LauncherPlacementStore {
    private let defaults: UserDefaults
    private let key = "launcher.placements"
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func placement(for display: String) -> LauncherPlacement? {
        guard let data = defaults.data(forKey: key),
            let saved = try? JSONDecoder().decode([String: LauncherPlacement].self, from: data),
            let value = saved[display], value.horizontal.isFinite, value.vertical.isFinite,
            (0...1).contains(value.horizontal), (0...1).contains(value.vertical)
        else { return nil }
        return value
    }

    public func save(_ value: LauncherPlacement, for display: String) {
        var saved =
            defaults.data(forKey: key).flatMap {
                try? JSONDecoder().decode([String: LauncherPlacement].self, from: $0)
            } ?? [:]
        saved[display] = value
        if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: key) }
    }
}
