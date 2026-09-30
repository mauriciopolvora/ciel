import AppKit
import CielCore

// Exercise real FSEvents without changing the user's application folders.
final class CatalogCheck {
    private var catalog: AppCatalog?
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "ciel-events-" + UUID().uuidString)
    private var phase = 0
    private var finished = false
    private var app: URL { root.appendingPathComponent("Nested/Menu Tool.app") }
    func run() {
        do { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) } catch {
            finish(false, "Create fixture: \(error)")
            return
        }
        catalog = AppCatalog(roots: [root], useCache: false)
        catalog?.onChange = { [weak self] in self?.changed() }
        catalog?.refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            self?.finish(false, "Watcher timed out")
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
                guard entries.isEmpty else {
                    finish(false, "Fixture was not empty")
                    return
                }
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
                try FileManager.default.removeItem(at: app)
            case 3:
                guard entries.isEmpty else { return }
                print("PASS automatic app removal")
                finish(true, "3 filesystem event checks passed")
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
