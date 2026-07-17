import AppKit
import ApplicationServices

enum WindowRanking {
    static func currentWindow(in items: [WindowItem]) -> WindowItem? {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        let frontmostItems = items.filter { item in
            item.app.processIdentifier == frontmostApp.processIdentifier && !item.isMinimized
        }
        guard !frontmostItems.isEmpty else {
            return nil
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
        let lhsSessionRank = WindowSelectionMemory.shared.sessionRank(
            for: lhs,
            from: sourceWindow,
            referenceTime: referenceTime
        )
        let rhsSessionRank = WindowSelectionMemory.shared.sessionRank(
            for: rhs,
            from: sourceWindow,
            referenceTime: referenceTime
        )
        let lhsPersistentRank = WindowSelectionMemory.shared.persistentRank(
            for: lhs,
            referenceTime: referenceTime
        )
        let rhsPersistentRank = WindowSelectionMemory.shared.persistentRank(
            for: rhs,
            referenceTime: referenceTime
        )
        if let preference = WindowRankingPolicy.preference(
            lhsSession: lhsSessionRank,
            rhsSession: rhsSessionRank,
            lhsPersistent: lhsPersistentRank,
            rhsPersistent: rhsPersistentRank,
            sameApplication: lhs.appMemoryKey == rhs.appMemoryKey
        ) {
            return preference
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
