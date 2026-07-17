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

enum WindowRankingPolicy {
    static let previousSessionMultiplier = 0.2
    static let previousSessionSelectionCap = 3
    static let persistentHalfLifeDays = 3.0
    static let maximumPersistentAppScore = 40.0
    static let maximumPersistentWindowScore = 40.0

    static func preference(
        lhsSession: WindowSessionRank,
        rhsSession: WindowSessionRank,
        lhsPersistent: WindowPersistentRank,
        rhsPersistent: WindowPersistentRank,
        sameApplication: Bool
    ) -> Bool? {
        if lhsSession.lastUsedAt != rhsSession.lastUsedAt {
            return lhsSession.lastUsedAt > rhsSession.lastUsedAt
        }

        if lhsSession.interactionCount != rhsSession.interactionCount {
            return lhsSession.interactionCount > rhsSession.interactionCount
        }

        // A stable window identity is useful inside one application, but must not
        // give applications such as Cursor an extra cross-application score.
        if sameApplication,
           lhsPersistent.windowScore != rhsPersistent.windowScore {
            return lhsPersistent.windowScore > rhsPersistent.windowScore
        }

        if lhsPersistent.appScore != rhsPersistent.appScore {
            return lhsPersistent.appScore > rhsPersistent.appScore
        }

        return nil
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

        let rawScore = min(maximumScore, Double(selectionCount) * 2)
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
