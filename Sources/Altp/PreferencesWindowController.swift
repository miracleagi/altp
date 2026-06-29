import AppKit

final class PreferencesWindowController: NSWindowController {
    var onShortcutChanged: (() -> Void)?

    private let shortcutButton = ShortcutRecorderButton(shortcut: AppSettings.shortcut)
    private let hotKeyStatusLabel = NSTextField(labelWithString: "")
    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch at Login", target: nil, action: nil)
    private let launchStatusLabel = NSTextField(labelWithString: "")
    private let accessibilityStatusLabel = NSTextField(labelWithString: "")
    private let requestAccessibilityButton = NSButton(title: "Request Permission", target: nil, action: nil)

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 332),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Altp Preferences"
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        window.delegate = self
        buildInterface()
        refresh()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func showWindow(_ sender: Any?) {
        refresh()
        super.showWindow(sender)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(sender)
    }

    func updateHotKeyStatus(_ message: String, isError: Bool) {
        hotKeyStatusLabel.stringValue = message
        hotKeyStatusLabel.textColor = isError ? .systemRed : .secondaryLabelColor
    }

    func refresh() {
        shortcutButton.shortcut = AppSettings.shortcut
        refreshLaunchAtLoginStatus()
        refreshAccessibilityStatus()
    }

    private func buildInterface() {
        guard let contentView = window?.contentView else {
            return
        }

        let rootStack = NSStackView()
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 16
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 22),
            rootStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -22),
            rootStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22),
            rootStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -22)
        ])

        rootStack.addArrangedSubview(sectionTitle("Keyboard"))
        rootStack.addArrangedSubview(shortcutRow())
        rootStack.addArrangedSubview(statusRow(hotKeyStatusLabel))
        rootStack.addArrangedSubview(separator())

        rootStack.addArrangedSubview(sectionTitle("Startup"))
        rootStack.addArrangedSubview(launchAtLoginRow())
        rootStack.addArrangedSubview(statusRow(launchStatusLabel))
        rootStack.addArrangedSubview(separator())

        rootStack.addArrangedSubview(sectionTitle("Permissions"))
        rootStack.addArrangedSubview(accessibilityRow())
        rootStack.addArrangedSubview(statusRow(accessibilityStatusLabel))
    }

    private func sectionTitle(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .labelColor
        return label
    }

    private func shortcutRow() -> NSStackView {
        let resetButton = NSButton(title: "Reset", target: self, action: #selector(resetShortcut))
        resetButton.bezelStyle = .rounded
        resetButton.controlSize = .regular

        shortcutButton.onShortcutChange = { [weak self] shortcut in
            AppSettings.shortcut = shortcut
            self?.updateHotKeyStatus("Registering \(shortcut.displayString)...", isError: false)
            self?.onShortcutChanged?()
        }

        return row(label: "Shortcut", views: [shortcutButton, resetButton])
    }

    private func launchAtLoginRow() -> NSStackView {
        launchAtLoginCheckbox.target = self
        launchAtLoginCheckbox.action = #selector(toggleLaunchAtLogin)

        let settingsButton = NSButton(title: "Open Login Items", target: self, action: #selector(openLoginItemsSettings))
        settingsButton.bezelStyle = .rounded
        settingsButton.controlSize = .regular

        return row(label: "Startup", views: [launchAtLoginCheckbox, settingsButton])
    }

    private func accessibilityRow() -> NSStackView {
        requestAccessibilityButton.target = self
        requestAccessibilityButton.action = #selector(requestAccessibilityPermission)
        requestAccessibilityButton.bezelStyle = .rounded
        requestAccessibilityButton.controlSize = .regular

        let settingsButton = NSButton(title: "Open Settings", target: self, action: #selector(openAccessibilitySettings))
        settingsButton.bezelStyle = .rounded
        settingsButton.controlSize = .regular

        let refreshButton = NSButton(title: "Refresh", target: self, action: #selector(refreshStatuses))
        refreshButton.bezelStyle = .rounded
        refreshButton.controlSize = .regular

        return row(label: "Accessibility", views: [requestAccessibilityButton, settingsButton, refreshButton])
    }

    private func row(label title: String, views: [NSView]) -> NSStackView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.alignment = .right
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.widthAnchor.constraint(equalToConstant: 110).isActive = true

        let rowStack = NSStackView(views: [titleLabel] + views)
        rowStack.orientation = .horizontal
        rowStack.alignment = .centerY
        rowStack.spacing = 10
        rowStack.translatesAutoresizingMaskIntoConstraints = false

        return rowStack
    }

    private func statusRow(_ label: NSTextField) -> NSStackView {
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 2

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.widthAnchor.constraint(equalToConstant: 110).isActive = true

        let rowStack = NSStackView(views: [spacer, label])
        rowStack.orientation = .horizontal
        rowStack.alignment = .centerY
        rowStack.spacing = 10
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        rowStack.widthAnchor.constraint(greaterThanOrEqualToConstant: 480).isActive = true

        return rowStack
    }

    private func separator() -> NSBox {
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.widthAnchor.constraint(equalToConstant: 516).isActive = true
        return separator
    }

    private func refreshLaunchAtLoginStatus() {
        let status = LaunchAtLoginManager.status
        launchAtLoginCheckbox.allowsMixedState = true
        launchAtLoginCheckbox.isEnabled = LaunchAtLoginManager.canUpdateRegistration

        switch status {
        case .enabled:
            launchAtLoginCheckbox.state = .on
            launchStatusLabel.textColor = .secondaryLabelColor
        case .enabledViaLaunchAgent:
            launchAtLoginCheckbox.state = .on
            launchStatusLabel.textColor = .secondaryLabelColor
        case .notRegistered:
            launchAtLoginCheckbox.state = .off
            launchStatusLabel.textColor = .secondaryLabelColor
        case .requiresApproval:
            launchAtLoginCheckbox.state = .mixed
            launchStatusLabel.textColor = .systemOrange
        case .staleLaunchAgent:
            launchAtLoginCheckbox.state = .mixed
            launchStatusLabel.textColor = .systemOrange
        case .unavailable:
            launchAtLoginCheckbox.state = .off
            launchStatusLabel.textColor = .systemRed
        }

        launchStatusLabel.stringValue = LaunchAtLoginManager.statusText
    }

    private func refreshAccessibilityStatus() {
        if AccessibilityPermission.isTrusted {
            accessibilityStatusLabel.stringValue = "Granted"
            accessibilityStatusLabel.textColor = .systemGreen
            requestAccessibilityButton.isEnabled = false
        } else {
            accessibilityStatusLabel.stringValue = "Required to list and focus windows"
            accessibilityStatusLabel.textColor = .systemOrange
            requestAccessibilityButton.isEnabled = true
        }
    }

    @objc private func resetShortcut() {
        AppSettings.resetShortcut()
        shortcutButton.shortcut = AppSettings.shortcut
        updateHotKeyStatus("Registering \(AppSettings.shortcut.displayString)...", isError: false)
        onShortcutChanged?()
    }

    @objc private func toggleLaunchAtLogin() {
        guard LaunchAtLoginManager.canUpdateRegistration else {
            refreshLaunchAtLoginStatus()
            return
        }

        let shouldEnable = launchAtLoginCheckbox.state == .on

        do {
            try LaunchAtLoginManager.setEnabled(shouldEnable)
            refreshLaunchAtLoginStatus()
        } catch {
            refreshLaunchAtLoginStatus()
            launchStatusLabel.stringValue = "Could not update: \(error.localizedDescription)"
            launchStatusLabel.textColor = .systemRed
        }
    }

    @objc private func openLoginItemsSettings() {
        LaunchAtLoginManager.openSettings()
    }

    @objc private func requestAccessibilityPermission() {
        _ = AccessibilityPermission.requestIfNeeded()
        refreshAccessibilityStatus()
    }

    @objc private func openAccessibilitySettings() {
        AccessibilityPermission.openSettings()
    }

    @objc private func refreshStatuses() {
        refresh()
    }
}

extension PreferencesWindowController: NSWindowDelegate {
    func windowDidBecomeKey(_ notification: Notification) {
        refresh()
    }
}
