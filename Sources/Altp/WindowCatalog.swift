import AppKit
import ApplicationServices

final class WindowItem: NSObject {
    let app: NSRunningApplication
    let axWindow: AXUIElement
    let title: String
    let appName: String
    let bundleIdentifier: String?
    let isMinimized: Bool
    let isHidden: Bool
    let role: String
    let subrole: String
    let document: String
    let identifier: String
    let frame: CGRect?
    let order: Int
    let catalogIndex: Int
    let sessionSortKey: CFHashCode

    init(
        app: NSRunningApplication,
        axWindow: AXUIElement,
        title: String,
        appName: String,
        bundleIdentifier: String?,
        isMinimized: Bool,
        isHidden: Bool,
        role: String,
        subrole: String,
        document: String,
        identifier: String,
        frame: CGRect?,
        order: Int,
        catalogIndex: Int
    ) {
        self.app = app
        self.axWindow = axWindow
        self.title = title
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.isMinimized = isMinimized
        self.isHidden = isHidden
        self.role = role
        self.subrole = subrole
        self.document = document
        self.identifier = identifier
        self.frame = frame
        self.order = order
        self.catalogIndex = catalogIndex
        self.sessionSortKey = CFHash(axWindow)
    }

    var displayTitle: String {
        title.isEmpty ? "Untitled Window" : title
    }

    var hasMeaningfulTitle: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var subtitle: String {
        var parts = [appName]

        if isMinimized {
            parts.append("minimized")
        }

        if isHidden {
            parts.append("hidden")
        }

        if let frame {
            parts.append("\(Int(frame.width)) x \(Int(frame.height))")
        }

        return parts.joined(separator: " - ")
    }

    var icon: NSImage? {
        app.icon
    }

    var searchableText: String {
        SearchText.searchableText(for: [
            title,
            appName,
            bundleIdentifier ?? "",
            subrole
        ])
    }

    var persistentMemoryKey: String? {
        if isCursorWindow {
            return [
                normalizedIdentityPart(bundleIdentifier ?? appName),
                normalizedIdentityPart(subrole),
                cursorWorkspaceIdentity
            ]
            .joined(separator: "|")
        }

        if isChromeWindow {
            return nil
        }

        return [
            normalizedIdentityPart(bundleIdentifier ?? appName),
            normalizedIdentityPart(title),
            normalizedIdentityPart(subrole),
            persistentIdentityHint
        ]
        .joined(separator: "|")
    }

    var appMemoryKey: String {
        normalizedIdentityPart(bundleIdentifier ?? appName)
    }

    var appSessionKey: String {
        "\(appMemoryKey)|pid:\(app.processIdentifier)"
    }

    var sessionMemoryKey: String {
        [
            appSessionKey,
            normalizedIdentityPart(subrole),
            "window:\(sessionSortKey)"
        ]
        .joined(separator: "|")
    }

    func representsSameWindow(as other: WindowItem) -> Bool {
        CFEqual(axWindow, other.axWindow)
    }

    private var isCursorWindow: Bool {
        bundleIdentifier?.lowercased() == "com.todesktop.230313mzl4w4u92" ||
            normalizedIdentityPart(appName) == "cursor"
    }

    private var isChromeWindow: Bool {
        bundleIdentifier?.lowercased().hasPrefix("com.google.chrome") == true ||
            normalizedIdentityPart(appName) == "google chrome"
    }

    private var cursorWorkspaceIdentity: String {
        if let separatorRange = title.range(of: " — ", options: .backwards) {
            let workspace = normalizedIdentityPart(String(title[separatorRange.upperBound...]))
            if !workspace.isEmpty {
                return "workspace:\(workspace)"
            }
        }

        let normalizedIdentifier = normalizedIdentityPart(identifier)
        if !normalizedIdentifier.isEmpty {
            return "identifier:\(normalizedIdentifier)"
        }

        guard let frame else {
            return "window:default"
        }

        return "frame:\(Int(frame.origin.x.rounded())),\(Int(frame.origin.y.rounded())),\(Int(frame.width.rounded())),\(Int(frame.height.rounded()))"
    }

    private var persistentIdentityHint: String {
        let normalizedDocument = normalizedIdentityPart(document)
        if !normalizedDocument.isEmpty {
            return "document:\(normalizedDocument)"
        }

        let normalizedIdentifier = normalizedIdentityPart(identifier)
        if !normalizedIdentifier.isEmpty {
            return "identifier:\(normalizedIdentifier)"
        }

        guard let frame else {
            return "frame:unknown"
        }

        return "frame:\(Int(frame.origin.x.rounded())),\(Int(frame.origin.y.rounded())),\(Int(frame.width.rounded())),\(Int(frame.height.rounded()))"
    }

}

final class WindowCatalog {
    func allWindows() -> [WindowItem] {
        guard AccessibilityPermission.isTrusted else {
            return []
        }

        let showMinimizedWindows = AppSettings.showMinimizedWindows
        let excludedTitlePatterns = AppSettings.excludedWindowTitlePatterns.map(normalizedIdentityPart)
        let visibleOrder = WindowOrdering.snapshot()
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications
            .filter { app in
                app.activationPolicy == .regular &&
                    app.processIdentifier != currentPID &&
                    !app.isTerminated
            }

        var results: [WindowItem] = []
        var nextCatalogIndex = 0

        for (appIndex, app) in apps.enumerated() {
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            guard let windows = copyAttribute(axApp, kAXWindowsAttribute as CFString) as? [AXUIElement] else {
                continue
            }

            for (windowIndex, window) in windows.enumerated() {
                let role = axString(window, kAXRoleAttribute as CFString) ?? ""
                guard role == kAXWindowRole as String || role == "AXWindow" else {
                    continue
                }

                let subrole = axString(window, kAXSubroleAttribute as CFString) ?? ""
                let title = axString(window, kAXTitleAttribute as CFString) ?? ""
                let document = axString(window, kAXDocumentAttribute as CFString) ?? ""
                let identifier = axString(window, kAXIdentifierAttribute as CFString) ?? ""
                let frame = axFrame(window)
                let isMinimized = axBool(window, kAXMinimizedAttribute as CFString) ?? false
                let isHidden = app.isHidden
                let appName = app.localizedName ?? app.bundleIdentifier ?? "Unknown App"

                if shouldExcludeUntitledAuxiliaryWindow(
                    appName: appName,
                    bundleIdentifier: app.bundleIdentifier,
                    title: title
                ) {
                    continue
                }

                if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   frame?.isEmpty != false {
                    continue
                }

                if isHidden {
                    continue
                }

                if isMinimized && !showMinimizedWindows {
                    continue
                }

                if isExcludedWindowTitle(title, excludedTitlePatterns: excludedTitlePatterns) {
                    continue
                }

                let key = WindowOrdering.key(pid: app.processIdentifier, title: title, frame: frame)
                let order = visibleOrder[key] ?? (10_000 + appIndex * 100 + windowIndex)
                let catalogIndex = nextCatalogIndex
                nextCatalogIndex += 1

                results.append(WindowItem(
                    app: app,
                    axWindow: window,
                    title: title,
                    appName: appName,
                    bundleIdentifier: app.bundleIdentifier,
                    isMinimized: isMinimized,
                    isHidden: isHidden,
                    role: role,
                    subrole: subrole,
                    document: document,
                    identifier: identifier,
                    frame: frame,
                    order: order,
                    catalogIndex: catalogIndex
                ))
            }
        }

        return deduplicateFeishuMeetingWindows(results).sorted { lhs, rhs in
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

    @discardableResult
    func activate(_ item: WindowItem) -> AXError {
        if item.isMinimized {
            AXUIElementSetAttributeValue(
                item.axWindow,
                kAXMinimizedAttribute as CFString,
                kCFBooleanFalse
            )
        }

        item.app.unhide()
        item.app.activate(options: [.activateIgnoringOtherApps])

        AXUIElementSetAttributeValue(
            item.axWindow,
            kAXMainAttribute as CFString,
            kCFBooleanTrue
        )
        AXUIElementSetAttributeValue(
            item.axWindow,
            kAXFocusedAttribute as CFString,
            kCFBooleanTrue
        )

        return AXUIElementPerformAction(item.axWindow, kAXRaiseAction as CFString)
    }
}

private enum WindowOrdering {
    static func snapshot() -> [String: Int] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let rawWindows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return [:]
        }

        var order: [String: Int] = [:]
        for (index, window) in rawWindows.enumerated() {
            guard intValue(window[kCGWindowLayer as String]) == 0,
                  let pid = intValue(window[kCGWindowOwnerPID as String]) else {
                continue
            }

            let title = window[kCGWindowName as String] as? String ?? ""
            let frame = cgFrame(window[kCGWindowBounds as String])
            let key = key(pid: pid_t(pid), title: title, frame: frame)
            if order[key] == nil {
                order[key] = index
            }
        }
        return order
    }

    static func key(pid: pid_t, title: String, frame: CGRect?) -> String {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let frame else {
            return "\(pid)|\(normalizedTitle)|frame:unknown"
        }

        return "\(pid)|\(normalizedTitle)|\(Int(frame.origin.x.rounded())),\(Int(frame.origin.y.rounded())),\(Int(frame.width.rounded())),\(Int(frame.height.rounded()))"
    }

    private static func cgFrame(_ value: Any?) -> CGRect? {
        guard let dictionary = value as? NSDictionary else {
            return nil
        }
        return CGRect(dictionaryRepresentation: dictionary as CFDictionary)
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int {
            return int
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        return nil
    }
}

private func copyAttribute(_ element: AXUIElement, _ attribute: CFString) -> CFTypeRef? {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, attribute, &value)
    guard error == .success else {
        return nil
    }
    return value
}

private func axString(_ element: AXUIElement, _ attribute: CFString) -> String? {
    copyAttribute(element, attribute) as? String
}

private func axBool(_ element: AXUIElement, _ attribute: CFString) -> Bool? {
    copyAttribute(element, attribute) as? Bool
}

private func axFrame(_ element: AXUIElement) -> CGRect? {
    guard let position = axPoint(element, kAXPositionAttribute as CFString),
          let size = axSize(element, kAXSizeAttribute as CFString) else {
        return nil
    }

    return CGRect(origin: position, size: size)
}

private func axPoint(_ element: AXUIElement, _ attribute: CFString) -> CGPoint? {
    guard let rawValue = copyAttribute(element, attribute),
          CFGetTypeID(rawValue) == AXValueGetTypeID() else {
        return nil
    }

    let value = unsafeBitCast(rawValue, to: AXValue.self)
    guard AXValueGetType(value) == .cgPoint else {
        return nil
    }

    var point = CGPoint.zero
    guard AXValueGetValue(value, .cgPoint, &point) else {
        return nil
    }
    return point
}

private func axSize(_ element: AXUIElement, _ attribute: CFString) -> CGSize? {
    guard let rawValue = copyAttribute(element, attribute),
          CFGetTypeID(rawValue) == AXValueGetTypeID() else {
        return nil
    }

    let value = unsafeBitCast(rawValue, to: AXValue.self)
    guard AXValueGetType(value) == .cgSize else {
        return nil
    }

    var size = CGSize.zero
    guard AXValueGetValue(value, .cgSize, &size) else {
        return nil
    }
    return size
}

private func normalizedIdentityPart(_ value: String) -> String {
    value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .split(separator: " ")
        .joined(separator: " ")
}

private func isExcludedWindowTitle(
    _ title: String,
    excludedTitlePatterns: [String]
) -> Bool {
    let normalizedTitle = normalizedIdentityPart(title)
    guard !normalizedTitle.isEmpty else {
        return false
    }

    return excludedTitlePatterns.contains { pattern in
        !pattern.isEmpty && normalizedTitle.contains(pattern)
    }
}

func shouldExcludeUntitledAuxiliaryWindow(
    appName: String,
    bundleIdentifier: String?,
    title: String
) -> Bool {
    guard title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return false
    }

    if bundleIdentifier?.lowercased() == "com.electron.lark" ||
        isFeishuMeetingApp(appName: appName, bundleIdentifier: bundleIdentifier) {
        return true
    }

    let normalizedAppName = normalizedIdentityPart(appName)
    return normalizedAppName == "飞书" ||
        normalizedAppName == "飞书会议" ||
        normalizedAppName == "feishu" ||
        normalizedAppName == "feishu meeting" ||
        normalizedAppName == "lark" ||
        normalizedAppName == "lark meeting"
}

private func deduplicateFeishuMeetingWindows(_ items: [WindowItem]) -> [WindowItem] {
    var primaryWindowByPID: [pid_t: WindowItem] = [:]

    for item in items where isFeishuMeetingApp(
        appName: item.appName,
        bundleIdentifier: item.bundleIdentifier
    ) {
        let pid = item.app.processIdentifier
        guard let current = primaryWindowByPID[pid] else {
            primaryWindowByPID[pid] = item
            continue
        }

        if isPreferredFeishuMeetingWindow(item, over: current) {
            primaryWindowByPID[pid] = item
        }
    }

    return items.filter { item in
        guard isFeishuMeetingApp(
            appName: item.appName,
            bundleIdentifier: item.bundleIdentifier
        ) else {
            return true
        }

        return primaryWindowByPID[item.app.processIdentifier] === item
    }
}

private func isPreferredFeishuMeetingWindow(
    _ candidate: WindowItem,
    over current: WindowItem
) -> Bool {
    if candidate.hasMeaningfulTitle != current.hasMeaningfulTitle {
        return candidate.hasMeaningfulTitle
    }

    let candidateArea = candidate.frame.map { $0.width * $0.height } ?? 0
    let currentArea = current.frame.map { $0.width * $0.height } ?? 0
    if candidateArea != currentArea {
        return candidateArea > currentArea
    }

    return candidate.order < current.order
}

private func isFeishuMeetingApp(
    appName: String,
    bundleIdentifier: String?
) -> Bool {
    if bundleIdentifier?.lowercased() == "com.electron.lark.iron" {
        return true
    }

    let normalizedAppName = normalizedIdentityPart(appName)
    return normalizedAppName == "飞书会议" ||
        normalizedAppName == "feishu meeting" ||
        normalizedAppName == "lark meeting"
}
