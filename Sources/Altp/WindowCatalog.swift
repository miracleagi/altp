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
    let frame: CGRect?
    let order: Int

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
        frame: CGRect?,
        order: Int
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
        self.frame = frame
        self.order = order
    }

    var displayTitle: String {
        title.isEmpty ? "Untitled Window" : title
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
        [
            title,
            appName,
            bundleIdentifier ?? "",
            subrole
        ]
        .joined(separator: " ")
        .lowercased()
    }

    var memoryKey: String {
        [
            normalizedIdentityPart(bundleIdentifier ?? appName),
            normalizedIdentityPart(title),
            normalizedIdentityPart(subrole)
        ]
        .joined(separator: "|")
    }

}

final class WindowCatalog {
    func allWindows() -> [WindowItem] {
        guard AccessibilityPermission.isTrusted else {
            return []
        }

        let visibleOrder = WindowOrdering.snapshot()
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications
            .filter { app in
                app.activationPolicy == .regular &&
                    app.processIdentifier != currentPID &&
                    !app.isTerminated
            }

        var results: [WindowItem] = []

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
                let frame = axFrame(window)

                if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   frame?.isEmpty != false {
                    continue
                }

                let appName = app.localizedName ?? app.bundleIdentifier ?? "Unknown App"
                let key = WindowOrdering.key(pid: app.processIdentifier, title: title)
                let order = visibleOrder[key] ?? (10_000 + appIndex * 100 + windowIndex)

                results.append(WindowItem(
                    app: app,
                    axWindow: window,
                    title: title,
                    appName: appName,
                    bundleIdentifier: app.bundleIdentifier,
                    isMinimized: axBool(window, kAXMinimizedAttribute as CFString) ?? false,
                    isHidden: app.isHidden,
                    role: role,
                    subrole: subrole,
                    frame: frame,
                    order: order
                ))
            }
        }

        return results.sorted { lhs, rhs in
            if lhs.order != rhs.order {
                return lhs.order < rhs.order
            }
            if lhs.appName.localizedCaseInsensitiveCompare(rhs.appName) != .orderedSame {
                return lhs.appName.localizedCaseInsensitiveCompare(rhs.appName) == .orderedAscending
            }
            return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
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
            let key = key(pid: pid_t(pid), title: title)
            if order[key] == nil {
                order[key] = index
            }
        }
        return order
    }

    static func key(pid: pid_t, title: String) -> String {
        "\(pid)|\(title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
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
