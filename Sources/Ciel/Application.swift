import AppKit

/// Native entry point shared by the app executable and its testable library.
public enum CielApplication {
    @MainActor public static func run() {
        AppPerformance.markLaunch()
        let application = NSApplication.shared
        // A fixture needs only its window. Construct it before the resident app
        // services, which have no role in this separate target process.
        if let index = CommandLine.arguments.firstIndex(of: "--window-fixture"),
            index + 1 < CommandLine.arguments.count
        {
            let fixture = WindowFixture(output: CommandLine.arguments[index + 1])
            fixture.run()
            withExtendedLifetime(fixture) { application.run() }
            return
        }
        let delegate = AppDelegate()
        application.delegate = delegate
        // NSApplication does not retain its delegate. Keep it alive for the
        // complete event loop after moving the entry point into this function.
        withExtendedLifetime(delegate) { application.run() }
    }
}
