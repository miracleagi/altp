import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

private func sortKey(
    relevanceScore: Int = 0,
    sessionScore: Double = 0,
    windowScore: Double = 0,
    applicationFallbackScore: Double = 0,
    visualOrder: Int
) -> WindowSortKey {
    WindowSortKey(
        relevanceScore: relevanceScore,
        sessionScore: sessionScore,
        persistentScore: windowScore + applicationFallbackScore,
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
        applicationIdentifier: "unstable-app",
        identifier: 1,
        sessionScore: 90,
        visualOrder: 4,
        catalogIndex: 1,
        hasWindowHistory: false
    ),
    WindowApplicationFallbackCandidate(
        applicationIdentifier: "unstable-app",
        identifier: 2,
        sessionScore: 0,
        visualOrder: 0,
        catalogIndex: 2,
        hasWindowHistory: false
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
    windowScore: 30,
    visualOrder: 2
)
let unrelatedWindow = sortKey(
    windowScore: 4,
    visualOrder: 1
)
let unusedCursorSibling = sortKey(
    visualOrder: 0
)
let siblingRegressionOrder = [unusedCursorSibling, unrelatedWindow, usedCursorWorkspace]
    .sorted { WindowRankingPolicy.prefers($0, over: $1) }
expect(
    siblingRegressionOrder == [usedCursorWorkspace, unrelatedWindow, unusedCursorSibling],
    "using one Cursor workspace must not pull every Cursor sibling above unrelated windows"
)

let formerlyCyclicKeys = [
    sortKey(windowScore: 40, visualOrder: 2),
    sortKey(visualOrder: 0),
    sortKey(applicationFallbackScore: 20, visualOrder: 1)
]
let deterministicOrder = formerlyCyclicKeys
    .sorted { WindowRankingPolicy.prefers($0, over: $1) }
expect(
    deterministicOrder.map(\.persistentScore) == [40, 20, 0],
    "sorting must use one transitive key instead of pair-dependent application rules"
)

let fiveSecondSessionScore = WindowRankingPolicy.sessionScore(
    for: WindowSessionRank(lastUsedAt: now - 5, interactionCount: 1),
    referenceTime: now
)
let fiveMinuteSessionScore = WindowRankingPolicy.sessionScore(
    for: WindowSessionRank(lastUsedAt: now - 300, interactionCount: 1),
    referenceTime: now
)
let recentWithoutHistory = sortKey(
    sessionScore: fiveSecondSessionScore,
    visualOrder: 2
)
let olderWithSaturatedHistory = sortKey(
    sessionScore: fiveMinuteSessionScore,
    windowScore: WindowRankingPolicy.maximumPersistentWindowScore,
    visualOrder: 1
)
expect(
    WindowRankingPolicy.prefers(recentWithoutHistory, over: olderWithSaturatedHistory),
    "a five-second-old session must beat a five-minute-old window even when the older window has saturated persistent history"
)

let strongerSearchMatch = sortKey(
    relevanceScore: 700,
    visualOrder: 2
)
let weakerSearchMatchWithHistory = sortKey(
    relevanceScore: 550,
    sessionScore: fiveSecondSessionScore,
    windowScore: WindowRankingPolicy.maximumPersistentWindowScore,
    visualOrder: 1
)
expect(
    WindowRankingPolicy.prefers(strongerSearchMatch, over: weakerSearchMatchWithHistory),
    "search relevance must be decided before session and persistent history"
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

let expiredPersistentScore = WindowRankingPolicy.persistentScore(
    selectionCount: 100,
    lastSelectedAt: now - WindowRankingPolicy.persistentHorizonDays * 86_400 - 1,
    maximumScore: WindowRankingPolicy.maximumPersistentWindowScore,
    referenceTime: now
)
expect(
    expiredPersistentScore == 0,
    "persistent history must become exactly zero after its horizon"
)
let subEpsilonPersistentScore = WindowRankingPolicy.persistentScore(
    selectionCount: 1,
    lastSelectedAt: now - 4 * 86_400,
    maximumScore: WindowRankingPolicy.maximumPersistentWindowScore,
    referenceTime: now
)
expect(
    subEpsilonPersistentScore == 0,
    "persistent history below the ranking epsilon must become exactly zero"
)

let completeCursorCandidates = [
    WindowApplicationFallbackCandidate(
        applicationIdentifier: "cursor",
        identifier: 10,
        sessionScore: 80,
        visualOrder: 1,
        catalogIndex: 10,
        hasWindowHistory: true
    ),
    WindowApplicationFallbackCandidate(
        applicationIdentifier: "cursor",
        identifier: 11,
        sessionScore: 0,
        visualOrder: 2,
        catalogIndex: 11,
        hasWindowHistory: false
    )
]
let completeCatalogFallbacks =
    WindowRankingPolicy.applicationFallbackRepresentatives(
        candidates: completeCursorCandidates
    )
let searchFilteredCursorIdentifiers = Set([11])
expect(
    completeCatalogFallbacks["cursor"] == nil
        && !searchFilteredCursorIdentifiers.contains(
            completeCatalogFallbacks["cursor"] ?? -1
        ),
    "filtering search results must not let an unused sibling inherit application history"
)

let sameAppDifferentSessionCandidates = [
    WindowApplicationFallbackCandidate(
        applicationIdentifier: "same-app|pid:101",
        identifier: 20,
        sessionScore: 60,
        visualOrder: 2,
        catalogIndex: 20,
        hasWindowHistory: false
    ),
    WindowApplicationFallbackCandidate(
        applicationIdentifier: "same-app|pid:101",
        identifier: 21,
        sessionScore: 10,
        visualOrder: 1,
        catalogIndex: 21,
        hasWindowHistory: false
    ),
    WindowApplicationFallbackCandidate(
        applicationIdentifier: "same-app|pid:202",
        identifier: 22,
        sessionScore: 40,
        visualOrder: 3,
        catalogIndex: 22,
        hasWindowHistory: false
    ),
    WindowApplicationFallbackCandidate(
        applicationIdentifier: "same-app|pid:202",
        identifier: 23,
        sessionScore: 5,
        visualOrder: 0,
        catalogIndex: 23,
        hasWindowHistory: false
    )
]
let sameAppDifferentSessionFallbacks =
    WindowRankingPolicy.applicationFallbackRepresentatives(
        candidates: sameAppDifferentSessionCandidates
    )
expect(
    sameAppDifferentSessionFallbacks == [
        "same-app|pid:101": 20,
        "same-app|pid:202": 22
    ],
    "separate running instances of one application must choose fallback representatives independently"
)

print("Window ranking harness passed")
