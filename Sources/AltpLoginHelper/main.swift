import AppKit
import Foundation

private let helperSuffix = ".login-helper"
private let helperBundleIdentifier = Bundle.main.bundleIdentifier ?? "com.miracleagi.altp.login-helper"
private let mainBundleIdentifier: String = {
    guard helperBundleIdentifier.hasSuffix(helperSuffix) else {
        return "com.miracleagi.altp"
    }

    return String(helperBundleIdentifier.dropLast(helperSuffix.count))
}()
private let launchAtLoginArgument = "--launch-at-login"

private func mainAppURL() -> URL {
    Bundle.main.bundleURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

if NSRunningApplication.runningApplications(withBundleIdentifier: mainBundleIdentifier).isEmpty {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false
    configuration.arguments = [launchAtLoginArgument]

    var didFinish = false
    NSWorkspace.shared.openApplication(at: mainAppURL(), configuration: configuration) { _, error in
        if let error {
            NSLog("Altp login helper could not open main app: \(error)")
        }
        didFinish = true
    }

    let deadline = Date().addingTimeInterval(10)
    while !didFinish && Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
    }
}
