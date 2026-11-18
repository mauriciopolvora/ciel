import Foundation
import FuzzyMatch

public struct SearchEntry: Identifiable, Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case application, window, utility }
    public let id: String
    public let title: String
    public let subtitle: String
    public let kind: Kind
    public let path: String?
    public let action: WindowAction?
    public let searchable: String
    public let normalizedTitle: String

    public init(
        id: String, title: String, subtitle: String, kind: Kind, path: String? = nil,
        action: WindowAction? = nil, keywords: String = ""
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.kind = kind
        self.path = path
        self.action = action
        self.normalizedTitle = SearchEngine.normalize(title)
        self.searchable = SearchEngine.normalize(title + " " + keywords)
    }

    public static var commands: [SearchEntry] {
        WindowAction.allCases.map {
            SearchEntry(
                id: $0.id, title: $0.title, subtitle: "Window Management",
                kind: .window, action: $0, keywords: $0.keywords)
        }
    }

    public static let utilities = UtilityCommand.allCases.map(\.entry)

    public var utility: UtilityCommand? { kind == .utility ? UtilityCommand(rawValue: id) : nil }
}

public enum UtilityCommand: String, CaseIterable, Sendable {
    case settings, rescan

    public var entry: SearchEntry {
        switch self {
        case .settings:
            SearchEntry(
                id: rawValue, title: "Ciel Settings", subtitle: "Preferences", kind: .utility,
                keywords: "hotkey shortcut permission accessibility login")
        case .rescan:
            SearchEntry(
                id: rawValue, title: "Rescan Applications", subtitle: "Ciel", kind: .utility,
                keywords: "refresh index apps")
        }
    }
}

public enum SearchEngine {
    public static func normalize(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    public static func tokens(in query: String) -> [String] {
        normalize(query).split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    private static let strict = FuzzyMatcher(
        config: MatchConfig(
            minScore: 0.3,
            algorithm: .editDistance(EditDistanceConfig(maxEditDistance: 0, longQueryMaxEditDistance: 0))))
    private static let tolerant = FuzzyMatcher(
        config: MatchConfig(
            minScore: 0.3,
            algorithm: .editDistance(EditDistanceConfig(maxEditDistance: 1, longQueryMaxEditDistance: 2))))

    /// The form a query is matched and remembered in, so a pick recorded for a query is found again by it.
    public static func queryKey(_ query: String) -> String {
        tokens(in: query).joined(separator: " ")
    }

    public static func search(
        _ query: String, entries: [SearchEntry], kind: SearchEntry.Kind? = nil, usage: Usage = Usage(),
        limit: Int = 60
    ) -> [SearchEntry] {
        let tokens = tokens(in: query)
        guard limit > 0, !tokens.isEmpty else { return [] }
        let key = queryKey(query)
        var learned: [String: Int] = [:]
        for pick in usage.picks where pick.query.hasPrefix(key) { learned[pick.id, default: 0] += 1 }
        let prepared = tokens.map { token in
            let matcher = token.count < 4 ? strict : tolerant
            return (token, matcher, matcher.prepare(token))
        }
        var buffer = tolerant.makeBuffer()
        return entries.compactMap { entry -> Ranked? in
            if let kind, entry.kind != kind { return nil }
            let history = min(max(0, usage.counts[entry.id, default: 0]), 30)
            var score = 0
            for (token, matcher, query) in prepared {
                if entry.normalizedTitle == token {
                    score += 300
                } else if entry.normalizedTitle.hasPrefix(token) {
                    score += 200
                } else if entry.normalizedTitle.contains(token) {
                    score += 130
                } else if entry.searchable.contains(token) {
                    score += 60
                } else if let match = matcher.score(entry.normalizedTitle, against: query, buffer: &buffer) {
                    score += Int(match.score * 55)
                } else {
                    return nil
                }
            }
            let exact = entry.normalizedTitle == key
            if exact { score += 500 }
            return Ranked(
                entry: entry, exact: exact, learned: learned[entry.id, default: 0], score: score + history,
                lastUsed: usage.lastUsed[entry.id, default: 0])
        }.sorted {
            if $0.exact != $1.exact { return $0.exact }
            if $0.learned != $1.learned { return $0.learned > $1.learned }
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.lastUsed != $1.lastUsed { return $0.lastUsed > $1.lastUsed }
            return $0.entry.title.localizedStandardCompare($1.entry.title) == .orderedAscending
        }.prefix(limit).map(\.entry)
    }

    private struct Ranked {
        let entry: SearchEntry
        let exact: Bool
        let learned: Int
        let score: Int
        let lastUsed: Double
    }
}
