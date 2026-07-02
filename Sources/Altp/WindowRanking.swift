import AppKit

enum WindowRanking {
    static func currentWindow(in items: [WindowItem]) -> WindowItem? {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            return items.first
        }

        return items.first { item in
            item.app.processIdentifier == frontmostApp.processIdentifier && !item.isMinimized
        } ?? items.first
    }

    static func sortedForEmptyQuery(
        _ items: [WindowItem],
        sourceWindow: WindowItem?
    ) -> [WindowItem] {
        items.sorted { lhs, rhs in
            isPreferred(lhs, over: rhs, sourceWindow: sourceWindow)
        }
    }

    static func isPreferred(
        _ lhs: WindowItem,
        over rhs: WindowItem,
        sourceWindow: WindowItem?
    ) -> Bool {
        let lhsTransitionScore = WindowSelectionMemory.shared.transitionScore(from: sourceWindow, to: lhs)
        let rhsTransitionScore = WindowSelectionMemory.shared.transitionScore(from: sourceWindow, to: rhs)
        if lhsTransitionScore != rhsTransitionScore {
            return lhsTransitionScore > rhsTransitionScore
        }

        let lhsStats = WindowSelectionMemory.shared.usageStats(for: lhs)
        let rhsStats = WindowSelectionMemory.shared.usageStats(for: rhs)
        if lhsStats.selectionCount != rhsStats.selectionCount {
            return lhsStats.selectionCount > rhsStats.selectionCount
        }

        if lhsStats.appSelectionCount != rhsStats.appSelectionCount {
            return lhsStats.appSelectionCount > rhsStats.appSelectionCount
        }

        if lhsStats.hasSelections, rhsStats.hasSelections,
           lhsStats.latestSelectedAt != rhsStats.latestSelectedAt {
            return lhsStats.latestSelectedAt > rhsStats.latestSelectedAt
        }

        if lhs.hasMeaningfulTitle != rhs.hasMeaningfulTitle {
            return lhs.hasMeaningfulTitle
        }

        return lhs.order < rhs.order
    }
}
