import Foundation

/// Prototype variants that the operator switches live from the Design preview section in Settings.
/// The follow-up PR keeps the chosen variant and deletes this file.
enum SettingsDesign: String, CaseIterable, Sendable {
    case a, b, c

    var letter: String { rawValue.uppercased() }

    var summary: String {
        switch self {
        case .a: "Grouped rows"
        case .b: "Key caps on top"
        case .c: "Two columns"
        }
    }
}

enum LauncherDesign: String, CaseIterable, Sendable {
    case a, b, c

    var letter: String { rawValue.uppercased() }

    var summary: String {
        switch self {
        case .a: "Launcher A"
        case .b: "Launcher B"
        case .c: "Launcher C"
        }
    }
}

extension Notification.Name {
    static let designPreviewChanged = Notification.Name("CielDesignPreviewChanged")
}

struct DesignPreview {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var settings: SettingsDesign {
        get { defaults.string(forKey: "designPreview.settings").flatMap(SettingsDesign.init) ?? .a }
        nonmutating set { save(newValue.rawValue, "designPreview.settings") }
    }

    var launcher: LauncherDesign {
        get { defaults.string(forKey: "designPreview.launcher").flatMap(LauncherDesign.init) ?? .a }
        nonmutating set { save(newValue.rawValue, "designPreview.launcher") }
    }

    private func save(_ value: String, _ key: String) {
        defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: .designPreviewChanged, object: nil)
    }
}
