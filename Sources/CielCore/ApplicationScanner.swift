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
                // Read fresh metadata. Bundle caches Info.plist and can hide an app update.
                let infoURL = url.appendingPathComponent("Contents/Info.plist")
                guard let data = try? Data(contentsOf: infoURL),
                    let info = try? PropertyListSerialization.propertyList(from: data, format: nil)
                        as? [String: Any],
                    let id = info["CFBundleIdentifier"] as? String,
                    info["LSBackgroundOnly"] as? Bool != true,
                    id != identifier, seen.insert(id).inserted
                else { return }
                let name =
                    (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                entries.append(
                    SearchEntry(
                        id: "app." + id, title: name, subtitle: "Application",
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
