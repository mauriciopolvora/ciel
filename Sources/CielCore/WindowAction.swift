import CoreGraphics
import Foundation

public enum WindowAction: String, CaseIterable, Codable, Sendable {
    case leftHalf, rightHalf, centerTwoThirds, firstThreeFourths, lastThreeFourths
    case maximize, almostMaximize, center, nextDisplay, previousDisplay, restore
    case topHalf, bottomHalf, topLeft, topRight, bottomLeft, bottomRight, minimize

    public var title: String {
        switch self {
        case .leftHalf: return "Left Half"
        case .rightHalf: return "Right Half"
        case .centerTwoThirds: return "Center Two Thirds"
        case .firstThreeFourths: return "First Three Fourths"
        case .lastThreeFourths: return "Last Three Fourths"
        case .maximize: return "Maximize"
        case .almostMaximize: return "Almost Maximize"
        case .center: return "Center"
        case .nextDisplay: return "Move to Next Display"
        case .previousDisplay: return "Move to Previous Display"
        case .restore: return "Restore Previous Size"
        case .topHalf: return "Top Half"
        case .bottomHalf: return "Bottom Half"
        case .topLeft: return "Top Left Quarter"
        case .topRight: return "Top Right Quarter"
        case .bottomLeft: return "Bottom Left Quarter"
        case .bottomRight: return "Bottom Right Quarter"
        case .minimize: return "Minimize"
        }
    }

    public var keywords: String {
        switch self {
        case .maximize: return "full fill expand window"
        case .almostMaximize: return "large expand padding window"
        case .nextDisplay, .previousDisplay: return "monitor screen move window"
        case .restore: return "undo reset previous window"
        case .minimize: return "minimise hide dock window"
        default: return "snap tile resize move window " + title
        }
    }

    /// Normalized geometry uses top-left coordinates, as Accessibility does.
    public var unitRect: CGRect? {
        switch self {
        case .leftHalf: return CGRect(x: 0, y: 0, width: 0.5, height: 1)
        case .rightHalf: return CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        case .centerTwoThirds: return CGRect(x: 1.0 / 6, y: 0, width: 2.0 / 3, height: 1)
        case .firstThreeFourths: return CGRect(x: 0, y: 0, width: 0.75, height: 1)
        case .lastThreeFourths: return CGRect(x: 0.25, y: 0, width: 0.75, height: 1)
        case .maximize: return CGRect(x: 0, y: 0, width: 1, height: 1)
        case .almostMaximize: return CGRect(x: 0.05, y: 0.05, width: 0.9, height: 0.9)
        case .topHalf: return CGRect(x: 0, y: 0, width: 1, height: 0.5)
        case .bottomHalf: return CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
        case .topLeft: return CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        case .topRight: return CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
        case .bottomLeft: return CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)
        case .bottomRight: return CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
        default: return nil
        }
    }

    public func frame(in visible: CGRect, current: CGRect) -> CGRect {
        if self == .minimize { return current }
        guard let unit = unitRect else {
            let size = CGSize(
                width: min(current.width, visible.width), height: min(current.height, visible.height))
            return CGRect(
                x: (visible.midX - size.width / 2).rounded(), y: (visible.midY - size.height / 2).rounded(),
                width: size.width, height: size.height)
        }
        // Round shared boundaries, not independent widths, to avoid seams.
        let x = (visible.minX + unit.minX * visible.width).rounded()
        let y = (visible.minY + unit.minY * visible.height).rounded()
        let maxX = (visible.minX + unit.maxX * visible.width).rounded()
        let maxY = (visible.minY + unit.maxY * visible.height).rounded()
        return CGRect(x: x, y: y, width: maxX - x, height: maxY - y)
    }
}

public enum WindowGeometry {
    public static func accessibilityRect(_ appKit: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: appKit.minX, y: primaryHeight - appKit.maxY, width: appKit.width, height: appKit.height)
    }

    public static func displayIndex(for window: CGRect, displays: [CGRect]) -> Int? {
        guard !displays.isEmpty else { return nil }
        return displays.indices.max { a, b in
            let aRect = window.intersection(displays[a])
            let bRect = window.intersection(displays[b])
            let areaA = aRect.isNull ? 0 : aRect.width * aRect.height
            let areaB = bRect.isNull ? 0 : bRect.width * bRect.height
            if areaA != areaB { return areaA < areaB }
            let da = hypot(window.midX - displays[a].midX, window.midY - displays[a].midY)
            let db = hypot(window.midX - displays[b].midX, window.midY - displays[b].midY)
            return da > db
        }
    }

    public static func move(_ frame: CGRect, from source: CGRect, to target: CGRect) -> CGRect {
        guard source.width > 0, source.height > 0 else { return target }
        let width = min(target.width, frame.width / source.width * target.width)
        let height = min(target.height, frame.height / source.height * target.height)
        let x = target.minX + (frame.minX - source.minX) / source.width * target.width
        let y = target.minY + (frame.minY - source.minY) / source.height * target.height
        return CGRect(
            x: min(max(x, target.minX), target.maxX - width),
            y: min(max(y, target.minY), target.maxY - height), width: width, height: height
        ).integral
    }
}
