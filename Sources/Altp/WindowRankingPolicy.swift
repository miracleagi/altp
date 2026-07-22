import Foundation

struct WindowSessionRank: Equatable {
    static let none = WindowSessionRank(lastUsedAt: 0, interactionCount: 0)

    let lastUsedAt: TimeInterval
    let interactionCount: Int
}

struct WindowPersistentRank: Equatable {
    static let none = WindowPersistentRank(appScore: 0, windowScore: 0)

    let appScore: Double
    let windowScore: Double
}

struct WindowApplicationFallbackCandidate: Equatable {
    let identifier: Int
    let sessionScore: Double
    let visualOrder: Int
    let catalogIndex: Int
}

struct WindowSortKey: Equatable {
    let totalScore: Double
    let sessionScore: Double
    let sessionInteractionCount: Int
    let windowScore: Double
    let applicationFallbackScore: Double
    let hasMeaningfulTitle: Bool
    let visualOrder: Int
    let appName: String
    let windowTitle: String
    let sessionSortKey: UInt
    let catalogIndex: Int
}

enum WindowRankingPolicy {
    static let previousSessionMultiplier = 0.2
    static let previousSessionSelectionCap = 3
    static let persistentHalfLifeDays = 1.0
    static let sessionHalfLifeHours = 4.0
    static let sessionHorizonHours = 24.0
    static let maximumPersistentAppScore = 40.0
    static let maximumPersistentWindowScore = 40.0
    static let baseSessionScore = 100.0

    static func sessionScore(
        for rank: WindowSessionRank,
        referenceTime: TimeInterval
    ) -> Double {
        guard rank.lastUsedAt > 0 else {
            return 0
        }

        let ageSeconds = max(0, referenceTime - rank.lastUsedAt)
        guard ageSeconds <= sessionHorizonHours * 3_600 else {
            return 0
        }

        return decayedScore(
            baseSessionScore,
            lastUsedAt: rank.lastUsedAt,
            halfLifeDays: sessionHalfLifeHours / 24,
            referenceTime: referenceTime
        )
    }

    static func applicationFallbackRepresentative(
        candidates: [WindowApplicationFallbackCandidate],
        hasWindowHistory: Bool
    ) -> Int? {
        guard !hasWindowHistory else {
            return nil
        }

        return candidates.min { lhs, rhs in
            if lhs.sessionScore != rhs.sessionScore {
                return lhs.sessionScore > rhs.sessionScore
            }
            if lhs.visualOrder != rhs.visualOrder {
                return lhs.visualOrder < rhs.visualOrder
            }
            return lhs.catalogIndex < rhs.catalogIndex
        }?.identifier
    }

    static func prefers(_ lhs: WindowSortKey, over rhs: WindowSortKey) -> Bool {
        if lhs.totalScore != rhs.totalScore {
            return lhs.totalScore > rhs.totalScore
        }
        if lhs.sessionScore != rhs.sessionScore {
            return lhs.sessionScore > rhs.sessionScore
        }
        if lhs.sessionInteractionCount != rhs.sessionInteractionCount {
            return lhs.sessionInteractionCount > rhs.sessionInteractionCount
        }
        if lhs.windowScore != rhs.windowScore {
            return lhs.windowScore > rhs.windowScore
        }
        if lhs.applicationFallbackScore != rhs.applicationFallbackScore {
            return lhs.applicationFallbackScore > rhs.applicationFallbackScore
        }
        if lhs.hasMeaningfulTitle != rhs.hasMeaningfulTitle {
            return lhs.hasMeaningfulTitle
        }
        if lhs.visualOrder != rhs.visualOrder {
            return lhs.visualOrder < rhs.visualOrder
        }

        let appComparison = lhs.appName.localizedCaseInsensitiveCompare(rhs.appName)
        if appComparison != .orderedSame {
            return appComparison == .orderedAscending
        }

        let titleComparison = lhs.windowTitle.localizedCaseInsensitiveCompare(rhs.windowTitle)
        if titleComparison != .orderedSame {
            return titleComparison == .orderedAscending
        }
        if lhs.sessionSortKey != rhs.sessionSortKey {
            return lhs.sessionSortKey < rhs.sessionSortKey
        }
        return lhs.catalogIndex < rhs.catalogIndex
    }

    static func persistentScore(
        selectionCount: Int,
        lastSelectedAt: TimeInterval,
        maximumScore: Double,
        referenceTime: TimeInterval,
        sessionMultiplier: Double = 1
    ) -> Double {
        guard selectionCount > 0,
              lastSelectedAt > 0,
              maximumScore > 0,
              sessionMultiplier > 0 else {
            return 0
        }

        let rawScore = min(
            maximumScore,
            log2(Double(selectionCount) + 1) * 6
        )
        return decayedScore(
            rawScore,
            lastUsedAt: lastSelectedAt,
            halfLifeDays: persistentHalfLifeDays,
            referenceTime: referenceTime
        ) * sessionMultiplier
    }

    static func decayedScore(
        _ score: Double,
        lastUsedAt: TimeInterval,
        halfLifeDays: Double,
        referenceTime: TimeInterval
    ) -> Double {
        guard score > 0, lastUsedAt > 0, halfLifeDays > 0 else {
            return 0
        }

        let ageSeconds = max(0, referenceTime - lastUsedAt)
        let halfLifeSeconds = halfLifeDays * 86_400
        return score * pow(0.5, ageSeconds / halfLifeSeconds)
    }

    static func downgradedSelectionCount(_ selectionCount: Int) -> Int {
        min(
            previousSessionSelectionCap,
            Int(Double(selectionCount) * previousSessionMultiplier)
        )
    }
}
