import Foundation

public struct Usage: Equatable, Sendable {
    public struct Pick: Equatable, Sendable {
        public let query: String
        public let id: String

        public init(query: String, id: String) {
            self.query = query
            self.id = id
        }
    }

    public var counts: [String: Int]
    public var lastUsed: [String: Double]
    /// Oldest first, at most `UsageHistory.pickLimit`.
    public var picks: [Pick]

    public init(counts: [String: Int] = [:], lastUsed: [String: Double] = [:], picks: [Pick] = []) {
        self.counts = counts
        self.lastUsed = lastUsed
        self.picks = picks
    }
}

public final class UsageHistory {
    public static let pickLimit = 500
    private let defaults: UserDefaults
    public private(set) var usage: Usage

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let picks = (defaults.array(forKey: "picks") ?? []).compactMap { row -> Usage.Pick? in
            guard let row = row as? [String: Any], let query = row["query"] as? String,
                let id = row["id"] as? String
            else { return nil }
            return Usage.Pick(query: query, id: id)
        }
        usage = Usage(
            counts: defaults.dictionary(forKey: "usage") as? [String: Int] ?? [:],
            lastUsed: defaults.dictionary(forKey: "lastUsed") as? [String: Double] ?? [:],
            picks: picks)
    }

    public func record(_ id: String, query: String? = nil, at date: Date = Date()) {
        usage.counts[id] = min(Int.max - 1, max(0, usage.counts[id, default: 0])) + 1
        usage.lastUsed[id] = date.timeIntervalSince1970
        defaults.set(usage.counts, forKey: "usage")
        defaults.set(usage.lastUsed, forKey: "lastUsed")
        guard let key = query.map(SearchEngine.queryKey), !key.isEmpty else { return }
        usage.picks.append(Usage.Pick(query: key, id: id))
        usage.picks.removeFirst(max(0, usage.picks.count - Self.pickLimit))
        defaults.set(usage.picks.map { ["query": $0.query, "id": $0.id] }, forKey: "picks")
    }
}
