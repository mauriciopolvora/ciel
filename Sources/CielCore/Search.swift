import Foundation
import FuzzyMatch

public struct SearchEntry: Identifiable, Codable, Sendable {
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
                id: "window." + $0.rawValue, title: $0.title, subtitle: "Window Management",
                kind: .window, action: $0, keywords: $0.keywords)
        }
    }
}

public enum SearchEngine {
    public static func normalize(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private static let strict = FuzzyMatcher(
        config: MatchConfig(
            minScore: 0.3,
            algorithm: .editDistance(EditDistanceConfig(maxEditDistance: 0, longQueryMaxEditDistance: 0))))
    private static let tolerant = FuzzyMatcher(
        config: MatchConfig(
            minScore: 0.3,
            algorithm: .editDistance(EditDistanceConfig(maxEditDistance: 1, longQueryMaxEditDistance: 2))))

    public static func search(
        _ query: String, entries: [SearchEntry], kind: SearchEntry.Kind? = nil,
        usage: [String: Int] = [:], lastUsed: [String: Double] = [:], limit: Int = 60
    ) -> [SearchEntry] {
        guard limit > 0 else { return [] }
        let q = normalize(query).trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = q.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        // Prepare each token once. Reuse the scoring buffer for the complete catalog.
        let prepared = tokens.map { token in
            let matcher = token.count < 4 ? strict : tolerant
            return (token, matcher, matcher.prepare(token))
        }
        var buffer = tolerant.makeBuffer()
        return entries.compactMap { entry -> (SearchEntry, Int)? in
            if let kind, entry.kind != kind { return nil }
            let count = max(0, usage[entry.id, default: 0])
            let history = min(count, 30)
            if q.isEmpty {
                // Frequency ranks apps and window commands equally.
                return (entry, count)
            }
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
            if entry.normalizedTitle == q { score += 500 }
            return (entry, score + history)
        }.sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            if $0.1 > 0 {
                let a = lastUsed[$0.0.id, default: 0]
                let b = lastUsed[$1.0.id, default: 0]
                if a != b { return a > b }
            } else if q.isEmpty {
                let a = $0.0.kind == .application ? 2 : $0.0.kind == .window ? 1 : 0
                let b = $1.0.kind == .application ? 2 : $1.0.kind == .window ? 1 : 0
                if a != b { return a > b }
            }
            return $0.0.title.localizedStandardCompare($1.0.title) == .orderedAscending
        }.prefix(limit).map(\.0)
    }
}
