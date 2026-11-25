import CielCore
import Foundation
import Testing

@Suite struct VerifyRecipeTests {
    private static let commandsWithoutARecipe: Set<String> = [
        "window.rightHalf", "window.firstThreeFourths", "window.lastThreeFourths",
        "window.centerThreeFourths", "window.almostMaximize", "window.center",
        "window.nextDisplay", "window.previousDisplay", "window.topHalf", "window.bottomHalf",
        "window.topLeft", "window.topRight", "window.bottomLeft", "window.bottomRight",
        "window.minimize",
    ]

    private static var commands: [(id: String, title: String)] {
        let windows = WindowAction.allCases.map { (id: $0.id, title: $0.title) }
        let utilities = UtilityCommand.allCases.map { (id: $0.entry.id, title: $0.entry.title) }
        return windows + utilities
    }

    private static func runQueries() throws -> Set<String> {
        let features = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".agents/skills/verify-ciel/features")
        let recipes = try FileManager.default
            .contentsOfDirectory(at: features, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "md" && $0.lastPathComponent != "README.md" }
        try #require(!recipes.isEmpty)
        let step = try Regex(#"ciel-verify\.sh (?:type (?:"([^"]+)"|([^\s`"]+))|press ([^\s`"]+))"#)
        var queries: Set<String> = []
        for recipe in recipes {
            let text = try String(contentsOf: recipe, encoding: .utf8)
            guard let start = text.range(of: "\n## Driving it with ciel-verify.sh\n") else { continue }
            let driving = text[start.upperBound...]
            let section = driving.range(of: "\n## ").map { driving[..<$0.lowerBound] } ?? driving
            var typed: Substring?
            for match in section.matches(of: step) {
                if let key = match.output[3].substring {
                    if key == "return", let query = typed {
                        queries.insert(query.lowercased())
                    }
                    typed = nil
                } else {
                    typed = match.output[1].substring ?? match.output[2].substring
                }
            }
        }
        return queries
    }

    private static func withRecipe(_ queries: Set<String>) -> Set<String> {
        Set(commands.filter { queries.contains($0.title.lowercased()) }.map { $0.id })
    }

    @Test func everyCommandWithoutARecipeIsListed() throws {
        let covered = try Self.withRecipe(Self.runQueries())
        let missing = Set(Self.commands.map { $0.id }).subtracting(covered)
            .subtracting(Self.commandsWithoutARecipe)
        #expect(missing.isEmpty, "Add a verify-ciel recipe that types and runs each title: \(missing)")
    }

    @Test func aListedCommandThatGainsARecipeLeavesTheList() throws {
        let covered = try Self.withRecipe(Self.runQueries())
            .intersection(Self.commandsWithoutARecipe)
        #expect(covered.isEmpty, "Remove these from commandsWithoutARecipe: \(covered)")
    }

    @Test func theListNamesOnlyRealCommands() {
        let unknown = Self.commandsWithoutARecipe.subtracting(Self.commands.map { $0.id })
        #expect(unknown.isEmpty, "Remove these from commandsWithoutARecipe: \(unknown)")
    }
}
