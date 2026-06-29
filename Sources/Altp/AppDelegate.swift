import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let windowCatalog = WindowCatalog()
    private lazy var searchPanelController = SearchPanelController(catalog: windowCatalog)
    private var hotKeyManager: HotKeyManager?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("Altp did finish launching")
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupHotKey()
        _ = AccessibilityPermission.requestIfNeeded()
        searchPanelController.show()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSearchPanelAfterCurrentEvent()
        return true
    }

    @objc private func showSearchPanel() {
        showSearchPanelAfterCurrentEvent()
    }

    @objc private func toggleSearchPanel() {
        searchPanelController.toggle()
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
        do {
            hotKeyManager = try HotKeyManager(
                keyCode: UInt32(kVK_Space),
                modifiers: UInt32(optionKey),
                action: { [weak self] in
                    DispatchQueue.main.async {
                        self?.toggleSearchPanel()
                    }
                }
            )
            NSLog("Altp registered Option-Space hotkey")
        } catch {
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

    private func showSearchPanelAfterCurrentEvent() {
        DispatchQueue.main.async { [weak self] in
            self?.searchPanelController.show()
        }
    }
}
