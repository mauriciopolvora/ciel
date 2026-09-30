import Foundation

/// Small local history. Keys remain compatible with earlier Ciel builds.
public final class UsageHistory {
    private let defaults: UserDefaults
    public private(set) var counts: [String: Int]
    public private(set) var lastUsed: [String: Double]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        counts = defaults.dictionary(forKey: "usage") as? [String: Int] ?? [:]
        lastUsed = defaults.dictionary(forKey: "lastUsed") as? [String: Double] ?? [:]
    }

    public func record(_ id: String, at date: Date = Date()) {
        counts[id] = min(Int.max - 1, max(0, counts[id, default: 0])) + 1
        lastUsed[id] = date.timeIntervalSince1970
        defaults.set(counts, forKey: "usage")
        defaults.set(lastUsed, forKey: "lastUsed")
    }
}
