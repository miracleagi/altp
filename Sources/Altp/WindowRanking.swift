import AppKit
import ApplicationServices

enum WindowRanking {
    static func currentWindow(in items: [WindowItem]) -> WindowItem? {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            return items.first
        }

        let frontmostItems = items.filter { item in
            item.app.processIdentifier == frontmostApp.processIdentifier && !item.isMinimized
        }
        guard !frontmostItems.isEmpty else {
            return items.first
        }

        let axApp = AXUIElementCreateApplication(frontmostApp.processIdentifier)
        var focusedValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            axApp,
            kAXFocusedWindowAttribute as CFString,
            &focusedValue
        ) == .success,
           let focusedWindow = focusedValue {
            let focusedAXWindow = unsafeBitCast(focusedWindow, to: AXUIElement.self)
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
        let referenceTime = Date().timeIntervalSince1970
        return items.sorted { lhs, rhs in
            isPreferred(
                lhs,
                over: rhs,
                sourceWindow: sourceWindow,
                referenceTime: referenceTime
            )
        }
    }

    static func isPreferred(
        _ lhs: WindowItem,
        over rhs: WindowItem,
        sourceWindow: WindowItem?,
        referenceTime: TimeInterval = Date().timeIntervalSince1970
    ) -> Bool {
        let lhsTransitionRank = WindowSelectionMemory.shared.transitionRank(
            from: sourceWindow,
            to: lhs,
            referenceTime: referenceTime
        )
        let rhsTransitionRank = WindowSelectionMemory.shared.transitionRank(
            from: sourceWindow,
            to: rhs,
            referenceTime: referenceTime
        )
        if lhsTransitionRank.lastSelectedAt != rhsTransitionRank.lastSelectedAt {
            return lhsTransitionRank.lastSelectedAt > rhsTransitionRank.lastSelectedAt
        }
        if lhsTransitionRank.selectionCount != rhsTransitionRank.selectionCount {
            return lhsTransitionRank.selectionCount > rhsTransitionRank.selectionCount
        }

        let lhsSessionRank = WindowSelectionMemory.shared.sessionRank(
            for: lhs,
            referenceTime: referenceTime
        )
        let rhsSessionRank = WindowSelectionMemory.shared.sessionRank(
            for: rhs,
            referenceTime: referenceTime
        )
        if lhsSessionRank.lastSelectedAt != rhsSessionRank.lastSelectedAt {
            return lhsSessionRank.lastSelectedAt > rhsSessionRank.lastSelectedAt
        }
        if lhsSessionRank.selectionCount != rhsSessionRank.selectionCount {
            return lhsSessionRank.selectionCount > rhsSessionRank.selectionCount
        }

        let lhsUsageScore = WindowSelectionMemory.shared.rankingScore(
            for: lhs,
            referenceTime: referenceTime
        )
        let rhsUsageScore = WindowSelectionMemory.shared.rankingScore(
            for: rhs,
            referenceTime: referenceTime
        )
        if lhsUsageScore != rhsUsageScore {
            return lhsUsageScore > rhsUsageScore
        }

        if lhs.hasMeaningfulTitle != rhs.hasMeaningfulTitle {
            return lhs.hasMeaningfulTitle
        }

        if lhs.order != rhs.order {
            return lhs.order < rhs.order
        }

        if lhs.appName.localizedCaseInsensitiveCompare(rhs.appName) != .orderedSame {
            return lhs.appName.localizedCaseInsensitiveCompare(rhs.appName) == .orderedAscending
        }

        if lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) != .orderedSame {
            return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
        }

        if lhs.sessionSortKey != rhs.sessionSortKey {
            return lhs.sessionSortKey < rhs.sessionSortKey
        }

        return lhs.catalogIndex < rhs.catalogIndex
    }
}
