import Foundation

enum SearchText {
    enum MatchQuality {
        case prefix
        case contains
    }

    static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    static func tokens(in query: String) -> [String] {
        normalize(query)
            .split(separator: " ")
            .map(String.init)
    }

    static func searchableText(for parts: [String]) -> String {
        Array(Set(parts.flatMap(variants(for:))))
            .sorted()
            .joined(separator: " ")
    }

    static func matchQuality(token: String, in value: String) -> MatchQuality? {
        let normalizedToken = normalize(token)
        guard !normalizedToken.isEmpty else {
            return nil
        }

        var sawContains = false
        for variant in variants(for: value) {
            if variant.hasPrefix(normalizedToken) {
                return .prefix
            }
            if variant.contains(normalizedToken) {
                sawContains = true
            }
        }

        return sawContains ? .contains : nil
    }

    static func variants(for value: String) -> [String] {
        let normalized = normalize(value)
        guard !normalized.isEmpty else {
            return []
        }

        var variants = [normalized]
        if let latinized = latinized(value) {
            variants.append(latinized)

            let compactLatinized = latinized.filter { !$0.isWhitespace }
            if compactLatinized != latinized {
                variants.append(compactLatinized)
            }
        }

        return Array(Set(variants))
    }

    private static func latinized(_ value: String) -> String? {
        guard let transformed = value.applyingTransform(.toLatin, reverse: false)?
            .applyingTransform(.stripCombiningMarks, reverse: false) else {
            return nil
        }

        let normalized = normalize(transformed)
        guard !normalized.isEmpty else {
            return nil
        }

        return normalized
    }
}
