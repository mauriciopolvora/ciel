import Foundation
import Testing

@testable import CielApp

@Suite("Launch arguments and the checks identity")
struct LaunchModeTests {
    private static let executable = "/Applications/Ciel.app/Contents/MacOS/Ciel"
    private static let everyMode: [LaunchMode] = [
        .app, .appCheck(.launcher), .appCheck(.smoke), .appCheck(.performance), .processCheck(.catalog),
        .processCheck(.window), .processCheck(.fixture(output: "/tmp/ciel check", minimumSize: false)),
        .processCheck(.fixture(output: "/tmp/ciel check/minimum", minimumSize: true)),
    ]
    private static let checkScriptFlags: [(String, LaunchMode)] = [
        ("--ui-test", .appCheck(.launcher)), ("--smoke-test", .appCheck(.smoke)),
        ("--performance-test", .appCheck(.performance)), ("--catalog-test", .processCheck(.catalog)),
        ("--window-test", .processCheck(.window)),
    ]

    @Test(arguments: checkScriptFlags)
    func checkScriptFlagsRunTheirCheckInTheChecksBundle(flag: String, mode: LaunchMode) throws {
        let resolved = LaunchMode.resolve(
            arguments: [Self.executable, flag], bundleIdentifier: try checksBundleIdentifier())
        #expect(resolved == .success(mode))
    }

    @Test(arguments: [[], ["-NSDocumentRevisionsDebugMode", "YES"], ["-psn_0_12345"]])
    func noDoubleDashArgumentLaunchesTheApp(arguments: [String]) {
        #expect(
            LaunchMode.resolve(
                arguments: [Self.executable] + arguments, bundleIdentifier: AppIdentity.bundleIdentifier)
                == .success(.app))
    }

    @Test(arguments: everyMode)
    func everyModeParsesBackFromItsOwnArguments(mode: LaunchMode) {
        #expect(LaunchMode(arguments: [Self.executable] + mode.arguments) == mode)
    }

    @Test(arguments: [
        ["--ui-tset"], ["--window-test", "--smoke-test"], ["--ui-test", "extra"], ["--window-fixture"],
        ["--window-fixture", "/tmp/out", "--window-fixture-minimum"], ["-NSFoo", "YES", "--catalog"],
    ])
    func unknownArgumentsNeverLaunchTheApp(arguments: [String]) throws {
        for identifier in [AppIdentity.bundleIdentifier, try checksBundleIdentifier()] {
            let resolved = LaunchMode.resolve(
                arguments: [Self.executable] + arguments, bundleIdentifier: identifier)
            switch resolved {
            case .failure(.unknownArguments): break
            default: Issue.record("\(arguments) as \(identifier) resolved to \(resolved)")
            }
        }
    }

    @Test(arguments: everyMode.filter { $0 != .app })
    func checksRefuseEveryOtherIdentity(mode: LaunchMode) {
        for identifier in [AppIdentity.bundleIdentifier, "app.mauriciopolvora.ciel.check", nil] {
            let resolved = LaunchMode.resolve(
                arguments: [Self.executable] + mode.arguments, bundleIdentifier: identifier)
            switch resolved {
            case .failure(.wrongIdentity): break
            default: Issue.record("\(mode) as \(identifier ?? "nil") resolved to \(resolved)")
            }
        }
    }

    @Test(arguments: everyMode.filter { $0 != .app })
    func checksRunInTheChecksBundle(mode: LaunchMode) throws {
        let resolved = LaunchMode.resolve(
            arguments: [Self.executable] + mode.arguments, bundleIdentifier: try checksBundleIdentifier())
        #expect(resolved == .success(mode))
    }

    private func checksBundleIdentifier() throws -> String {
        let plist = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Info.plist")
        let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: plist), format: nil)
        return try #require((info as? [String: Any])?["CFBundleIdentifier"] as? String) + ".checks"
    }
}
