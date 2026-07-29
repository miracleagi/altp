import Foundation

final class WindowSelectionMemory {
    static let shared = WindowSelectionMemory()

    private enum DefaultsKey {
        static let snapshot = "windowSelectionMemory.v4"
        static let legacySnapshot = "windowSelectionMemory.v3"
        static let olderSnapshot = "windowSelectionMemory.v2"
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
        var lastUsedAt: TimeInterval
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

    private let defaults: UserDefaults
    private var cachedSnapshot: Snapshot?
    private var sessionRecords: [String: SessionRecord] = [:]
    private var sessionTransitions: [String: TransitionRecord] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func queryBonus(for item: WindowItem, query: String) -> Int {
        let normalizedQuery = Self.normalizedQuery(query)
        guard !normalizedQuery.isEmpty else {
            return 0
        }

        let snapshot = snapshot()
        guard let key = item.persistentMemoryKey,
              let record = snapshot.records[key] else {
            return 0
        }

        return scaledForCurrentSession(
            queryBonus(for: record, query: normalizedQuery),
            record: record,
            currentAppSessionKey: item.appSessionKey
        )
    }

    func persistentRank(for item: WindowItem, referenceTime: TimeInterval) -> WindowPersistentRank {
        let snapshot = snapshot()
        var windowScore = 0.0

        if let key = item.persistentMemoryKey,
           let record = snapshot.records[key] {
            windowScore = WindowRankingPolicy.persistentScore(
                selectionCount: record.selectionCount,
                lastSelectedAt: record.lastSelectedAt,
                maximumScore: WindowRankingPolicy.maximumPersistentWindowScore,
                referenceTime: referenceTime,
                sessionMultiplier: sessionMultiplier(
                    for: record,
                    currentAppSessionKey: item.appSessionKey
                )
            )
        }

        var appScore = 0.0
        if let appRecord = snapshot.appRecords[item.appMemoryKey] {
            appScore = WindowRankingPolicy.persistentScore(
                selectionCount: appRecord.selectionCount,
                lastSelectedAt: appRecord.lastSelectedAt,
                maximumScore: WindowRankingPolicy.maximumPersistentAppScore,
                referenceTime: referenceTime,
                sessionMultiplier: sessionMultiplier(
                    for: appRecord,
                    currentAppSessionKey: item.appSessionKey
                )
            )
        }

        return WindowPersistentRank(appScore: appScore, windowScore: windowScore)
    }

    func sessionRank(
        for item: WindowItem,
        from source: WindowItem?,
        referenceTime: TimeInterval
    ) -> WindowSessionRank {
        let record = sessionRecords[item.sessionMemoryKey]
        var lastUsedAt = record?.lastUsedAt ?? 0
        var interactionCount = record?.selectionCount ?? 0

        if let source, !source.representsSameWindow(as: item) {
            let directKey = Self.transitionKey(
                from: source.sessionMemoryKey,
                to: item.sessionMemoryKey
            )
            let reverseKey = Self.transitionKey(
                from: item.sessionMemoryKey,
                to: source.sessionMemoryKey
            )
            let transitions = [sessionTransitions[directKey], sessionTransitions[reverseKey]].compactMap { $0 }
            lastUsedAt = max(lastUsedAt, transitions.map(\.lastSelectedAt).max() ?? 0)
            interactionCount += transitions.reduce(0) { $0 + $1.selectionCount }
        }

        let rank = WindowSessionRank(
            lastUsedAt: lastUsedAt,
            interactionCount: interactionCount
        )
        guard WindowRankingPolicy.sessionScore(
            for: rank,
            referenceTime: referenceTime
        ) > 0 else {
            return .none
        }
        return rank
    }

    func recordObservation(
        _ item: WindowItem,
        observedAt: TimeInterval = Date().timeIntervalSince1970
    ) {
        recordSessionActivity(item, at: observedAt, incrementSelectionCount: false)
        trimSessionRecords()
    }

    func recordSelection(
        _ item: WindowItem,
        query: String,
        from source: WindowItem? = nil,
        selectedAt: TimeInterval = Date().timeIntervalSince1970
    ) {
        let normalizedQuery = Self.normalizedQuery(query)

        if let source {
            recordSessionActivity(source, at: selectedAt, incrementSelectionCount: false)
        }
        recordSessionActivity(item, at: selectedAt, incrementSelectionCount: true)

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
            transition.lastSelectedAt = max(
                transition.lastSelectedAt,
                selectedAt
            )
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
            record.lastSelectedAt = max(record.lastSelectedAt, selectedAt)

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
        appRecord.lastSelectedAt = max(
            appRecord.lastSelectedAt,
            selectedAt
        )

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

    private func queryBonus(for record: Record, query normalizedQuery: String) -> Int {
        let score = min(120, (record.queryHits[normalizedQuery] ?? 0) * 30)
            + relatedQueryBonus(record: record, query: normalizedQuery)

        return Int(WindowRankingPolicy.decayedScore(
            Double(score),
            lastUsedAt: record.lastSelectedAt,
            halfLifeDays: WindowRankingPolicy.persistentHalfLifeDays,
            referenceTime: Date().timeIntervalSince1970
        ))
    }

    private func snapshot() -> Snapshot {
        if let cachedSnapshot {
            return cachedSnapshot
        }

        if let data = defaults.data(forKey: DefaultsKey.snapshot),
           let decodedSnapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            var snapshot = sanitizedCurrentSnapshot(decodedSnapshot)
            trimRecords(in: &snapshot)
            trimAppRecords(in: &snapshot)
            cachedSnapshot = snapshot
            if snapshot.records.count != decodedSnapshot.records.count
                || snapshot.appRecords.count != decodedSnapshot.appRecords.count {
                save(snapshot)
            }
            return snapshot
        }

        for key in [
            DefaultsKey.legacySnapshot,
            DefaultsKey.olderSnapshot,
            DefaultsKey.oldestSnapshot
        ] {
            if let data = defaults.data(forKey: key),
               let legacySnapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
                var snapshot = migratedLegacySnapshot(legacySnapshot)
                trimRecords(in: &snapshot)
                trimAppRecords(in: &snapshot)
                cachedSnapshot = snapshot
                save(snapshot)
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

        defaults.set(data, forKey: DefaultsKey.snapshot)
    }

    private func sanitizedCurrentSnapshot(_ snapshot: Snapshot) -> Snapshot {
        Snapshot(
            records: snapshot.records.filter { key, _ in
                WindowIdentityPolicy.isCurrentPersistentKey(key)
            },
            appRecords: snapshot.appRecords.filter { key, _ in
                !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        )
    }

    private func migratedLegacySnapshot(_ legacySnapshot: Snapshot) -> Snapshot {
        var migrated = Snapshot()

        for (legacyKey, record) in legacySnapshot.records {
            guard let key = WindowIdentityPolicy.migratedLegacyPersistentKey(
                legacyKey
            ) else {
                continue
            }
            migrated.records[key] = mergedRecord(
                migrated.records[key],
                with: record
            )
        }

        for (legacyKey, record) in legacySnapshot.appRecords {
            let key = WindowIdentityPolicy.applicationKey(
                bundleIdentifier: legacyKey,
                appName: legacyKey
            )
            guard !key.isEmpty else {
                continue
            }
            migrated.appRecords[key] = mergedRecord(
                migrated.appRecords[key],
                with: record
            )
        }

        return migrated
    }

    private func mergedRecord(
        _ existing: Record?,
        with incoming: Record
    ) -> Record {
        guard var merged = existing else {
            var record = incoming
            record.selectionCount = max(0, record.selectionCount)
            record.lastSelectedAt = max(0, record.lastSelectedAt)
            record.queryHits = record.queryHits.filter { _, count in
                count > 0
            }
            trimQueries(in: &record)
            return record
        }

        let existingLastSelectedAt = merged.lastSelectedAt
        merged.selectionCount = saturatingSum(
            max(0, merged.selectionCount),
            max(0, incoming.selectionCount)
        )
        merged.lastSelectedAt = max(
            existingLastSelectedAt,
            incoming.lastSelectedAt
        )
        if incoming.lastSelectedAt >= existingLastSelectedAt {
            merged.appSessionKey = incoming.appSessionKey
        }

        for (query, count) in incoming.queryHits where count > 0 {
            merged.queryHits[query] = saturatingSum(
                max(0, merged.queryHits[query] ?? 0),
                count
            )
        }
        trimQueries(in: &merged)
        return merged
    }

    private func saturatingSum(_ lhs: Int, _ rhs: Int) -> Int {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int.max : sum
    }

    private func downgradeIfNeeded(_ record: inout Record, for appSessionKey: String) {
        guard record.appSessionKey != appSessionKey else {
            return
        }

        record.selectionCount = WindowRankingPolicy.downgradedSelectionCount(record.selectionCount)
        record.queryHits = record.queryHits.reduce(into: [:]) { result, entry in
            let downgradedCount = min(
                1,
                WindowRankingPolicy.downgradedSelectionCount(entry.value)
            )
            if downgradedCount > 0 {
                result[entry.key] = downgradedCount
            }
        }
        record.appSessionKey = appSessionKey
    }

    private func sessionMultiplier(
        for record: Record,
        currentAppSessionKey: String
    ) -> Double {
        record.appSessionKey == currentAppSessionKey
            ? 1
            : WindowRankingPolicy.previousSessionMultiplier
    }

    private func scaledForCurrentSession(
        _ score: Int,
        record: Record,
        currentAppSessionKey: String
    ) -> Int {
        Int(Double(score) * sessionMultiplier(
            for: record,
            currentAppSessionKey: currentAppSessionKey
        ))
    }

    private func relatedQueryBonus(record: Record, query: String) -> Int {
        var score = 0

        for (storedQuery, hits) in record.queryHits where storedQuery != query {
            if storedQuery.contains(query) || query.contains(storedQuery) {
                score += min(60, hits * 20)
            }
        }

        return min(60, score)
    }

    private func recordSessionActivity(
        _ item: WindowItem,
        at timestamp: TimeInterval,
        incrementSelectionCount: Bool
    ) {
        var record = sessionRecords[item.sessionMemoryKey] ?? SessionRecord(
            selectionCount: 0,
            lastUsedAt: 0
        )
        if incrementSelectionCount {
            record.selectionCount += 1
        }
        record.lastUsedAt = max(record.lastUsedAt, timestamp)
        sessionRecords[item.sessionMemoryKey] = record
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
                if lhs.value.lastUsedAt != rhs.value.lastUsedAt {
                    return lhs.value.lastUsedAt < rhs.value.lastUsedAt
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
