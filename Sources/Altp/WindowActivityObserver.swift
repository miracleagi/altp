import AppKit

final class WindowActivityObserver {
    private let catalog: WindowCatalog
    private var activationObserver: NSObjectProtocol?
    private var pendingObservation: DispatchWorkItem?

    init(catalog: WindowCatalog) {
        self.catalog = catalog
    }

    deinit {
        stop()
    }

    func start() {
        guard activationObserver == nil else {
            return
        }

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication,
                  application.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
                return
            }
            self?.scheduleObservation(expectedPID: application.processIdentifier)
        }

        if let frontmostApplication = NSWorkspace.shared.frontmostApplication,
           frontmostApplication.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            scheduleObservation(expectedPID: frontmostApplication.processIdentifier)
        }
    }

    func stop() {
        pendingObservation?.cancel()
        pendingObservation = nil

        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
    }

    private func scheduleObservation(expectedPID: pid_t) {
        pendingObservation?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  AccessibilityPermission.isTrusted,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == expectedPID else {
                return
            }

            let windows = self.catalog.allWindows()
            guard let currentWindow = WindowRanking.currentWindow(in: windows),
                  currentWindow.app.processIdentifier == expectedPID else {
                return
            }
            WindowSelectionMemory.shared.recordObservation(currentWindow)
        }

        pendingObservation = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
    }
}
