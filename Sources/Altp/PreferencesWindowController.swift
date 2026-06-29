import AppKit

final class PreferencesWindowController: NSWindowController {
    var onShortcutChanged: (() -> Void)?

    private enum Pane {
        case general
        case permissions
    }

    private enum ToolbarID {
        static let settings = NSToolbar.Identifier("AltpSettingsToolbar")
        static let general = NSToolbarItem.Identifier("AltpSettingsGeneral")
        static let permissions = NSToolbarItem.Identifier("AltpSettingsPermissions")
    }

    private let contentContainer = NSView()
    private let generalPane = NSView()
    private let permissionsPane = NSView()

    private let searchShortcutButton = ShortcutRecorderButton(shortcut: AppSettings.searchShortcut)
    private let searchHotKeyStatusLabel = NSTextField(labelWithString: "")
    private let quickSwitchShortcutButton = ShortcutRecorderButton(shortcut: AppSettings.quickSwitchShortcut)
    private let quickSwitchHotKeyStatusLabel = NSTextField(labelWithString: "")

    private let launchAtLoginSwitch = NSSwitch()
    private let launchStatusLabel = NSTextField(labelWithString: "")

    private let accessibilityDot = NSView()
    private let accessibilityStatusLabel = NSTextField(labelWithString: "")
    private let requestAccessibilityButton = NSButton(title: "Request Permission", target: nil, action: nil)

    private var currentPane: Pane = .general

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 430),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.toolbarStyle = .preference
        window.center()

        super.init(window: window)
        window.delegate = self
        configureToolbar()
        buildInterface()
        refresh()
        selectPane(.general)
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

    func updateSearchHotKeyStatus(_ message: String, isError: Bool) {
        searchHotKeyStatusLabel.stringValue = message
        searchHotKeyStatusLabel.textColor = isError ? .systemRed : .secondaryLabelColor
    }

    func updateQuickSwitchHotKeyStatus(_ message: String, isError: Bool) {
        quickSwitchHotKeyStatusLabel.stringValue = message
        quickSwitchHotKeyStatusLabel.textColor = isError ? .systemRed : .secondaryLabelColor
    }

    func refresh() {
        searchShortcutButton.shortcut = AppSettings.searchShortcut
        quickSwitchShortcutButton.shortcut = AppSettings.quickSwitchShortcut
        refreshLaunchAtLoginStatus()
        refreshAccessibilityStatus()
    }

    private func configureToolbar() {
        let toolbar = NSToolbar(identifier: ToolbarID.settings)
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.sizeMode = .regular
        toolbar.allowsUserCustomization = false
        toolbar.selectedItemIdentifier = ToolbarID.general
        window?.toolbar = toolbar
    }

    private func buildInterface() {
        guard let contentView = window?.contentView else {
            return
        }

        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(contentContainer)

        NSLayoutConstraint.activate([
            contentContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            contentContainer.topAnchor.constraint(equalTo: contentView.topAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        generalPane.translatesAutoresizingMaskIntoConstraints = false
        permissionsPane.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(generalPane)
        contentContainer.addSubview(permissionsPane)

        for pane in [generalPane, permissionsPane] {
            NSLayoutConstraint.activate([
                pane.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
                pane.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
                pane.topAnchor.constraint(equalTo: contentContainer.topAnchor),
                pane.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
            ])
        }

        buildGeneralPane()
        buildPermissionsPane()
    }

    private func buildGeneralPane() {
        let rootStack = paneStack(title: "General")
        generalPane.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: generalPane.leadingAnchor, constant: 28),
            rootStack.trailingAnchor.constraint(equalTo: generalPane.trailingAnchor, constant: -28),
            rootStack.topAnchor.constraint(equalTo: generalPane.topAnchor, constant: 24)
        ])

        let resetSearchButton = secondaryButton(title: "Reset", action: #selector(resetSearchShortcut))
        searchShortcutButton.onShortcutChange = { [weak self] shortcut in
            AppSettings.searchShortcut = shortcut
            self?.updateSearchHotKeyStatus("Registering \(shortcut.displayString)...", isError: false)
            self?.onShortcutChanged?()
        }

        let searchShortcutControls = horizontalStack([searchShortcutButton, resetSearchButton], spacing: 8)
        let resetQuickSwitchButton = secondaryButton(title: "Reset", action: #selector(resetQuickSwitchShortcut))
        quickSwitchShortcutButton.onShortcutChange = { [weak self] shortcut in
            AppSettings.quickSwitchShortcut = shortcut
            self?.updateQuickSwitchHotKeyStatus("Registering \(shortcut.displayString)...", isError: false)
            self?.onShortcutChanged?()
        }

        let quickSwitchControls = horizontalStack([quickSwitchShortcutButton, resetQuickSwitchButton], spacing: 8)
        rootStack.addArrangedSubview(settingGroup(rows: [
            settingRow(
                title: "Search Shortcut",
                detail: "Use this shortcut to show or hide window search.",
                control: searchShortcutControls,
                statusLabel: searchHotKeyStatusLabel
            ),
            settingRow(
                title: "Quick Switch Shortcut",
                detail: "Show a selectable switcher for recent windows.",
                control: quickSwitchControls,
                statusLabel: quickSwitchHotKeyStatusLabel
            )
        ]))

        launchAtLoginSwitch.target = self
        launchAtLoginSwitch.action = #selector(toggleLaunchAtLogin)
        launchAtLoginSwitch.setContentHuggingPriority(.required, for: .horizontal)

        let loginItemsButton = secondaryButton(title: "Open Login Items", action: #selector(openLoginItemsSettings))
        let startupControls = horizontalStack([launchAtLoginSwitch, loginItemsButton], spacing: 10)
        rootStack.addArrangedSubview(settingGroup(rows: [
            settingRow(
                title: "Open at Login",
                detail: "Start Altp automatically when you sign in.",
                control: startupControls,
                statusLabel: launchStatusLabel
            )
        ]))
    }

    private func buildPermissionsPane() {
        let rootStack = paneStack(title: "Permissions")
        permissionsPane.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: permissionsPane.leadingAnchor, constant: 28),
            rootStack.trailingAnchor.constraint(equalTo: permissionsPane.trailingAnchor, constant: -28),
            rootStack.topAnchor.constraint(equalTo: permissionsPane.topAnchor, constant: 24)
        ])

        requestAccessibilityButton.target = self
        requestAccessibilityButton.action = #selector(requestAccessibilityPermission)
        requestAccessibilityButton.bezelStyle = .rounded
        requestAccessibilityButton.controlSize = .regular

        let settingsButton = secondaryButton(title: "Open Settings", action: #selector(openAccessibilitySettings))
        let refreshButton = secondaryButton(title: "Refresh", action: #selector(refreshStatuses))

        accessibilityDot.wantsLayer = true
        accessibilityDot.layer?.cornerRadius = 5
        accessibilityDot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            accessibilityDot.widthAnchor.constraint(equalToConstant: 10),
            accessibilityDot.heightAnchor.constraint(equalToConstant: 10)
        ])

        let accessibilityState = horizontalStack([accessibilityDot, accessibilityStatusLabel], spacing: 8)
        let accessibilityActions = horizontalStack([requestAccessibilityButton, settingsButton, refreshButton], spacing: 8)
        let accessibilityControls = verticalStack([accessibilityState, accessibilityActions], spacing: 10)

        rootStack.addArrangedSubview(settingGroup(rows: [
            settingRow(
                title: "Accessibility",
                detail: "Required to list windows and focus the selected one.",
                control: accessibilityControls,
                statusLabel: nil
            )
        ]))
    }

    private func paneStack(title: String) -> NSStackView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.textColor = .labelColor

        let stack = NSStackView(views: [titleLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func settingGroup(rows: [NSView]) -> NSView {
        let group = NSView()
        group.wantsLayer = true
        group.layer?.cornerRadius = 8
        group.layer?.borderWidth = 1
        group.layer?.borderColor = NSColor.separatorColor.cgColor
        group.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.55).cgColor
        group.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        group.addSubview(stack)

        for (index, row) in rows.enumerated() {
            stack.addArrangedSubview(row)
            if index < rows.count - 1 {
                stack.addArrangedSubview(separator())
            }
        }

        NSLayoutConstraint.activate([
            group.widthAnchor.constraint(equalToConstant: 564),
            stack.leadingAnchor.constraint(equalTo: group.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: group.trailingAnchor),
            stack.topAnchor.constraint(equalTo: group.topAnchor),
            stack.bottomAnchor.constraint(equalTo: group.bottomAnchor)
        ])

        return group
    }

    private func settingRow(
        title: String,
        detail: String,
        control: NSView,
        statusLabel: NSTextField?
    ) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.widthAnchor.constraint(equalToConstant: 150).isActive = true

        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byWordWrapping
        detailLabel.maximumNumberOfLines = 2

        let rightStack = verticalStack([control, detailLabel], spacing: 6)
        if let statusLabel {
            statusLabel.font = .systemFont(ofSize: 12)
            statusLabel.textColor = .secondaryLabelColor
            statusLabel.lineBreakMode = .byWordWrapping
            statusLabel.maximumNumberOfLines = 2
            rightStack.addArrangedSubview(statusLabel)
        }

        let contentStack = NSStackView(views: [titleLabel, rightStack])
        contentStack.orientation = .horizontal
        contentStack.alignment = .top
        contentStack.spacing = 18
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(contentStack)

        NSLayoutConstraint.activate([
            row.widthAnchor.constraint(equalToConstant: 564),
            contentStack.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            contentStack.topAnchor.constraint(equalTo: row.topAnchor, constant: 14),
            contentStack.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -14)
        ])

        return row
    }

    private func separator() -> NSBox {
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.widthAnchor.constraint(equalToConstant: 564).isActive = true
        return separator
    }

    private func horizontalStack(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = spacing
        return stack
    }

    private func verticalStack(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        return stack
    }

    private func secondaryButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .regular
        return button
    }

    private func selectPane(_ pane: Pane) {
        currentPane = pane
        generalPane.isHidden = pane != .general
        permissionsPane.isHidden = pane != .permissions

        switch pane {
        case .general:
            window?.toolbar?.selectedItemIdentifier = ToolbarID.general
            window?.title = "Settings"
        case .permissions:
            window?.toolbar?.selectedItemIdentifier = ToolbarID.permissions
            window?.title = "Settings"
        }
    }

    private func refreshLaunchAtLoginStatus() {
        let status = LaunchAtLoginManager.status
        launchAtLoginSwitch.isEnabled = LaunchAtLoginManager.canUpdateRegistration

        switch status {
        case .enabled:
            launchAtLoginSwitch.state = .on
            launchStatusLabel.textColor = .secondaryLabelColor
        case .notRegistered:
            launchAtLoginSwitch.state = .off
            launchStatusLabel.textColor = .secondaryLabelColor
        case .requiresApproval:
            launchAtLoginSwitch.state = .off
            launchStatusLabel.textColor = .systemOrange
        case .helperMissing:
            launchAtLoginSwitch.state = .off
            launchStatusLabel.textColor = .systemOrange
        case .unavailable:
            launchAtLoginSwitch.state = .off
            launchStatusLabel.textColor = .systemRed
        }

        launchStatusLabel.stringValue = LaunchAtLoginManager.statusText
    }

    private func refreshAccessibilityStatus() {
        if AccessibilityPermission.isTrusted {
            accessibilityStatusLabel.stringValue = "Granted"
            accessibilityStatusLabel.textColor = .labelColor
            accessibilityDot.layer?.backgroundColor = NSColor.systemGreen.cgColor
            requestAccessibilityButton.isEnabled = false
        } else {
            accessibilityStatusLabel.stringValue = "Required"
            accessibilityStatusLabel.textColor = .labelColor
            accessibilityDot.layer?.backgroundColor = NSColor.systemOrange.cgColor
            requestAccessibilityButton.isEnabled = true
        }
    }

    @objc private func selectToolbarItem(_ sender: NSToolbarItem) {
        if sender.itemIdentifier == ToolbarID.general {
            selectPane(.general)
        } else if sender.itemIdentifier == ToolbarID.permissions {
            selectPane(.permissions)
        }
    }

    @objc private func resetSearchShortcut() {
        AppSettings.resetSearchShortcut()
        searchShortcutButton.shortcut = AppSettings.searchShortcut
        updateSearchHotKeyStatus("Registering \(AppSettings.searchShortcut.displayString)...", isError: false)
        onShortcutChanged?()
    }

    @objc private func resetQuickSwitchShortcut() {
        AppSettings.resetQuickSwitchShortcut()
        quickSwitchShortcutButton.shortcut = AppSettings.quickSwitchShortcut
        updateQuickSwitchHotKeyStatus("Registering \(AppSettings.quickSwitchShortcut.displayString)...", isError: false)
        onShortcutChanged?()
    }

    @objc private func toggleLaunchAtLogin() {
        guard LaunchAtLoginManager.canUpdateRegistration else {
            refreshLaunchAtLoginStatus()
            return
        }

        let shouldEnable = launchAtLoginSwitch.state == .on

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

extension PreferencesWindowController: NSToolbarDelegate {
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [ToolbarID.general, ToolbarID.permissions]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [ToolbarID.general, ToolbarID.permissions]
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [ToolbarID.general, ToolbarID.permissions]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.target = self
        item.action = #selector(selectToolbarItem(_:))

        if itemIdentifier == ToolbarID.general {
            item.label = "General"
            item.paletteLabel = "General"
            item.toolTip = "General settings"
            item.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "General")
        } else if itemIdentifier == ToolbarID.permissions {
            item.label = "Permissions"
            item.paletteLabel = "Permissions"
            item.toolTip = "Permission settings"
            item.image = NSImage(systemSymbolName: "hand.raised", accessibilityDescription: "Permissions")
        }

        return item
    }
}

extension PreferencesWindowController: NSWindowDelegate {
    func windowDidBecomeKey(_ notification: Notification) {
        refresh()
    }
}
