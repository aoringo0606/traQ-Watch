import Foundation

nonisolated struct StampReference: Equatable, Hashable, Sendable {
    let name: String
    let effects: [String]
    let raw: String

    var pointSize: Double {
        switch effects.last(where: { ["small", "large", "ex-large"].contains($0) }) {
        case "small": 18
        case "large": 32
        case "ex-large": 40
        default: 24
        }
    }

    static func parse(_ raw: String) -> Self? {
        guard raw.first == ":", raw.last == ":", raw.count <= 180 else { return nil }
        let parts = raw.dropFirst().dropLast().split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard let name = parts.first else { return nil }
        let pattern = #"^(?:[a-zA-Z0-9+_-]{1,32}|@[a-zA-Z0-9_-]{1,32})$"#
        guard name.range(of: pattern, options: .regularExpression) != nil else { return nil }
        let effects = Array(parts.dropFirst())
        let sizes: Set<String> = ["small", "large", "ex-large"]
        let animations: Set<String> = ["rotate", "rotate-inv", "wiggle", "parrot", "zoom", "inversion", "turn", "turn-v", "happa", "pyon", "flashy", "pull", "atsumori", "stretch", "stretch-v", "conga", "conga-inv", "marquee", "marquee-inv", "rainbow", "ascension", "shake", "party", "attract"]
        guard effects.allSatisfy({ sizes.contains($0) || animations.contains($0) }),
              effects.filter({ animations.contains($0) }).count <= 5 else { return nil }
        return Self(name: name, effects: effects, raw: raw)
    }
}
