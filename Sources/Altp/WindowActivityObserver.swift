import AppKit
import ApplicationServices

final class WindowActivityObserver {
    private let catalog: WindowCatalog
    private var activationObserver: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?
    private var activeAXObserver: AXObserver?
    private var activeAXApplication: AXUIElement?
    private var observedPID: pid_t?
    private var pendingActivationObservation: DispatchWorkItem?
    private var pendingFocusObservations: [UUID: DispatchWorkItem] = [:]

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

        let workspaceNotificationCenter = NSWorkspace.shared.notificationCenter
        activationObserver = workspaceNotificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication else {
                return
            }
            self.observeActivatedApplication(application)
        }

        terminationObserver = workspaceNotificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication,
                  application.processIdentifier == self.observedPID else {
                return
            }
            self.stopFocusedWindowObservation()
        }

        if let frontmostApplication = NSWorkspace.shared.frontmostApplication {
            observeActivatedApplication(frontmostApplication)
        }
    }

    func stop() {
        pendingActivationObservation?.cancel()
        pendingActivationObservation = nil

        for workItem in pendingFocusObservations.values {
            workItem.cancel()
        }
        pendingFocusObservations.removeAll()
        stopFocusedWindowObservation()

        let workspaceNotificationCenter = NSWorkspace.shared.notificationCenter
        if let activationObserver {
            workspaceNotificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        if let terminationObserver {
            workspaceNotificationCenter.removeObserver(terminationObserver)
            self.terminationObserver = nil
        }
    }

    private func observeActivatedApplication(_ application: NSRunningApplication) {
        pendingActivationObservation?.cancel()
        pendingActivationObservation = nil
        stopFocusedWindowObservation()

        let processIdentifier = application.processIdentifier
        guard processIdentifier != ProcessInfo.processInfo.processIdentifier,
              !application.isTerminated else {
            return
        }

        observedPID = processIdentifier
        installFocusedWindowObservation(for: application)

        let capturedAt = Date().timeIntervalSince1970
        if let snapshot = catalog.captureStrictFocusSnapshot(
            expectedPID: processIdentifier,
            capturedAt: capturedAt
        ) {
            scheduleObservation(of: snapshot, after: 0)
        }
        scheduleSettledActivationObservation(expectedPID: processIdentifier)
    }

    private func installFocusedWindowObservation(for application: NSRunningApplication) {
        let processIdentifier = application.processIdentifier
        var observer: AXObserver?
        guard AXObserverCreate(
            processIdentifier,
            Self.focusedWindowChangedCallback,
            &observer
        ) == .success, let observer else {
            return
        }

        let axApplication = AXUIElementCreateApplication(processIdentifier)
        let addResult = AXObserverAddNotification(
            observer,
            axApplication,
            kAXFocusedWindowChangedNotification as CFString,
            Unmanaged.passUnretained(self).toOpaque()
        )
        guard addResult == .success || addResult == .notificationAlreadyRegistered else {
            return
        }

        activeAXObserver = observer
        activeAXApplication = axApplication
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .commonModes
        )
    }

    private func stopFocusedWindowObservation() {
        if let observer = activeAXObserver,
           let application = activeAXApplication {
            AXObserverRemoveNotification(
                observer,
                application,
                kAXFocusedWindowChangedNotification as CFString
            )
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .commonModes
            )
        }

        activeAXObserver = nil
        activeAXApplication = nil
        observedPID = nil
    }

    private func handleFocusedWindowChanged(expectedPID: pid_t) {
        guard observedPID == expectedPID,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == expectedPID else {
            return
        }

        let capturedAt = Date().timeIntervalSince1970
        guard let snapshot = catalog.captureStrictFocusSnapshot(
            expectedPID: expectedPID,
            capturedAt: capturedAt
        ) else {
            scheduleSettledActivationObservation(expectedPID: expectedPID)
            return
        }
        scheduleObservation(of: snapshot, after: 0)
    }

    private func scheduleSettledActivationObservation(expectedPID: pid_t) {
        pendingActivationObservation?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.activationObserver != nil,
                  self.observedPID == expectedPID,
                  AccessibilityPermission.isTrusted,
                  let snapshot = self.catalog.captureStrictFocusSnapshot(
                    expectedPID: expectedPID
                  ) else {
                return
            }
            self.recordObservation(of: snapshot)
        }

        pendingActivationObservation = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
    }

    private func scheduleObservation(
        of snapshot: VerifiedWindowFocusSnapshot,
        after delay: TimeInterval
    ) {
        let observationID = UUID()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }
            self.pendingFocusObservations.removeValue(forKey: observationID)
            guard self.activationObserver != nil,
                  AccessibilityPermission.isTrusted else {
                return
            }
            self.recordObservation(of: snapshot)
        }

        pendingFocusObservations[observationID] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func recordObservation(of snapshot: VerifiedWindowFocusSnapshot) {
        let windows = catalog.allWindows()
        guard let currentWindow = catalog.strictlyFocusedWindow(
            in: windows,
            snapshot: snapshot
        ) else {
            return
        }
        WindowSelectionMemory.shared.recordObservation(
            currentWindow,
            observedAt: snapshot.capturedAt
        )
    }

    private static let focusedWindowChangedCallback: AXObserverCallback = {
        _, element, notification, context in
        guard notification as String == kAXFocusedWindowChangedNotification as String,
              let context else {
            return
        }

        var processIdentifier: pid_t = 0
        guard AXUIElementGetPid(element, &processIdentifier) == .success else {
            return
        }
        let callbackPID = processIdentifier
        let owner = Unmanaged<WindowActivityObserver>
            .fromOpaque(context)
            .takeUnretainedValue()
        DispatchQueue.main.async { [weak owner] in
            owner?.handleFocusedWindowChanged(expectedPID: callbackPID)
        }
    }
}
