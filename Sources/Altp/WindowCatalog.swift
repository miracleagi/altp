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
    let fallbackKind: WindowFallbackKind?

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
        catalogIndex: Int,
        fallbackKind: WindowFallbackKind? = nil
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
        self.fallbackKind = fallbackKind
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
        let windowServerSnapshot = WindowOrdering.snapshot()
        let visibleOrder = windowServerSnapshot.visibleOrder
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
            let windows = copyAttribute(axApp, kAXWindowsAttribute as CFString) as? [AXUIElement] ?? []
            var hasDiscoverableAXWindow = false

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

                if WindowCompatibilityRules.shouldExcludeWindow(
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

                hasDiscoverableAXWindow = true

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

            let fallbackCandidate = WindowFallbackPolicy.preferredCandidate(
                from: windowServerSnapshot.fallbackCandidatesByPID[app.processIdentifier] ?? []
            )
            if WindowFallbackPolicy.shouldCreateApplicationFallback(
                hasDiscoverableAXWindow: hasDiscoverableAXWindow,
                isHidden: app.isHidden,
                isTerminated: app.isTerminated,
                candidate: fallbackCandidate
            ), WindowCompatibilityRules.allowsApplicationFallback(
                appName: app.localizedName ?? app.bundleIdentifier ?? "Unknown App",
                bundleIdentifier: app.bundleIdentifier
            ), let fallback = fallbackCandidate {
                let appName = app.localizedName ?? app.bundleIdentifier ?? "Unknown App"
                guard !isExcludedWindowTitle(
                    appName,
                    excludedTitlePatterns: excludedTitlePatterns
                ) else {
                    continue
                }

                let catalogIndex = nextCatalogIndex
                nextCatalogIndex += 1
                results.append(WindowItem(
                    app: app,
                    axWindow: axApp,
                    title: appName,
                    appName: appName,
                    bundleIdentifier: app.bundleIdentifier,
                    isMinimized: false,
                    isHidden: false,
                    role: "AXApplication",
                    subrole: "AXApplicationFallback",
                    document: "",
                    identifier: "window-server-fallback",
                    frame: fallback.frame,
                    order: fallback.order,
                    catalogIndex: catalogIndex,
                    fallbackKind: WindowFallbackPolicy.kind(for: fallback)
                ))
            }
        }

        return deduplicateWindowsUsingCompatibilityRules(results).sorted { lhs, rhs in
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

    func activate(
        _ item: WindowItem,
        completion: @escaping (AXError) -> Void
    ) {
        if item.isMinimized {
            AXUIElementSetAttributeValue(
                item.axWindow,
                kAXMinimizedAttribute as CFString,
                kCFBooleanFalse
            )
        }

        item.app.unhide()
        if let fallbackKind = item.fallbackKind {
            item.app.activate(options: activationOptions(for: fallbackKind))
            retryFallbackActivation(
                item,
                attemptIndex: 0,
                completion: completion
            )
            return
        }

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

        completion(AXUIElementPerformAction(item.axWindow, kAXRaiseAction as CFString))
    }

    private func retryFallbackActivation(
        _ item: WindowItem,
        attemptIndex: Int,
        completion: @escaping (AXError) -> Void
    ) {
        let retryDelays: [TimeInterval] = [0.08, 0.16, 0.28, 0.48]
        guard attemptIndex < retryDelays.count else {
            completion(.cannotComplete)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + retryDelays[attemptIndex]) { [weak self] in
            guard let self, !item.app.isTerminated else {
                completion(.cannotComplete)
                return
            }

            if let window = self.preferredAXWindow(for: item.app) {
                if let fallbackKind = item.fallbackKind {
                    item.app.activate(options: self.activationOptions(for: fallbackKind))
                }
                let mainResult = AXUIElementSetAttributeValue(
                    window,
                    kAXMainAttribute as CFString,
                    kCFBooleanTrue
                )
                let focusResult = AXUIElementSetAttributeValue(
                    window,
                    kAXFocusedAttribute as CFString,
                    kCFBooleanTrue
                )
                let raiseResult = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                if raiseResult == .success || mainResult == .success || focusResult == .success {
                    completion(.success)
                    return
                }
            }

            if attemptIndex == 0 {
                self.requestApplicationReopen(item.app)
            }
            self.retryFallbackActivation(
                item,
                attemptIndex: attemptIndex + 1,
                completion: completion
            )
        }
    }

    private func activationOptions(
        for fallbackKind: WindowFallbackKind
    ) -> NSApplication.ActivationOptions {
        switch fallbackKind {
        case .onScreenWindowServer:
            return [.activateIgnoringOtherApps]
        case .crossSpaceWindowServer:
            return [.activateAllWindows, .activateIgnoringOtherApps]
        }
    }

    private func preferredAXWindow(for app: NSRunningApplication) -> AXUIElement? {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        guard let windows = copyAttribute(axApp, kAXWindowsAttribute as CFString) as? [AXUIElement] else {
            return nil
        }

        let appName = app.localizedName ?? app.bundleIdentifier ?? "Unknown App"
        var bestWindow: AXUIElement?
        var bestPriority = Int.min
        var bestArea: CGFloat = 0

        for window in windows {
            let role = axString(window, kAXRoleAttribute as CFString) ?? ""
            guard role == kAXWindowRole as String || role == "AXWindow" else {
                continue
            }

            let title = axString(window, kAXTitleAttribute as CFString) ?? ""
            let subrole = axString(window, kAXSubroleAttribute as CFString) ?? ""
            if WindowCompatibilityRules.shouldExcludeWindow(
                appName: appName,
                bundleIdentifier: app.bundleIdentifier,
                title: title
            ) {
                continue
            }

            let priority = WindowFallbackPolicy.activationPriority(
                title: title,
                appName: appName,
                subrole: subrole,
                isMain: axBool(window, kAXMainAttribute as CFString) ?? false,
                isFocused: axBool(window, kAXFocusedAttribute as CFString) ?? false
            )

            let area = axFrame(window).map { $0.width * $0.height } ?? 0
            if priority > bestPriority || (priority == bestPriority && area > bestArea) {
                bestWindow = window
                bestPriority = priority
                bestArea = area
            }
        }

        return bestWindow
    }

    private func requestApplicationReopen(_ app: NSRunningApplication) {
        guard let bundleURL = app.bundleURL else {
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false
        NSWorkspace.shared.openApplication(
            at: bundleURL,
            configuration: configuration
        ) { _, error in
            if let error {
                NSLog("Altp window reopen fallback failed: \(error.localizedDescription)")
            }
        }
    }
}

private struct WindowOrderingSnapshot {
    let visibleOrder: [String: Int]
    let fallbackCandidatesByPID: [pid_t: [WindowServerFallbackCandidate]]
}

private enum WindowOrdering {
    static func snapshot() -> WindowOrderingSnapshot {
        let onScreenOptions: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let onScreenWindows = CGWindowListCopyWindowInfo(onScreenOptions, kCGNullWindowID)
            as? [[String: Any]] ?? []

        var order: [String: Int] = [:]
        var onScreenWindowNumbers: Set<Int> = []
        for (index, window) in onScreenWindows.enumerated() {
            guard intValue(window[kCGWindowLayer as String]) == 0,
                  let pid = intValue(window[kCGWindowOwnerPID as String]) else {
                continue
            }

            if let windowNumber = intValue(window[kCGWindowNumber as String]) {
                onScreenWindowNumbers.insert(windowNumber)
            }

            let title = window[kCGWindowName as String] as? String ?? ""
            let frame = cgFrame(window[kCGWindowBounds as String])
            let key = key(pid: pid_t(pid), title: title, frame: frame)
            if order[key] == nil {
                order[key] = index
            }
        }

        let allOptions: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        let allWindows = CGWindowListCopyWindowInfo(allOptions, kCGNullWindowID)
            as? [[String: Any]] ?? []
        var fallbackCandidatesByPID: [pid_t: [WindowServerFallbackCandidate]] = [:]
        for (index, window) in allWindows.enumerated() {
            guard let pid = intValue(window[kCGWindowOwnerPID as String]),
                  let windowNumber = intValue(window[kCGWindowNumber as String]),
                  let layer = intValue(window[kCGWindowLayer as String]),
                  let frame = cgFrame(window[kCGWindowBounds as String]) else {
                continue
            }

            fallbackCandidatesByPID[pid_t(pid), default: []].append(
                WindowServerFallbackCandidate(
                    frame: frame,
                    layer: layer,
                    alpha: doubleValue(window[kCGWindowAlpha as String]) ?? 1,
                    order: index,
                    isOnScreen: onScreenWindowNumbers.contains(windowNumber)
                )
            )
        }

        return WindowOrderingSnapshot(
            visibleOrder: order,
            fallbackCandidatesByPID: fallbackCandidatesByPID
        )
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

    private static func doubleValue(_ value: Any?) -> Double? {
        if let double = value as? Double {
            return double
        }
        if let number = value as? NSNumber {
            return number.doubleValue
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

private func deduplicateWindowsUsingCompatibilityRules(
    _ items: [WindowItem]
) -> [WindowItem] {
    var primaryWindowByKey: [String: WindowItem] = [:]

    for item in items {
        guard let key = WindowCompatibilityRules.deduplicationKey(
            appName: item.appName,
            bundleIdentifier: item.bundleIdentifier,
            processIdentifier: item.app.processIdentifier
        ) else {
            continue
        }

        guard let current = primaryWindowByKey[key] else {
            primaryWindowByKey[key] = item
            continue
        }

        if WindowCompatibilityRules.prefers(
            compatibilityPreference(for: item),
            over: compatibilityPreference(for: current)
        ) {
            primaryWindowByKey[key] = item
        }
    }

    return items.filter { item in
        guard let key = WindowCompatibilityRules.deduplicationKey(
            appName: item.appName,
            bundleIdentifier: item.bundleIdentifier,
            processIdentifier: item.app.processIdentifier
        ) else {
            return true
        }
        return primaryWindowByKey[key] === item
    }
}

private func compatibilityPreference(for item: WindowItem) -> WindowCompatibilityPreference {
    WindowCompatibilityPreference(
        hasMeaningfulTitle: item.hasMeaningfulTitle,
        area: item.frame.map { Double($0.width * $0.height) } ?? 0,
        order: item.order
    )
}
