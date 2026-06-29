import AppKit
import ServiceManagement

enum LaunchAtLoginManager {
    static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    static var isEnabled: Bool {
        status == .enabled
    }

    static var statusText: String {
        switch status {
        case .enabled:
            return "Enabled"
        case .notRegistered:
            return "Off"
        case .requiresApproval:
            return "Requires approval in Login Items"
        case .notFound:
            return "App bundle not found"
        @unknown default:
            return "Unknown"
        }
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
