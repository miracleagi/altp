import AppKit
import ApplicationServices

enum AccessibilityPermission {
    private(set) static var hasRequestedThisLaunch = false

    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    static func requestIfNeeded() -> Bool {
        if isTrusted {
            return true
        }

        guard !hasRequestedThisLaunch else {
            openSettings()
            return false
        }

        hasRequestedThisLaunch = true
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
