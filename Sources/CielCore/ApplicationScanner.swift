import Foundation

public enum ApplicationScanner {
    public static var defaultRoots: [URL] {
        [
            "/Applications", NSHomeDirectory() + "/Applications", "/System/Applications",
            "/System/Library/CoreServices/Applications", "/System/Library/CoreServices/Finder.app",
            "/System/Cryptexes/App/System/Applications",
        ].map { URL(fileURLWithPath: $0) }
    }

    public static func scan(roots: [URL] = defaultRoots, excluding identifier: String? = nil) -> [SearchEntry]
    {
        let fm = FileManager.default
        var entries: [SearchEntry] = []
        var seen = Set<String>()
        func visit(_ url: URL, depth: Int) {
            guard depth <= 5 else { return }
            if url.pathExtension.lowercased() == "app" {
                guard let bundle = BundleInfo(appAt: url), bundle.isUserFacing,
                    bundle.identifier != identifier, seen.insert(bundle.identifier).inserted
                else { return }
                entries.append(
                    SearchEntry(
                        id: "app." + bundle.identifier, title: bundle.displayName, subtitle: "Application",
                        kind: .application, path: url.path,
                        keywords: url.deletingPathExtension().lastPathComponent))
                return
            }
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                values.isDirectory == true, values.isSymbolicLink != true
            else { return }
            let children =
                (try? fm.contentsOfDirectory(
                    at: url, includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles])) ?? []
            for child in children.sorted(by: { $0.path < $1.path }) { visit(child, depth: depth + 1) }
        }
        for root in roots { visit(root, depth: 0) }
        return entries.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
}

struct BundleInfo {
    let identifier: String
    let displayName: String
    let isBackgroundOnly: Bool
    let isMenuBarApp: Bool

    /// Launch Services treats a menu bar app as visible even when it is also background-only.
    var isUserFacing: Bool { !isBackgroundOnly || isMenuBarApp }

    init?(appAt url: URL) {
        // Read fresh metadata. Bundle caches Info.plist and can hide an app update.
        guard let data = try? Data(contentsOf: url.appendingPathComponent("Contents/Info.plist")),
            let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let identifier = info["CFBundleIdentifier"] as? String
        else { return nil }
        self.identifier = identifier
        displayName =
            info["CFBundleDisplayName"] as? String ?? info["CFBundleName"] as? String
            ?? url.deletingPathExtension().lastPathComponent
        isBackgroundOnly = Self.flag(info["LSBackgroundOnly"])
        isMenuBarApp = Self.flag(info["LSUIElement"])
    }

    /// Launch Services accepts Bool, number, and string flags ("1", "YES", "true") and reads them as `boolValue` does.
    private static func flag(_ value: Any?) -> Bool {
        switch value {
        case let number as NSNumber: number.boolValue
        case let string as String: (string as NSString).boolValue
        default: false
        }
    }
}
