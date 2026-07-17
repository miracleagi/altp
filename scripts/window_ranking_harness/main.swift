import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let now: TimeInterval = 1_000_000
let historicalCursor = WindowPersistentRank(appScore: 40, windowScore: 40)
let weakHistory = WindowPersistentRank(appScore: 2, windowScore: 0)

let usedAnHourAgo = WindowSessionRank(
    lastUsedAt: now - 60 * 60,
    interactionCount: 1
)
expect(
    WindowRankingPolicy.preference(
        lhsSession: usedAnHourAgo,
        rhsSession: .none,
        lhsPersistent: weakHistory,
        rhsPersistent: historicalCursor,
        sameApplication: false
    ) == true,
    "current-session activity must still outrank historical Cursor after the old 10-minute horizon"
)

let recentlyUsedPair = WindowSessionRank(lastUsedAt: now - 5, interactionCount: 2)
let olderCursorSession = WindowSessionRank(lastUsedAt: now - 300, interactionCount: 50)
expect(
    WindowRankingPolicy.preference(
        lhsSession: recentlyUsedPair,
        rhsSession: olderCursorSession,
        lhsPersistent: weakHistory,
        rhsPersistent: historicalCursor,
        sameApplication: false
    ) == true,
    "the recently used pair must beat a frequently selected Cursor window"
)

expect(
    WindowRankingPolicy.preference(
        lhsSession: .none,
        rhsSession: .none,
        lhsPersistent: WindowPersistentRank(appScore: 10, windowScore: 40),
        rhsPersistent: WindowPersistentRank(appScore: 20, windowScore: 0),
        sameApplication: false
    ) == false,
    "a Cursor workspace score must not add an extra cross-application advantage"
)

expect(
    WindowRankingPolicy.preference(
        lhsSession: .none,
        rhsSession: .none,
        lhsPersistent: WindowPersistentRank(appScore: 20, windowScore: 30),
        rhsPersistent: WindowPersistentRank(appScore: 20, windowScore: 10),
        sameApplication: true
    ) == true,
    "stable workspace identity must still distinguish windows inside Cursor"
)

let freshScore = WindowRankingPolicy.persistentScore(
    selectionCount: 100,
    lastSelectedAt: now,
    maximumScore: WindowRankingPolicy.maximumPersistentAppScore,
    referenceTime: now
)
let threeDayScore = WindowRankingPolicy.persistentScore(
    selectionCount: 100,
    lastSelectedAt: now - 3 * 86_400,
    maximumScore: WindowRankingPolicy.maximumPersistentAppScore,
    referenceTime: now
)
expect(abs(threeDayScore - freshScore / 2) < 0.001, "persistent score must have a three-day half-life")

let previousSessionScore = WindowRankingPolicy.persistentScore(
    selectionCount: 100,
    lastSelectedAt: now,
    maximumScore: WindowRankingPolicy.maximumPersistentAppScore,
    referenceTime: now,
    sessionMultiplier: WindowRankingPolicy.previousSessionMultiplier
)
expect(abs(previousSessionScore - freshScore * 0.2) < 0.001, "restarted apps must receive the previous-session multiplier")
expect(
    WindowRankingPolicy.downgradedSelectionCount(338) == 3,
    "the first selection after restart must not immediately restore a saturated historical count"
)

print("Window ranking harness passed")
