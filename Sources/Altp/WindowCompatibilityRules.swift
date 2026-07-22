import Foundation

struct WindowCompatibilityPreference {
    let hasMeaningfulTitle: Bool
    let area: Double
    let order: Int
}

enum WindowCompatibilityRules {
    // App-specific rules belong here only when the behavior is reproducible,
    // materially affects switching, can be identified without ambiguity, and
    // has a narrow regression surface. Unreliable third-party quirks must not
    // be encoded as compatibility rules.
    static func shouldExcludeWindow(
        appName: String,
        bundleIdentifier: String?,
        title: String
    ) -> Bool {
        let normalizedTitle = normalized(title)

        if isFeishuMainApp(appName: appName, bundleIdentifier: bundleIdentifier),
           normalizedTitle == "watermarkwidget" {
            return true
        }

        guard normalizedTitle.isEmpty else {
            return false
        }

        return isFeishuMainApp(appName: appName, bundleIdentifier: bundleIdentifier) ||
            isFeishuMeetingApp(appName: appName, bundleIdentifier: bundleIdentifier)
    }

    static func deduplicationKey(
        appName: String,
        bundleIdentifier: String?,
        processIdentifier: Int32
    ) -> String? {
        guard isFeishuMeetingApp(
            appName: appName,
            bundleIdentifier: bundleIdentifier
        ) else {
            return nil
        }
        return "feishu-meeting|pid:\(processIdentifier)"
    }

    static func allowsApplicationFallback(
        appName: String,
        bundleIdentifier: String?
    ) -> Bool {
        !isFeishuMeetingApp(
            appName: appName,
            bundleIdentifier: bundleIdentifier
        )
    }

    static func prefers(
        _ candidate: WindowCompatibilityPreference,
        over current: WindowCompatibilityPreference
    ) -> Bool {
        if candidate.hasMeaningfulTitle != current.hasMeaningfulTitle {
            return candidate.hasMeaningfulTitle
        }
        if candidate.area != current.area {
            return candidate.area > current.area
        }
        return candidate.order < current.order
    }

    private static func isFeishuMainApp(
        appName: String,
        bundleIdentifier: String?
    ) -> Bool {
        if let bundleIdentifier {
            return bundleIdentifier.lowercased() == "com.electron.lark"
        }

        let normalizedAppName = normalized(appName)
        return normalizedAppName == "飞书" ||
            normalizedAppName == "feishu" ||
            normalizedAppName == "lark"
    }

    private static func isFeishuMeetingApp(
        appName: String,
        bundleIdentifier: String?
    ) -> Bool {
        if let bundleIdentifier {
            return bundleIdentifier.lowercased() == "com.electron.lark.iron"
        }

        let normalizedAppName = normalized(appName)
        return normalizedAppName == "飞书会议" ||
            normalizedAppName == "feishu meeting" ||
            normalizedAppName == "lark meeting"
    }

    private static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(separator: " ")
            .joined(separator: " ")
    }
}
