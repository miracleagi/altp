import AppKit
import ServiceManagement

enum LaunchAtLoginManager {
    enum Status {
        case enabled
        case notRegistered
        case requiresApproval
        case helperMissing
        case unavailable
    }

    private static let legacyLaunchAgentLabel = "com.miracleagi.altp.login"

    private static var loginHelperIdentifier: String {
        "\(Bundle.main.bundleIdentifier ?? "com.miracleagi.altp").login-helper"
    }

    private static var loginItemService: SMAppService {
        SMAppService.loginItem(identifier: loginHelperIdentifier)
    }

    private static var loginHelperAppName: String {
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Altp"
        return "\(appName) Login Helper.app"
    }

    private static var embeddedLoginHelperURL: URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LoginItems", isDirectory: true)
            .appendingPathComponent(loginHelperAppName, isDirectory: true)
    }

    private static var hasEmbeddedLoginHelper: Bool {
        guard FileManager.default.fileExists(atPath: embeddedLoginHelperURL.path) else {
            return false
        }

        return Bundle(url: embeddedLoginHelperURL)?.bundleIdentifier == loginHelperIdentifier
    }

    private static var legacyLaunchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(legacyLaunchAgentLabel).plist")
    }

    private static var bundlePath: String {
        Bundle.main.bundlePath
    }

    private static var isRunningFromApplications: Bool {
        bundlePath.contains("/Applications/")
    }

    static var status: Status {
        guard isRunningFromApplications else {
            return .unavailable
        }

        switch loginItemService.status {
        case .enabled:
            return .enabled
        case .notRegistered:
            return .notRegistered
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return hasEmbeddedLoginHelper ? .notRegistered : .helperMissing
        @unknown default:
            return .unavailable
        }
    }

    static var isEnabled: Bool {
        switch status {
        case .enabled:
            return true
        case .notRegistered, .requiresApproval, .helperMissing, .unavailable:
            return false
        }
    }

    static var statusText: String {
        switch status {
        case .enabled:
            return "Enabled"
        case .notRegistered:
            return "Off"
        case .requiresApproval:
            return "Requires approval in Login Items"
        case .helperMissing:
            return "Login helper is missing; rebuild or reinstall Altp.app"
        case .unavailable:
            return "Move Altp.app to Applications and reopen it to enable Launch at Login"
        }
    }

    static var canUpdateRegistration: Bool {
        switch status {
        case .unavailable:
            return false
        case .helperMissing:
            return false
        case .enabled, .notRegistered, .requiresApproval:
            return true
        }
    }

    static func setEnabled(_ enabled: Bool) throws {
        try removeLegacyLaunchAgentIfPresent()

        if enabled {
            guard hasEmbeddedLoginHelper else {
                throw NSError(
                    domain: "Altp.LaunchAtLogin",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Login helper is missing"]
                )
            }

            try loginItemService.register()
        } else {
            try loginItemService.unregister()
        }
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    static func migrateLegacyLaunchAgentIfNeeded() {
        guard isRunningFromApplications,
              legacyLaunchAgentBundlePath() == bundlePath else {
            return
        }

        switch loginItemService.status {
        case .enabled:
            try? removeLegacyLaunchAgentIfPresent()
        case .notRegistered:
            registerLoginItemForLegacyMigration()
        case .requiresApproval:
            break
        case .notFound where hasEmbeddedLoginHelper:
            registerLoginItemForLegacyMigration()
        case .notFound:
            NSLog("Altp login helper is missing; legacy login item was left unchanged")
        @unknown default:
            break
        }
    }

    private static func registerLoginItemForLegacyMigration() {
        do {
            try loginItemService.register()
            try? removeLegacyLaunchAgentIfPresent()
        } catch {
            NSLog("Altp could not migrate legacy login item: \(error)")
        }
    }

    private static func removeLegacyLaunchAgentIfPresent() throws {
        guard FileManager.default.fileExists(atPath: legacyLaunchAgentURL.path) else {
            return
        }

        try FileManager.default.removeItem(at: legacyLaunchAgentURL)
    }

    private static func legacyLaunchAgentBundlePath() -> String? {
        guard let data = try? Data(contentsOf: legacyLaunchAgentURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = plist as? [String: Any],
              let arguments = dictionary["ProgramArguments"] as? [String] else {
            return nil
        }

        return arguments.last
    }
}
