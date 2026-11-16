import AppKit

/// Type, metrics and motion for one launcher design. Every design keeps the 68 pt header, since saved placements
/// anchor to it, and opens, filters and moves the selection without animation.
@MainActor struct LauncherStyle {
    enum Selection { case inverse, raised, bar }

    let design: LauncherDesign
    let dark: Bool
    let palette: LauncherPalette
    let queryFont: NSFont
    let queryX: CGFloat
    let queryHeight: CGFloat
    let scopeFont: NSFont
    let scopeTint: NSColor
    let titleFont: NSFont
    let hintFont: NSFont
    let noMatchFont: NSFont
    let noMatchDetailFont: NSFont
    let noMatchAlignment: NSTextAlignment
    let panelRadius: CGFloat
    let dividerInset: CGFloat?
    let topGap: CGFloat
    let bottomPad: CGFloat
    let noMatchHeight: CGFloat
    let rowHeight: CGFloat
    let rowInset: CGFloat
    let rowRadius: CGFloat
    let iconSize: CGFloat
    let visibleRows: Int
    let selection: Selection
    let hoverDuration: CFTimeInterval

    static func make(_ design: LauncherDesign, systemDark: Bool) -> LauncherStyle {
        let contrast = Theme.increaseContrast
        switch design {
        case .a:
            let palette = LauncherPalette.inverse
            return LauncherStyle(
                design: design, dark: true, palette: contrast ? palette.contrasted(dark: true) : palette,
                queryFont: .systemFont(ofSize: 24), queryX: 24, queryHeight: 32,
                scopeFont: .systemFont(ofSize: 12, weight: .medium), scopeTint: Theme.accent,
                titleFont: .systemFont(ofSize: 15, weight: .medium),
                hintFont: .systemFont(ofSize: 12, weight: .medium),
                noMatchFont: .systemFont(ofSize: 15, weight: .medium),
                noMatchDetailFont: .systemFont(ofSize: 13),
                noMatchAlignment: .center, panelRadius: Theme.panelRadius, dividerInset: nil, topGap: 0,
                bottomPad: 8, noMatchHeight: 72, rowHeight: Theme.rowHeight, rowInset: 8,
                rowRadius: Theme.rowRadius, iconSize: 28, visibleRows: 7, selection: .inverse,
                hoverDuration: Theme.hoverDuration)
        case .b:
            let palette = systemDark ? LauncherPalette.graphiteDark : .graphiteLight
            return LauncherStyle(
                design: design, dark: systemDark,
                palette: contrast ? palette.contrasted(dark: systemDark) : palette,
                queryFont: rounded(22), queryX: 24, queryHeight: 30, scopeFont: rounded(12, .medium),
                scopeTint: palette.title, titleFont: rounded(15), hintFont: rounded(12, .medium),
                noMatchFont: rounded(15, .medium), noMatchDetailFont: rounded(13), noMatchAlignment: .center,
                panelRadius: 18, dividerInset: 20, topGap: 6, bottomPad: 8, noMatchHeight: 78, rowHeight: 48,
                rowInset: 10, rowRadius: 10, iconSize: 30, visibleRows: 7, selection: .raised,
                hoverDuration: 0.15)
        case .c:
            let palette = LauncherPalette.console
            return LauncherStyle(
                design: design, dark: true, palette: contrast ? palette.contrasted(dark: true) : palette,
                queryFont: .monospacedSystemFont(ofSize: 18, weight: .regular), queryX: 18, queryHeight: 24,
                scopeFont: .monospacedSystemFont(ofSize: 11, weight: .medium), scopeTint: palette.title,
                titleFont: .monospacedSystemFont(ofSize: 13, weight: .regular),
                hintFont: .monospacedSystemFont(ofSize: 11, weight: .regular),
                noMatchFont: .monospacedSystemFont(ofSize: 13, weight: .medium),
                noMatchDetailFont: .monospacedSystemFont(ofSize: 12, weight: .regular),
                noMatchAlignment: .left, panelRadius: 10, dividerInset: 0, topGap: 4, bottomPad: 6,
                noMatchHeight: 76, rowHeight: 34, rowInset: 6, rowRadius: 5, iconSize: 18, visibleRows: 9,
                selection: .bar, hoverDuration: 0)
        }
    }

    /// The panel height: the header alone with no query, a short message with no results, and up to `visibleRows`
    /// rows plus half a row that shows the list scrolls.
    func height(results: Int, hasQuery: Bool) -> CGFloat {
        guard hasQuery else { return LauncherView.initialHeight }
        guard results > 0 else { return LauncherView.initialHeight + noMatchHeight }
        let rows = CGFloat(min(results, visibleRows)) * rowHeight
        let peek = results > visibleRows ? (rowHeight / 2).rounded(.down) - 2 : 0
        return LauncherView.initialHeight + topGap + rows + bottomPad + peek
    }

    private static func rounded(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        return font.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? font
    }
}
