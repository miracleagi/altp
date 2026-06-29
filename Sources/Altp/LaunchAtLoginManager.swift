import AppKit
import ServiceManagement

enum LaunchAtLoginManager {
    enum Status {
        case enabled
        case enabledViaLaunchAgent
        case notRegistered
        case requiresApproval
        case staleLaunchAgent
        case unavailable
    }

    private static let launchAgentLabel = "com.miracleagi.altp.login"

    private static var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(launchAgentLabel).plist")
    }

    private static var bundlePath: String {
        Bundle.main.bundlePath
    }

    private static var isRunningFromApplications: Bool {
        bundlePath.contains("/Applications/")
    }

    static var status: Status {
        switch SMAppService.mainApp.status {
        case .enabled:
            return .enabled
        case .notRegistered:
            return launchAgentStatusWhenMainAppIsUnavailable(defaultStatus: .notRegistered)
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return launchAgentStatusWhenMainAppIsUnavailable(defaultStatus: isRunningFromApplications ? .notRegistered : .unavailable)
        @unknown default:
            return launchAgentStatusWhenMainAppIsUnavailable(defaultStatus: .unavailable)
        }
    }

    static var isEnabled: Bool {
        switch status {
        case .enabled, .enabledViaLaunchAgent:
            return true
        case .notRegistered, .requiresApproval, .staleLaunchAgent, .unavailable:
            return false
        }
    }

    static var statusText: String {
        switch status {
        case .enabled:
            return "Enabled"
        case .enabledViaLaunchAgent:
            return "Enabled via LaunchAgent"
        case .notRegistered:
            return "Off"
        case .requiresApproval:
            return "Requires approval in Login Items"
        case .staleLaunchAgent:
            return "Login item points to another copy; turn it off and on to repair"
        case .unavailable:
            return "Move Altp.app to Applications and reopen it to enable Launch at Login"
        }
    }

    static var canUpdateRegistration: Bool {
        switch status {
        case .unavailable:
            return false
        case .enabled, .enabledViaLaunchAgent, .notRegistered, .requiresApproval, .staleLaunchAgent:
            return true
        }
    }

    static func setEnabled(_ enabled: Bool) throws {
        switch SMAppService.mainApp.status {
        case .notFound:
            try setLaunchAgentEnabled(enabled)
        default:
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
                try setLaunchAgentEnabled(false)
            }
        }
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    private static func launchAgentStatusWhenMainAppIsUnavailable(defaultStatus: Status) -> Status {
        guard FileManager.default.fileExists(atPath: launchAgentURL.path) else {
            return defaultStatus
        }

        if launchAgentBundlePath() == bundlePath {
            return .enabledViaLaunchAgent
        }

        return .staleLaunchAgent
    }

    private static func setLaunchAgentEnabled(_ enabled: Bool) throws {
        let fileManager = FileManager.default

        if !enabled {
            if fileManager.fileExists(atPath: launchAgentURL.path) {
                try fileManager.removeItem(at: launchAgentURL)
            }
            return
        }

        let launchAgentsURL = launchAgentURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: launchAgentsURL, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "Label": launchAgentLabel,
            "ProgramArguments": [
                "/usr/bin/open",
                "-g",
                "-j",
                bundlePath
            ],
            "RunAtLoad": true
        ]

        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: launchAgentURL, options: .atomic)
    }

    private static func launchAgentBundlePath() -> String? {
        guard let data = try? Data(contentsOf: launchAgentURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = plist as? [String: Any],
              let arguments = dictionary["ProgramArguments"] as? [String] else {
            return nil
        }

        return arguments.last
    }
}
