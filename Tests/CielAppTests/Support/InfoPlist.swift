import Foundation

func infoPlist() throws -> [String: Any] {
    let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    let plist = repository.appendingPathComponent("Resources/Info.plist")
    let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: plist), format: nil)
    return info as? [String: Any] ?? [:]
}
