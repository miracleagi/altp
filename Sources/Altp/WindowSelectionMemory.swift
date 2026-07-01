import Foundation

final class WindowSelectionMemory {
    static let shared = WindowSelectionMemory()

    private enum DefaultsKey {
        static let snapshot = "windowSelectionMemory.v2"
        static let legacySnapshot = "windowSelectionMemory.v1"
    }

    private struct Snapshot: Codable {
        var records: [String: Record] = [:]
        var transitions: [String: TransitionRecord] = [:]

        init(records: [String: Record] = [:], transitions: [String: TransitionRecord] = [:]) {
            self.records = records
            self.transitions = transitions
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            records = try container.decodeIfPresent([String: Record].self, forKey: .records) ?? [:]
            transitions = try container.decodeIfPresent([String: TransitionRecord].self, forKey: .transitions) ?? [:]
        }
    }

    private struct Record: Codable {
        var selectionCount: Int
        var lastSelectedAt: TimeInterval
        var queryHits: [String: Int]
    }

    private struct TransitionRecord: Codable {
        var selectionCount: Int
        var lastSelectedAt: TimeInterval
    }

    private let maxRecords = 500
    private let maxTransitions = 800
    private let maxQueriesPerRecord = 24
    private var cachedSnapshot: Snapshot?

    func score(for item: WindowItem, query: String) -> Int {
        let normalizedQuery = Self.normalizedQuery(query)
        guard let record = snapshot().records[item.memoryKey] else {
            return 0
        }

        var score = min(360, record.selectionCount * 30)
        score += recencyBonus(lastSelectedAt: record.lastSelectedAt)

        if !normalizedQuery.isEmpty {
            score += min(900, (record.queryHits[normalizedQuery] ?? 0) * 300)
            score += relatedQueryBonus(record: record, query: normalizedQuery)
        }

        return score
    }

    func transitionScore(from source: WindowItem?, to target: WindowItem) -> Int {
        guard let source, source.memoryKey != target.memoryKey else {
            return 0
        }

        let key = Self.transitionKey(from: source.memoryKey, to: target.memoryKey)
        let reverseKey = Self.transitionKey(from: target.memoryKey, to: source.memoryKey)
        let transitions = snapshot().transitions

        var totalScore = 0
        if let record = transitions[key] {
            totalScore += transitionScore(for: record)
        }

        if let reverseRecord = transitions[reverseKey] {
            totalScore += transitionScore(for: reverseRecord) / 2
        }

        return totalScore
    }

    func recordSelection(_ item: WindowItem, query: String, from source: WindowItem? = nil) {
        let normalizedQuery = Self.normalizedQuery(query)
        var snapshot = snapshot()
        var record = snapshot.records[item.memoryKey] ?? Record(
            selectionCount: 0,
            lastSelectedAt: 0,
            queryHits: [:]
        )

        record.selectionCount += 1
        record.lastSelectedAt = Date().timeIntervalSince1970

        if !normalizedQuery.isEmpty {
            record.queryHits[normalizedQuery, default: 0] += 1
            trimQueries(in: &record)
        }

        snapshot.records[item.memoryKey] = record

        if let source, source.memoryKey != item.memoryKey {
            let transitionKey = Self.transitionKey(from: source.memoryKey, to: item.memoryKey)
            var transition = snapshot.transitions[transitionKey] ?? TransitionRecord(
                selectionCount: 0,
                lastSelectedAt: 0
            )
            transition.selectionCount += 1
            transition.lastSelectedAt = record.lastSelectedAt
            snapshot.transitions[transitionKey] = transition
        }

        trimRecords(in: &snapshot)
        trimTransitions(in: &snapshot)
        cachedSnapshot = snapshot
        save(snapshot)
    }

    private func snapshot() -> Snapshot {
        if let cachedSnapshot {
            return cachedSnapshot
        }

        if let data = UserDefaults.standard.data(forKey: DefaultsKey.snapshot),
           let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            cachedSnapshot = snapshot
            return snapshot
        }

        guard let data = UserDefaults.standard.data(forKey: DefaultsKey.legacySnapshot),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            let snapshot = Snapshot()
            cachedSnapshot = snapshot
            return snapshot
        }

        cachedSnapshot = snapshot
        return snapshot
    }

    private func save(_ snapshot: Snapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }

        UserDefaults.standard.set(data, forKey: DefaultsKey.snapshot)
    }

    private func recencyBonus(lastSelectedAt: TimeInterval) -> Int {
        let age = Date().timeIntervalSince1970 - lastSelectedAt
        let ageDays = max(0, age / 86_400)
        guard ageDays < 30 else {
            return 0
        }

        return Int(240 * (1 - ageDays / 30))
    }

    private func transitionRecencyBonus(lastSelectedAt: TimeInterval) -> Int {
        let age = Date().timeIntervalSince1970 - lastSelectedAt
        let ageDays = max(0, age / 86_400)
        guard ageDays < 14 else {
            return 0
        }

        return Int(2_000 * (1 - ageDays / 14))
    }

    private func transitionScore(for transition: TransitionRecord) -> Int {
        var score = min(3_000, transition.selectionCount * 750)
        score += transitionRecencyBonus(lastSelectedAt: transition.lastSelectedAt)
        return score
    }

    private func relatedQueryBonus(record: Record, query: String) -> Int {
        var score = 0

        for (storedQuery, hits) in record.queryHits where storedQuery != query {
            if storedQuery.contains(query) || query.contains(storedQuery) {
                score += min(300, hits * 80)
            }
        }

        return min(300, score)
    }

    private func trimRecords(in snapshot: inout Snapshot) {
        guard snapshot.records.count > maxRecords else {
            return
        }

        let keysToRemove = snapshot.records
            .sorted { lhs, rhs in
                if lhs.value.lastSelectedAt != rhs.value.lastSelectedAt {
                    return lhs.value.lastSelectedAt < rhs.value.lastSelectedAt
                }
                return lhs.value.selectionCount < rhs.value.selectionCount
            }
            .prefix(snapshot.records.count - maxRecords)
            .map(\.key)

        for key in keysToRemove {
            snapshot.records.removeValue(forKey: key)
        }
    }

    private func trimTransitions(in snapshot: inout Snapshot) {
        guard snapshot.transitions.count > maxTransitions else {
            return
        }

        let keysToRemove = snapshot.transitions
            .sorted { lhs, rhs in
                if lhs.value.lastSelectedAt != rhs.value.lastSelectedAt {
                    return lhs.value.lastSelectedAt < rhs.value.lastSelectedAt
                }
                return lhs.value.selectionCount < rhs.value.selectionCount
            }
            .prefix(snapshot.transitions.count - maxTransitions)
            .map(\.key)

        for key in keysToRemove {
            snapshot.transitions.removeValue(forKey: key)
        }
    }

    private func trimQueries(in record: inout Record) {
        guard record.queryHits.count > maxQueriesPerRecord else {
            return
        }

        let keysToRemove = record.queryHits
            .sorted { lhs, rhs in
                lhs.value < rhs.value
            }
            .prefix(record.queryHits.count - maxQueriesPerRecord)
            .map(\.key)

        for key in keysToRemove {
            record.queryHits.removeValue(forKey: key)
        }
    }

    static func normalizedQuery(_ query: String) -> String {
        SearchText.normalize(query)
    }

    private static func transitionKey(from source: String, to target: String) -> String {
        "\(source)>\(target)"
    }
}
