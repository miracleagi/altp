import AppKit
import ApplicationServices

enum WindowRanking {
    struct FocusSnapshot {
        fileprivate let application: NSRunningApplication
        fileprivate let focusedWindow: AXUIElement?
    }

    private struct EvaluatedWindow {
        let item: WindowItem
        let baseScore: Int
        let sessionScore: Double
        let sessionInteractionCount: Int
        let persistentRank: WindowPersistentRank
    }

    private struct RankedWindow {
        let item: WindowItem
        let sortKey: WindowSortKey
    }

    static func captureCurrentFocus() -> FocusSnapshot? {
        guard let application = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        let axApp = AXUIElementCreateApplication(application.processIdentifier)
        var focusedValue: CFTypeRef?
        let focusedWindow: AXUIElement?
        if AXUIElementCopyAttributeValue(
            axApp,
            kAXFocusedWindowAttribute as CFString,
            &focusedValue
        ) == .success,
           let focusedValue {
            focusedWindow = unsafeBitCast(focusedValue, to: AXUIElement.self)
        } else {
            focusedWindow = nil
        }

        return FocusSnapshot(
            application: application,
            focusedWindow: focusedWindow
        )
    }

    static func currentWindow(in items: [WindowItem]) -> WindowItem? {
        currentWindow(in: items, focusSnapshot: captureCurrentFocus())
    }

    static func currentWindow(
        in items: [WindowItem],
        focusSnapshot: FocusSnapshot?
    ) -> WindowItem? {
        guard let focusSnapshot else {
            return nil
        }

        let frontmostItems = items.filter { item in
            item.app.processIdentifier == focusSnapshot.application.processIdentifier
                && !item.isMinimized
        }
        guard !frontmostItems.isEmpty else {
            return nil
        }

        if let focusedAXWindow = focusSnapshot.focusedWindow {
            if let exactMatch = frontmostItems.first(where: { item in
                CFEqual(item.axWindow, focusedAXWindow)
            }) {
                return exactMatch
            }
        }

        return frontmostItems.first
    }

    static func sortedForEmptyQuery(
        _ items: [WindowItem],
        sourceWindow: WindowItem?
    ) -> [WindowItem] {
        sorted(items, sourceWindow: sourceWindow) { _ in 0 }
    }

    static func sortedForQuery(
        _ items: [(item: WindowItem, score: Int)],
        sourceWindow: WindowItem?
    ) -> [WindowItem] {
        let scoreByItem = Dictionary(
            uniqueKeysWithValues: items.map { candidate in
                (ObjectIdentifier(candidate.item), candidate.score)
            }
        )
        return sorted(items.map(\.item), sourceWindow: sourceWindow) { item in
            scoreByItem[ObjectIdentifier(item)] ?? 0
        }
    }

    private static func sorted(
        _ items: [WindowItem],
        sourceWindow: WindowItem?,
        baseScore: (WindowItem) -> Int
    ) -> [WindowItem] {
        let referenceTime = Date().timeIntervalSince1970
        let evaluated = items.map { item in
            let sessionRank = WindowSelectionMemory.shared.sessionRank(
                for: item,
                from: sourceWindow,
                referenceTime: referenceTime
            )
            return EvaluatedWindow(
                item: item,
                baseScore: baseScore(item),
                sessionScore: WindowRankingPolicy.sessionScore(
                    for: sessionRank,
                    referenceTime: referenceTime
                ),
                sessionInteractionCount: sessionRank.interactionCount,
                persistentRank: WindowSelectionMemory.shared.persistentRank(
                    for: item,
                    referenceTime: referenceTime
                )
            )
        }

        let fallbackRepresentatives = applicationFallbackRepresentatives(in: evaluated)
        let ranked = evaluated.map { candidate -> RankedWindow in
            let item = candidate.item
            let isFallbackRepresentative = fallbackRepresentatives[item.appMemoryKey] == item.catalogIndex
            let applicationFallbackScore = isFallbackRepresentative
                ? candidate.persistentRank.appScore
                : 0
            let totalScore = Double(candidate.baseScore)
                + candidate.sessionScore
                + candidate.persistentRank.windowScore
                + applicationFallbackScore

            return RankedWindow(
                item: item,
                sortKey: WindowSortKey(
                    totalScore: totalScore,
                    sessionScore: candidate.sessionScore,
                    sessionInteractionCount: candidate.sessionInteractionCount,
                    windowScore: candidate.persistentRank.windowScore,
                    applicationFallbackScore: applicationFallbackScore,
                    hasMeaningfulTitle: item.hasMeaningfulTitle,
                    visualOrder: item.order,
                    appName: item.appName,
                    windowTitle: item.displayTitle,
                    sessionSortKey: item.sessionSortKey,
                    catalogIndex: item.catalogIndex
                )
            )
        }

        return ranked
            .sorted { lhs, rhs in
                WindowRankingPolicy.prefers(lhs.sortKey, over: rhs.sortKey)
            }
            .map { $0.item }
    }

    private static func applicationFallbackRepresentatives(
        in evaluated: [EvaluatedWindow]
    ) -> [String: Int] {
        let groupedByApplication = Dictionary(grouping: evaluated) { candidate in
            candidate.item.appMemoryKey
        }

        return groupedByApplication.reduce(into: [:]) { result, group in
            let candidates = group.value
            let representative = WindowRankingPolicy.applicationFallbackRepresentative(
                candidates: candidates.map { candidate in
                    WindowApplicationFallbackCandidate(
                        identifier: candidate.item.catalogIndex,
                        sessionScore: candidate.sessionScore,
                        visualOrder: candidate.item.order,
                        catalogIndex: candidate.item.catalogIndex
                    )
                },
                hasWindowHistory: candidates.contains { candidate in
                    candidate.persistentRank.windowScore > 0
                }
            )
            if let representative {
                result[group.key] = representative
            }
        }
    }
}
