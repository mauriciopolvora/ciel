import AppKit

enum LaunchMode: Equatable {
    case app
    case appCheck(AppCheck)
    case processCheck(ProcessCheck)

    static func resolve(arguments: [String], bundleIdentifier: String?) -> Result<LaunchMode, LaunchError> {
        guard let mode = LaunchMode(arguments: arguments) else {
            return .failure(.unknownArguments(arguments.drop { !$0.hasPrefix("--") }.joined(separator: " ")))
        }
        switch mode {
        case .app:
            return .success(mode)
        case .appCheck, .processCheck:
            guard bundleIdentifier == AppIdentity.checksBundleIdentifier else {
                return .failure(.wrongIdentity(bundleIdentifier ?? "an unbundled executable"))
            }
            return .success(mode)
        }
    }

    init?(arguments: [String]) {
        let flags = Array(arguments.drop { !$0.hasPrefix("--") })
        switch (flags.first, flags.count) {
        case (nil, _): self = .app
        case ("--ui-test", 1): self = .appCheck(.launcher)
        case ("--smoke-test", 1): self = .appCheck(.smoke)
        case ("--performance-test", 1): self = .appCheck(.performance)
        case ("--catalog-test", 1): self = .processCheck(.catalog)
        case ("--window-test", 1): self = .processCheck(.window)
        case ("--window-fixture", 2): self = .processCheck(.fixture(output: flags[1], minimumSize: false))
        case ("--window-fixture-minimum-size", 2):
            self = .processCheck(.fixture(output: flags[1], minimumSize: true))
        default: return nil
        }
    }

    var arguments: [String] {
        switch self {
        case .app: []
        case .appCheck(.launcher): ["--ui-test"]
        case .appCheck(.smoke): ["--smoke-test"]
        case .appCheck(.performance): ["--performance-test"]
        case .processCheck(.catalog): ["--catalog-test"]
        case .processCheck(.window): ["--window-test"]
        case .processCheck(.fixture(let output, minimumSize: false)): ["--window-fixture", output]
        case .processCheck(.fixture(let output, minimumSize: true)):
            ["--window-fixture-minimum-size", output]
        }
    }
}

enum LaunchError: Error, Equatable, CustomStringConvertible {
    case unknownArguments(String)
    case wrongIdentity(String)

    var description: String {
        switch self {
        case .unknownArguments(let arguments):
            "Ciel does not recognize \(arguments). Run native checks with bash scripts/check.sh."
        case .wrongIdentity(let identifier):
            "Native checks run only as \(AppIdentity.checksBundleIdentifier), not \(identifier). Run them with bash scripts/check.sh."
        }
    }
}

enum AppCheck: Equatable {
    case launcher, smoke, performance

    @MainActor func run(_ app: CheckHandles) {
        switch self {
        case .launcher:
            LauncherCheck.run(launcher: app.launcher, panel: app.panel, entries: app.catalog.entries)
        case .smoke:
            SmokeCheck.run(
                launcher: app.launcher, fieldEditor: app.fieldEditor, catalog: app.catalog,
                hotKeys: app.hotKeys,
                menu: app.menu, showSettings: app.showSettings, windowShortcuts: app.windowShortcuts,
                showGuide: app.showGuide)
        case .performance:
            PerformanceCheck.run(
                launcher: app.launcher, panel: app.panel,
                startupMilliseconds: AppPerformance.startupMilliseconds)
        }
    }
}

enum ProcessCheck: Equatable {
    case catalog, window
    case fixture(output: String, minimumSize: Bool)

    @MainActor func start() -> AnyObject {
        switch self {
        case .catalog:
            let check = CatalogCheck()
            check.run()
            return check
        case .window:
            let check = IntegrationCheck()
            check.run()
            return check
        case .fixture(let output, let minimumSize):
            let fixture = WindowFixture(output: output, minimumSize: minimumSize)
            fixture.run()
            return fixture
        }
    }
}
