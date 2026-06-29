import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let windowCatalog = WindowCatalog()
    private lazy var searchPanelController = SearchPanelController(catalog: windowCatalog)
    private var hotKeyManager: HotKeyManager?
    private var preferencesController: PreferencesWindowController?
    private var statusItem: NSStatusItem?
    private var hotKeyStatusMessage = ""
    private var hotKeyStatusIsError = false
    private var suppressSearchPanelOnReopen = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("Altp did finish launching")
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupHotKey()
        _ = AccessibilityPermission.requestIfNeeded()
        searchPanelController.show()
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
        searchPanelController.toggle()
    }

    @objc private func showPreferences() {
        suppressSearchPanelOnReopen = true
        searchPanelController.hide()

        let controller = preferencesController ?? makePreferencesController()
        preferencesController = controller
        controller.updateHotKeyStatus(hotKeyStatusMessage, isError: hotKeyStatusIsError)
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

    private func setupHotKey() {
        hotKeyManager = nil
        let shortcut = AppSettings.shortcut

        do {
            hotKeyManager = try HotKeyManager(
                keyCode: shortcut.keyCode,
                modifiers: shortcut.modifiers,
                action: { [weak self] in
                    DispatchQueue.main.async {
                        self?.toggleSearchPanel()
                    }
                }
            )
            setHotKeyStatus("Registered \(shortcut.displayString)", isError: false)
            statusItem?.button?.toolTip = "Altp Window Search - \(shortcut.displayString)"
            NSLog("Altp registered \(shortcut.displayString) hotkey")
        } catch {
            setHotKeyStatus("Could not register \(shortcut.displayString): \(error)", isError: true)
            NSLog("Altp hotkey registration failed: \(error)")
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
            title: "Preferences...",
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
            self?.setupHotKey()
        }
        return controller
    }

    private func setHotKeyStatus(_ message: String, isError: Bool) {
        hotKeyStatusMessage = message
        hotKeyStatusIsError = isError
        preferencesController?.updateHotKeyStatus(message, isError: isError)
    }

    private func showSearchPanelAfterCurrentEvent() {
        DispatchQueue.main.async { [weak self] in
            self?.searchPanelController.show()
        }
    }
}
