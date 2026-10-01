import AppKit
import CielCore

// Exercise real FSEvents without changing the user's application folders.
@MainActor
final class CatalogCheck {
    private var catalog: AppCatalog?
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "ciel-events-" + UUID().uuidString)
    private var phase = 0
    private var finished = false
    private var publicationCount = 0
    private var invalidatedPaths: Set<String> = []
    private var iconWriteStarted = false
    private var app: URL { root.appendingPathComponent("Nested/Menu Tool.app") }
    func run() {
        do { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) } catch {
            finish(false, "Create fixture: \(error)")
            return
        }
        catalog = AppCatalog(roots: [root], useCache: false)
        catalog?.onChange = { [weak self] in self?.publicationCount += 1 }
        catalog?.onIconsInvalidated = { [weak self] paths in self?.invalidatedPaths.formUnion(paths) }
        catalog?.onRefreshFinished = { [weak self] in self?.changed() }
        catalog?.refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 18) { [weak self] in
            guard let self else { return }
            self.finish(
                false,
                "Watcher timed out at phase \(self.phase): entry paths \(self.catalog?.entries.compactMap(\.path) ?? []), icon paths \(self.invalidatedPaths.sorted())"
            )
        }
    }
    private func write(_ name: String) throws {
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": "ciel.test.menu", "CFBundleName": name, "LSUIElement": true,
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"), options: .atomic)
    }
    private func changed() {
        guard !finished, let entries = catalog?.entries else { return }
        do {
            switch phase {
            case 0:
                guard entries.isEmpty, publicationCount == 0 else {
                    finish(false, "An unchanged empty scan published a catalog change")
                    return
                }
                print("PASS initial empty scan completion without a catalog change")
                phase = 1
                // FSEventStreamStart connects asynchronously to the filesystem daemon.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                    do { try self?.write("Menu Tool") } catch { self?.finish(false, "Fixture: \(error)") }
                }
            case 1:
                guard entries.first?.title == "Menu Tool" else { return }
                print("PASS automatic nested app discovery, including menu-bar apps")
                phase = 2
                try write("Renamed Tool")
            case 2:
                guard entries.first?.title == "Renamed Tool" else { return }
                print("PASS automatic Info.plist update")
                phase = 3
                // Let prior metadata events finish before changing only an icon resource.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                    guard let self else { return }
                    do {
                        self.invalidatedPaths = []
                        self.iconWriteStarted = true
                        let resources = self.app.appendingPathComponent("Contents/Resources")
                        try FileManager.default.createDirectory(
                            at: resources, withIntermediateDirectories: true)
                        try Data([0, 1, 2]).write(to: resources.appendingPathComponent("Fixture.icns"))
                    } catch { self.finish(false, "Icon fixture: \(error)") }
                }
            case 3:
                // Directory enumeration can return /private/var while the fixture URL
                // uses /var. Assert the key that result cells send to the icon cache.
                guard iconWriteStarted, let appPath = entries.first?.path,
                    invalidatedPaths.contains(appPath)
                else { return }
                guard entries.first?.title == "Renamed Tool", publicationCount == 2 else {
                    finish(false, "An icon-only event published an unchanged catalog")
                    return
                }
                print("PASS icon resource invalidation without a catalog change")
                phase = 4
                try FileManager.default.removeItem(at: app)
            case 4:
                guard entries.isEmpty else { return }
                print("PASS automatic app removal")
                finish(true, "5 filesystem event checks passed")
            default: break
            }
        } catch { finish(false, "Fixture: \(error)") }
    }
    private func finish(_ success: Bool, _ message: String) {
        guard !finished else { return }
        finished = true
        catalog = nil
        try? FileManager.default.removeItem(at: root)
        print(message)
        exit(success ? 0 : 1)
    }
}
