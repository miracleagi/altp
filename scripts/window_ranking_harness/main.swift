import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

private func sortKey(
    totalScore: Double,
    sessionScore: Double = 0,
    windowScore: Double = 0,
    applicationFallbackScore: Double = 0,
    visualOrder: Int
) -> WindowSortKey {
    WindowSortKey(
        totalScore: totalScore,
        sessionScore: sessionScore,
        sessionInteractionCount: 0,
        windowScore: windowScore,
        applicationFallbackScore: applicationFallbackScore,
        hasMeaningfulTitle: true,
        visualOrder: visualOrder,
        appName: "App",
        windowTitle: "Window \(visualOrder)",
        sessionSortKey: UInt(visualOrder),
        catalogIndex: visualOrder
    )
}

let now: TimeInterval = 1_000_000

let usedAnHourAgo = WindowSessionRank(
    lastUsedAt: now - 60 * 60,
    interactionCount: 1
)
expect(
    WindowRankingPolicy.sessionScore(for: usedAnHourAgo, referenceTime: now) >
        WindowRankingPolicy.maximumPersistentWindowScore,
    "an hour-old session interaction must beat saturated persistent history"
)

let expiredSession = WindowSessionRank(
    lastUsedAt: now - (WindowRankingPolicy.sessionHorizonHours * 3_600 + 1),
    interactionCount: 100
)
expect(
    WindowRankingPolicy.sessionScore(for: expiredSession, referenceTime: now) == 0,
    "session activity must expire instead of outranking untouched windows forever"
)

let recentlyUsedPair = WindowSessionRank(lastUsedAt: now - 5, interactionCount: 2)
let olderFrequentWindow = WindowSessionRank(lastUsedAt: now - 300, interactionCount: 50)
expect(
    WindowRankingPolicy.sessionScore(for: recentlyUsedPair, referenceTime: now) >
        WindowRankingPolicy.sessionScore(for: olderFrequentWindow, referenceTime: now),
    "recent switching must beat an older frequently selected window"
)

let fallbackCandidates = [
    WindowApplicationFallbackCandidate(
        identifier: 1,
        sessionScore: 90,
        visualOrder: 4,
        catalogIndex: 1
    ),
    WindowApplicationFallbackCandidate(
        identifier: 2,
        sessionScore: 0,
        visualOrder: 0,
        catalogIndex: 2
    )
]
expect(
    WindowRankingPolicy.applicationFallbackRepresentative(
        candidates: fallbackCandidates,
        hasWindowHistory: false
    ) == 1,
    "an identity-unstable application must give its fallback score to only its active representative"
)
expect(
    WindowRankingPolicy.applicationFallbackRepresentative(
        candidates: fallbackCandidates,
        hasWindowHistory: true
    ) == nil,
    "an application with stable window history must not spread app history to sibling windows"
)

let usedCursorWorkspace = sortKey(
    totalScore: 30,
    windowScore: 30,
    visualOrder: 2
)
let unrelatedWindow = sortKey(
    totalScore: 4,
    windowScore: 4,
    visualOrder: 1
)
let unusedCursorSibling = sortKey(
    totalScore: 0,
    visualOrder: 0
)
let siblingRegressionOrder = [unusedCursorSibling, unrelatedWindow, usedCursorWorkspace]
    .sorted { WindowRankingPolicy.prefers($0, over: $1) }
expect(
    siblingRegressionOrder == [usedCursorWorkspace, unrelatedWindow, unusedCursorSibling],
    "using one Cursor workspace must not pull every Cursor sibling above unrelated windows"
)

let formerlyCyclicKeys = [
    sortKey(totalScore: 40, windowScore: 40, visualOrder: 2),
    sortKey(totalScore: 0, visualOrder: 0),
    sortKey(totalScore: 20, applicationFallbackScore: 20, visualOrder: 1)
]
let deterministicOrder = formerlyCyclicKeys
    .sorted { WindowRankingPolicy.prefers($0, over: $1) }
expect(
    deterministicOrder.map(\.totalScore) == [40, 20, 0],
    "sorting must use one transitive key instead of pair-dependent application rules"
)

let twentySelections = WindowRankingPolicy.persistentScore(
    selectionCount: 20,
    lastSelectedAt: now,
    maximumScore: WindowRankingPolicy.maximumPersistentWindowScore,
    referenceTime: now
)
let fortySelections = WindowRankingPolicy.persistentScore(
    selectionCount: 40,
    lastSelectedAt: now,
    maximumScore: WindowRankingPolicy.maximumPersistentWindowScore,
    referenceTime: now
)
expect(
    fortySelections > twentySelections,
    "persistent frequency must not saturate after only twenty selections"
)

let oneDayScore = WindowRankingPolicy.persistentScore(
    selectionCount: 100,
    lastSelectedAt: now - 86_400,
    maximumScore: WindowRankingPolicy.maximumPersistentWindowScore,
    referenceTime: now
)
let freshScore = WindowRankingPolicy.persistentScore(
    selectionCount: 100,
    lastSelectedAt: now,
    maximumScore: WindowRankingPolicy.maximumPersistentWindowScore,
    referenceTime: now
)
expect(
    abs(oneDayScore - freshScore / 2) < 0.001,
    "persistent score must have a one-day half-life"
)

let previousSessionScore = WindowRankingPolicy.persistentScore(
    selectionCount: 100,
    lastSelectedAt: now,
    maximumScore: WindowRankingPolicy.maximumPersistentAppScore,
    referenceTime: now,
    sessionMultiplier: WindowRankingPolicy.previousSessionMultiplier
)
expect(
    abs(previousSessionScore - freshScore * 0.2) < 0.001,
    "restarted applications must receive the previous-session multiplier"
)
expect(
    WindowRankingPolicy.downgradedSelectionCount(338) == 3,
    "the first selection after restart must not restore saturated historical frequency"
)

print("Window ranking harness passed")
