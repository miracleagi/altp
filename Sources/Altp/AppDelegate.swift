import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let launchAtLoginArgument = "--launch-at-login"
    private let settingsArgument = "--settings"
    private let windowCatalog = WindowCatalog()
    private lazy var searchPanelController = SearchPanelController(catalog: windowCatalog)
    private var quickSwitchPanelController: QuickSwitchPanelController?
    private var searchHotKeyManager: HotKeyManager?
    private var quickSwitchHotKeyManager: HotKeyManager?
    private var preferencesController: PreferencesWindowController?
    private var statusItem: NSStatusItem?
    private var searchHotKeyStatusMessage = ""
    private var searchHotKeyStatusIsError = false
    private var quickSwitchHotKeyStatusMessage = ""
    private var quickSwitchHotKeyStatusIsError = false
    private var suppressSearchPanelOnReopen = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("Altp did finish launching")
        LaunchAtLoginManager.migrateLegacyLaunchAgentIfNeeded()
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupHotKeys()

        if ProcessInfo.processInfo.arguments.contains(settingsArgument) {
            showPreferences()
        } else if !ProcessInfo.processInfo.arguments.contains(launchAtLoginArgument) {
            searchPanelController.show()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if suppressSearchPanelOnReopen || preferencesController?.window?.isVisible == true {
            return true
        }

        showSearchPanelAfterCurrentEvent()
        return true
    }

    @objc private func showSearchPanel() {
        showSearchPanelAfterCurrentEvent()
    }

    @objc private func toggleSearchPanel() {
        quickSwitchPanelController?.hide()
        searchPanelController.toggle()
    }

    @objc private func quickSwitchWindow() {
        performQuickSwitch(activateOnModifierRelease: false)
    }

    private func performQuickSwitch(activateOnModifierRelease: Bool) {
        searchPanelController.hide()
        quickSwitchController().showOrAdvance(activateOnModifierRelease: activateOnModifierRelease)
    }

    @objc private func showPreferences() {
        suppressSearchPanelOnReopen = true
        searchPanelController.hide()
        quickSwitchPanelController?.hide()

        let controller = preferencesController ?? makePreferencesController()
        preferencesController = controller
        controller.updateSearchHotKeyStatus(searchHotKeyStatusMessage, isError: searchHotKeyStatusIsError)
        controller.updateQuickSwitchHotKeyStatus(quickSwitchHotKeyStatusMessage, isError: quickSwitchHotKeyStatusIsError)
        controller.refresh()
        controller.showWindow(nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.suppressSearchPanelOnReopen = false
        }
    }

    @objc private func requestAccessibilityPermission() {
        _ = AccessibilityPermission.requestIfNeeded()
        searchPanelController.reloadWindowList()
    }

    @objc private func openAccessibilitySettings() {
        AccessibilityPermission.openSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func setupHotKeys() {
        searchHotKeyManager = nil
        quickSwitchHotKeyManager = nil
        setupSearchHotKey()
        setupQuickSwitchHotKey()
        statusItem?.button?.toolTip = """
        Altp
        Search: \(AppSettings.searchShortcut.displayString)
        Quick Switch: \(AppSettings.quickSwitchShortcut.displayString)
        """
    }

    private func setupSearchHotKey() {
        let shortcut = AppSettings.searchShortcut

        do {
            searchHotKeyManager = try HotKeyManager(
                id: 1,
                keyCode: shortcut.keyCode,
                modifiers: shortcut.modifiers,
                action: { [weak self] in
                    DispatchQueue.main.async {
                        self?.toggleSearchPanel()
                    }
                }
            )
            setSearchHotKeyStatus("Registered \(shortcut.displayString)", isError: false)
            NSLog("Altp registered search hotkey \(shortcut.displayString)")
        } catch {
            setSearchHotKeyStatus("Could not register \(shortcut.displayString): \(error)", isError: true)
            NSLog("Altp search hotkey registration failed: \(error)")
        }
    }

    private func setupQuickSwitchHotKey() {
        let shortcut = AppSettings.quickSwitchShortcut

        do {
            quickSwitchHotKeyManager = try HotKeyManager(
                id: 2,
                keyCode: shortcut.keyCode,
                modifiers: shortcut.modifiers,
                action: { [weak self] in
                    DispatchQueue.main.async {
                        self?.performQuickSwitch(activateOnModifierRelease: true)
                    }
                }
            )
            setQuickSwitchHotKeyStatus("Registered \(shortcut.displayString)", isError: false)
            NSLog("Altp registered quick switch hotkey \(shortcut.displayString)")
        } catch {
            setQuickSwitchHotKeyStatus("Could not register \(shortcut.displayString): \(error)", isError: true)
            NSLog("Altp quick switch hotkey registration failed: \(error)")
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.length = 48
        item.button?.title = "Altp"
        item.button?.toolTip = "Altp Window Search"
        item.isVisible = true

        let menu = NSMenu()
        menu.addItem(menuItem(
            title: "Show Window Search",
            action: #selector(showSearchPanel),
            keyEquivalent: ""
        ))
        menu.addItem(menuItem(
            title: "Quick Switch to Previous Window",
            action: #selector(quickSwitchWindow),
            keyEquivalent: ""
        ))
        menu.addItem(menuItem(
            title: "Settings...",
            action: #selector(showPreferences),
            keyEquivalent: ","
        ))
        menu.addItem(.separator())
        menu.addItem(menuItem(
            title: "Request Accessibility Permission",
            action: #selector(requestAccessibilityPermission),
            keyEquivalent: ""
        ))
        menu.addItem(menuItem(
            title: "Open Accessibility Settings",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        ))
        menu.addItem(.separator())
        menu.addItem(menuItem(
            title: "Quit Altp",
            action: #selector(quit),
            keyEquivalent: "q"
        ))

        item.menu = menu
        statusItem = item
    }

    private func menuItem(title: String, action: Selector, keyEquivalent: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    private func makePreferencesController() -> PreferencesWindowController {
        let controller = PreferencesWindowController()
        controller.onShortcutChanged = { [weak self] in
            self?.setupHotKeys()
        }
        return controller
    }

    private func setSearchHotKeyStatus(_ message: String, isError: Bool) {
        searchHotKeyStatusMessage = message
        searchHotKeyStatusIsError = isError
        preferencesController?.updateSearchHotKeyStatus(message, isError: isError)
    }

    private func setQuickSwitchHotKeyStatus(_ message: String, isError: Bool) {
        quickSwitchHotKeyStatusMessage = message
        quickSwitchHotKeyStatusIsError = isError
        preferencesController?.updateQuickSwitchHotKeyStatus(message, isError: isError)
    }

    private func showSearchPanelAfterCurrentEvent() {
        DispatchQueue.main.async { [weak self] in
            self?.quickSwitchPanelController?.hide()
            self?.searchPanelController.show()
        }
    }

    private func quickSwitchController() -> QuickSwitchPanelController {
        if let quickSwitchPanelController {
            return quickSwitchPanelController
        }

        let controller = QuickSwitchPanelController(catalog: windowCatalog)
        quickSwitchPanelController = controller
        return controller
    }
}
