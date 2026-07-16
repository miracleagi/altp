import Foundation

struct WindowTransitionRank: Equatable {
    static let none = WindowTransitionRank(lastSelectedAt: 0, selectionCount: 0)

    let lastSelectedAt: TimeInterval
    let selectionCount: Int
}

struct WindowSessionRank: Equatable {
    static let none = WindowSessionRank(lastSelectedAt: 0, selectionCount: 0)

    let lastSelectedAt: TimeInterval
    let selectionCount: Int
}

final class WindowSelectionMemory {
    static let shared = WindowSelectionMemory()

    private enum DefaultsKey {
        static let snapshot = "windowSelectionMemory.v3"
        static let legacySnapshot = "windowSelectionMemory.v2"
        static let oldestSnapshot = "windowSelectionMemory.v1"
    }

    private struct Snapshot: Codable {
        var records: [String: Record] = [:]
        var appRecords: [String: Record] = [:]

        init(
            records: [String: Record] = [:],
            appRecords: [String: Record] = [:]
        ) {
            self.records = records
            self.appRecords = appRecords
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            records = try container.decodeIfPresent([String: Record].self, forKey: .records) ?? [:]
            appRecords = try container.decodeIfPresent([String: Record].self, forKey: .appRecords) ?? [:]
        }
    }

    private struct Record: Codable {
        var selectionCount: Int
        var lastSelectedAt: TimeInterval
        var queryHits: [String: Int]
        var appSessionKey: String?
    }

    private struct SessionRecord {
        var selectionCount: Int
        var lastSelectedAt: TimeInterval
    }

    private struct TransitionRecord {
        var selectionCount: Int
        var lastSelectedAt: TimeInterval
    }

    private let maxRecords = 500
    private let maxAppRecords = 200
    private let maxSessionRecords = 500
    private let maxSessionTransitions = 800
    private let maxQueriesPerRecord = 24
    private let recentSessionHorizon: TimeInterval = 10 * 60
    private let previousSessionMultiplier = 0.2

    private var cachedSnapshot: Snapshot?
    private var sessionRecords: [String: SessionRecord] = [:]
    private var sessionTransitions: [String: TransitionRecord] = [:]

    func score(for item: WindowItem, query: String) -> Int {
        let normalizedQuery = Self.normalizedQuery(query)
        let snapshot = snapshot()
        var total = appScore(for: item, query: normalizedQuery, snapshot: snapshot)

        if let key = item.persistentMemoryKey,
           let record = snapshot.records[key] {
            total += scaledForCurrentSession(
                score(for: record, query: normalizedQuery),
                record: record,
                currentAppSessionKey: item.appSessionKey
            )
        }

        return total
    }

    func rankingScore(for item: WindowItem, referenceTime: TimeInterval) -> Int {
        let snapshot = snapshot()
        var total = 0

        if let key = item.persistentMemoryKey,
           let record = snapshot.records[key] {
            let rawWindowScore = min(600, record.selectionCount * 30) + 240
            let windowScore = decayedScore(
                rawWindowScore,
                lastSelectedAt: record.lastSelectedAt,
                horizonDays: 60,
                referenceTime: referenceTime
            )
            total += scaledForCurrentSession(
                windowScore,
                record: record,
                currentAppSessionKey: item.appSessionKey
            )
        }

        if let appRecord = snapshot.appRecords[item.appMemoryKey] {
            let rawAppScore = min(180, appRecord.selectionCount * 8) + 60
            let appScore = decayedScore(
                rawAppScore,
                lastSelectedAt: appRecord.lastSelectedAt,
                horizonDays: 60,
                referenceTime: referenceTime
            )
            total += scaledForCurrentSession(
                appScore,
                record: appRecord,
                currentAppSessionKey: item.appSessionKey
            )
        }

        return total
    }

    func transitionRank(
        from source: WindowItem?,
        to target: WindowItem,
        referenceTime: TimeInterval
    ) -> WindowTransitionRank {
        guard let source, !source.representsSameWindow(as: target) else {
            return .none
        }

        let directKey = Self.transitionKey(
            from: source.sessionMemoryKey,
            to: target.sessionMemoryKey
        )
        let reverseKey = Self.transitionKey(
            from: target.sessionMemoryKey,
            to: source.sessionMemoryKey
        )
        let records = [sessionTransitions[directKey], sessionTransitions[reverseKey]].compactMap { $0 }
        guard let lastSelectedAt = records.map(\.lastSelectedAt).max(),
              referenceTime - lastSelectedAt <= recentSessionHorizon else {
            return .none
        }

        return WindowTransitionRank(
            lastSelectedAt: lastSelectedAt,
            selectionCount: records.reduce(0) { $0 + $1.selectionCount }
        )
    }

    func sessionRank(
        for item: WindowItem,
        referenceTime: TimeInterval
    ) -> WindowSessionRank {
        guard let record = sessionRecords[item.sessionMemoryKey],
              referenceTime - record.lastSelectedAt <= recentSessionHorizon else {
            return .none
        }

        return WindowSessionRank(
            lastSelectedAt: record.lastSelectedAt,
            selectionCount: record.selectionCount
        )
    }

    func recordSelection(_ item: WindowItem, query: String, from source: WindowItem? = nil) {
        let normalizedQuery = Self.normalizedQuery(query)
        let selectedAt = Date().timeIntervalSince1970

        var sessionRecord = sessionRecords[item.sessionMemoryKey] ?? SessionRecord(
            selectionCount: 0,
            lastSelectedAt: 0
        )
        sessionRecord.selectionCount += 1
        sessionRecord.lastSelectedAt = selectedAt
        sessionRecords[item.sessionMemoryKey] = sessionRecord

        if let source, !source.representsSameWindow(as: item) {
            let transitionKey = Self.transitionKey(
                from: source.sessionMemoryKey,
                to: item.sessionMemoryKey
            )
            var transition = sessionTransitions[transitionKey] ?? TransitionRecord(
                selectionCount: 0,
                lastSelectedAt: 0
            )
            transition.selectionCount += 1
            transition.lastSelectedAt = selectedAt
            sessionTransitions[transitionKey] = transition
        }

        var snapshot = snapshot()
        if let key = item.persistentMemoryKey {
            var record = snapshot.records[key] ?? Record(
                selectionCount: 0,
                lastSelectedAt: 0,
                queryHits: [:],
                appSessionKey: item.appSessionKey
            )
            downgradeIfNeeded(&record, for: item.appSessionKey)
            record.selectionCount += 1
            record.lastSelectedAt = selectedAt

            if !normalizedQuery.isEmpty {
                record.queryHits[normalizedQuery, default: 0] += 1
                trimQueries(in: &record)
            }
            snapshot.records[key] = record
        }

        var appRecord = snapshot.appRecords[item.appMemoryKey] ?? Record(
            selectionCount: 0,
            lastSelectedAt: 0,
            queryHits: [:],
            appSessionKey: item.appSessionKey
        )
        downgradeIfNeeded(&appRecord, for: item.appSessionKey)
        appRecord.selectionCount += 1
        appRecord.lastSelectedAt = selectedAt

        if !normalizedQuery.isEmpty {
            appRecord.queryHits[normalizedQuery, default: 0] += 1
            trimQueries(in: &appRecord)
        }
        snapshot.appRecords[item.appMemoryKey] = appRecord

        trimRecords(in: &snapshot)
        trimAppRecords(in: &snapshot)
        trimSessionRecords()
        trimSessionTransitions()
        cachedSnapshot = snapshot
        save(snapshot)
    }

    private func score(for record: Record, query normalizedQuery: String) -> Int {
        var score = min(360, record.selectionCount * 30)

        if !normalizedQuery.isEmpty {
            score += min(900, (record.queryHits[normalizedQuery] ?? 0) * 300)
            score += relatedQueryBonus(record: record, query: normalizedQuery)
        }

        return decayedScore(score, lastSelectedAt: record.lastSelectedAt, horizonDays: 60)
            + recencyBonus(lastSelectedAt: record.lastSelectedAt)
    }

    private func appScore(for item: WindowItem, query normalizedQuery: String, snapshot: Snapshot) -> Int {
        guard let record = snapshot.appRecords[item.appMemoryKey] else {
            return 0
        }

        var score = min(240, record.selectionCount * 12)

        if !normalizedQuery.isEmpty {
            score += min(300, (record.queryHits[normalizedQuery] ?? 0) * 100)
            score += relatedQueryBonus(record: record, query: normalizedQuery) / 2
        }

        let total = decayedScore(score, lastSelectedAt: record.lastSelectedAt, horizonDays: 60)
            + recencyBonus(lastSelectedAt: record.lastSelectedAt) / 2
        return scaledForCurrentSession(
            total,
            record: record,
            currentAppSessionKey: item.appSessionKey
        )
    }

    private func snapshot() -> Snapshot {
        if let cachedSnapshot {
            return cachedSnapshot
        }

        for key in [DefaultsKey.snapshot, DefaultsKey.legacySnapshot, DefaultsKey.oldestSnapshot] {
            if let data = UserDefaults.standard.data(forKey: key),
               let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
                cachedSnapshot = snapshot
                return snapshot
            }
        }

        let snapshot = Snapshot()
        cachedSnapshot = snapshot
        return snapshot
    }

    private func save(_ snapshot: Snapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }

        UserDefaults.standard.set(data, forKey: DefaultsKey.snapshot)
    }

    private func downgradeIfNeeded(_ record: inout Record, for appSessionKey: String) {
        guard record.appSessionKey != appSessionKey else {
            return
        }

        record.selectionCount = Int(Double(record.selectionCount) * previousSessionMultiplier)
        record.queryHits = record.queryHits.reduce(into: [:]) { result, entry in
            let downgradedCount = Int(Double(entry.value) * previousSessionMultiplier)
            if downgradedCount > 0 {
                result[entry.key] = downgradedCount
            }
        }
        record.appSessionKey = appSessionKey
    }

    private func scaledForCurrentSession(
        _ score: Int,
        record: Record,
        currentAppSessionKey: String
    ) -> Int {
        guard record.appSessionKey != currentAppSessionKey else {
            return score
        }
        return Int(Double(score) * previousSessionMultiplier)
    }

    private func recencyBonus(lastSelectedAt: TimeInterval) -> Int {
        let age = Date().timeIntervalSince1970 - lastSelectedAt
        let ageDays = max(0, age / 86_400)
        guard ageDays < 30 else {
            return 0
        }

        return Int(240 * (1 - ageDays / 30))
    }

    private func decayedScore(
        _ score: Int,
        lastSelectedAt: TimeInterval,
        horizonDays: Double,
        referenceTime: TimeInterval = Date().timeIntervalSince1970
    ) -> Int {
        guard score > 0, lastSelectedAt > 0 else {
            return 0
        }

        let ageSeconds = max(0, referenceTime - lastSelectedAt)
        let ageDays = ageSeconds / 86_400
        guard ageDays < horizonDays else {
            return 0
        }

        return Int(Double(score) * (1 - ageDays / horizonDays))
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

    private func trimAppRecords(in snapshot: inout Snapshot) {
        guard snapshot.appRecords.count > maxAppRecords else {
            return
        }

        let keysToRemove = snapshot.appRecords
            .sorted { lhs, rhs in
                if lhs.value.lastSelectedAt != rhs.value.lastSelectedAt {
                    return lhs.value.lastSelectedAt < rhs.value.lastSelectedAt
                }
                return lhs.value.selectionCount < rhs.value.selectionCount
            }
            .prefix(snapshot.appRecords.count - maxAppRecords)
            .map(\.key)

        for key in keysToRemove {
            snapshot.appRecords.removeValue(forKey: key)
        }
    }

    private func trimSessionRecords() {
        guard sessionRecords.count > maxSessionRecords else {
            return
        }

        let keysToRemove = sessionRecords
            .sorted { lhs, rhs in
                if lhs.value.lastSelectedAt != rhs.value.lastSelectedAt {
                    return lhs.value.lastSelectedAt < rhs.value.lastSelectedAt
                }
                return lhs.value.selectionCount < rhs.value.selectionCount
            }
            .prefix(sessionRecords.count - maxSessionRecords)
            .map(\.key)

        for key in keysToRemove {
            sessionRecords.removeValue(forKey: key)
        }
    }

    private func trimSessionTransitions() {
        guard sessionTransitions.count > maxSessionTransitions else {
            return
        }

        let keysToRemove = sessionTransitions
            .sorted { lhs, rhs in
                if lhs.value.lastSelectedAt != rhs.value.lastSelectedAt {
                    return lhs.value.lastSelectedAt < rhs.value.lastSelectedAt
                }
                return lhs.value.selectionCount < rhs.value.selectionCount
            }
            .prefix(sessionTransitions.count - maxSessionTransitions)
            .map(\.key)

        for key in keysToRemove {
            sessionTransitions.removeValue(forKey: key)
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
