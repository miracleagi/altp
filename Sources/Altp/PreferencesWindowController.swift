import AppKit

private final class SettingsWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == .command,
           event.charactersIgnoringModifiers?.lowercased() == "w" {
            performClose(nil)
            return true
        }

        return super.performKeyEquivalent(with: event)
    }
}

final class PreferencesWindowController: NSWindowController {
    var onShortcutChanged: (() -> Void)?

    private enum Layout {
        static let windowWidth: CGFloat = 640
        static let generalHeight: CGFloat = 610
        static let permissionsHeight: CGFloat = 330
        static let horizontalInset: CGFloat = 24
        static let contentWidth = windowWidth - horizontalInset * 2
    }

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
    private let minimizedWindowsSwitch = NSSwitch()
    private let excludedTitleTokenField = NSTokenField()
    private let excludedTitleStatusLabel = NSTextField(labelWithString: "")

    private let launchAtLoginSwitch = NSSwitch()
    private let launchStatusLabel = NSTextField(labelWithString: "")

    private let accessibilityDot = NSView()
    private let accessibilityStatusLabel = NSTextField(labelWithString: "")
    private let requestAccessibilityButton = NSButton(title: "Request Permission", target: nil, action: nil)

    private var currentPane: Pane = .general

    init() {
        let window = SettingsWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: Layout.windowWidth,
                height: Layout.generalHeight
            ),
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
        searchHotKeyStatusLabel.stringValue = isError ? message : ""
        searchHotKeyStatusLabel.textColor = isError ? .systemRed : .secondaryLabelColor
    }

    func updateQuickSwitchHotKeyStatus(_ message: String, isError: Bool) {
        quickSwitchHotKeyStatusLabel.stringValue = isError ? message : ""
        quickSwitchHotKeyStatusLabel.textColor = isError ? .systemRed : .secondaryLabelColor
    }

    func refresh() {
        searchShortcutButton.shortcut = AppSettings.searchShortcut
        quickSwitchShortcutButton.shortcut = AppSettings.quickSwitchShortcut
        minimizedWindowsSwitch.state = AppSettings.showMinimizedWindows ? .on : .off
        refreshExcludedTitleRules()
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
        addCloseButton(to: generalPane)
        addCloseButton(to: permissionsPane)
    }

    private func buildGeneralPane() {
        let rootStack = paneStack(
            title: "General",
            subtitle: "Choose how Altp finds windows and responds to shortcuts."
        )
        generalPane.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: generalPane.leadingAnchor, constant: Layout.horizontalInset),
            rootStack.trailingAnchor.constraint(equalTo: generalPane.trailingAnchor, constant: -Layout.horizontalInset),
            rootStack.topAnchor.constraint(equalTo: generalPane.topAnchor, constant: 22)
        ])

        let resetSearchButton = secondaryButton(
            title: "Reset",
            action: #selector(resetSearchShortcut),
            controlSize: .small
        )
        searchShortcutButton.onShortcutChange = { [weak self] shortcut in
            AppSettings.searchShortcut = shortcut
            self?.updateSearchHotKeyStatus("Registering \(shortcut.displayString)...", isError: false)
            self?.onShortcutChanged?()
        }

        let searchShortcutControls = horizontalStack([searchShortcutButton, resetSearchButton], spacing: 8)
        let resetQuickSwitchButton = secondaryButton(
            title: "Reset",
            action: #selector(resetQuickSwitchShortcut),
            controlSize: .small
        )
        quickSwitchShortcutButton.onShortcutChange = { [weak self] shortcut in
            AppSettings.quickSwitchShortcut = shortcut
            self?.updateQuickSwitchHotKeyStatus("Registering \(shortcut.displayString)...", isError: false)
            self?.onShortcutChanged?()
        }

        let quickSwitchControls = horizontalStack([quickSwitchShortcutButton, resetQuickSwitchButton], spacing: 8)
        rootStack.addArrangedSubview(settingSection(title: "Shortcuts", rows: [
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

        minimizedWindowsSwitch.target = self
        minimizedWindowsSwitch.action = #selector(toggleMinimizedWindows)
        minimizedWindowsSwitch.setContentHuggingPriority(.required, for: .horizontal)

        configureExcludedTitleTokenField()
        let resetExcludedTitlesButton = secondaryButton(
            title: "Reset",
            action: #selector(resetExcludedWindowTitles),
            controlSize: .small
        )
        let excludedTitleControls = horizontalStack([excludedTitleTokenField, resetExcludedTitlesButton], spacing: 8)

        rootStack.addArrangedSubview(settingSection(title: "Windows", rows: [
            settingRow(
                title: "Show Minimized Windows",
                detail: "Hidden app windows are always excluded. Turn this off to hide minimized windows too.",
                control: minimizedWindowsSwitch,
                statusLabel: nil
            ),
            settingRow(
                title: "Exclude Window Titles",
                detail: "Hide internal windows whose title contains any token.",
                control: excludedTitleControls,
                statusLabel: excludedTitleStatusLabel
            )
        ]))

        launchAtLoginSwitch.target = self
        launchAtLoginSwitch.action = #selector(toggleLaunchAtLogin)
        launchAtLoginSwitch.setContentHuggingPriority(.required, for: .horizontal)

        let loginItemsButton = secondaryButton(title: "Open Login Items", action: #selector(openLoginItemsSettings))
        let startupControls = horizontalStack([launchAtLoginSwitch, loginItemsButton], spacing: 10)
        rootStack.addArrangedSubview(settingSection(title: "Startup", rows: [
            settingRow(
                title: "Open at Login",
                detail: "Start Altp automatically when you sign in.",
                control: startupControls,
                statusLabel: launchStatusLabel
            )
        ]))
    }

    private func buildPermissionsPane() {
        let rootStack = paneStack(
            title: "Permissions",
            subtitle: "Altp only needs access required to discover and focus your windows."
        )
        permissionsPane.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: permissionsPane.leadingAnchor, constant: Layout.horizontalInset),
            rootStack.trailingAnchor.constraint(equalTo: permissionsPane.trailingAnchor, constant: -Layout.horizontalInset),
            rootStack.topAnchor.constraint(equalTo: permissionsPane.topAnchor, constant: 22)
        ])

        requestAccessibilityButton.target = self
        requestAccessibilityButton.action = #selector(requestAccessibilityPermission)
        requestAccessibilityButton.bezelStyle = .rounded
        requestAccessibilityButton.controlSize = .regular

        let refreshButton = secondaryButton(title: "Refresh", action: #selector(refreshStatuses))

        accessibilityDot.wantsLayer = true
        accessibilityDot.layer?.cornerRadius = 5
        accessibilityDot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            accessibilityDot.widthAnchor.constraint(equalToConstant: 10),
            accessibilityDot.heightAnchor.constraint(equalToConstant: 10)
        ])

        let accessibilityState = horizontalStack([accessibilityDot, accessibilityStatusLabel], spacing: 8)
        let accessibilityActions = horizontalStack([requestAccessibilityButton, refreshButton], spacing: 8)
        let accessibilityControls = verticalStack([accessibilityState, accessibilityActions], spacing: 10)

        rootStack.addArrangedSubview(settingSection(title: "System Access", rows: [
            settingRow(
                title: "Accessibility",
                detail: "Required to list windows and focus the selected one.",
                control: accessibilityControls,
                statusLabel: nil
            )
        ]))
    }

    private func addCloseButton(to pane: NSView) {
        let closeButton = NSButton(title: "Done", target: self, action: #selector(closeSettings))
        closeButton.bezelStyle = .rounded
        closeButton.controlSize = .regular
        closeButton.keyEquivalent = "\u{1b}"
        closeButton.keyEquivalentModifierMask = []
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        pane.addSubview(closeButton)

        NSLayoutConstraint.activate([
            closeButton.trailingAnchor.constraint(equalTo: pane.trailingAnchor, constant: -Layout.horizontalInset),
            closeButton.bottomAnchor.constraint(equalTo: pane.bottomAnchor, constant: -16)
        ])
    }

    private func paneStack(title: String, subtitle: String) -> NSStackView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .labelColor

        let subtitleLabel = NSTextField(wrappingLabelWithString: subtitle)
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.maximumNumberOfLines = 2

        let header = verticalStack([titleLabel, subtitleLabel], spacing: 3)
        let stack = NSStackView(views: [header])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func settingSection(title: String, rows: [NSView]) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .secondaryLabelColor

        let stack = verticalStack([label, settingGroup(rows: rows)], spacing: 6)
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func settingGroup(rows: [NSView]) -> NSView {
        let group = NSBox()
        group.boxType = .custom
        group.cornerRadius = 8
        group.borderWidth = 1
        group.borderColor = .separatorColor
        group.fillColor = .controlBackgroundColor
        group.contentViewMargins = .zero
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
            group.widthAnchor.constraint(equalToConstant: Layout.contentWidth),
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

        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byWordWrapping
        detailLabel.maximumNumberOfLines = 2

        var labelViews: [NSView] = [titleLabel, detailLabel]
        if let statusLabel {
            statusLabel.font = .systemFont(ofSize: 12)
            statusLabel.textColor = .secondaryLabelColor
            statusLabel.lineBreakMode = .byWordWrapping
            statusLabel.maximumNumberOfLines = 2
            labelViews.append(statusLabel)
        }

        let labelStack = verticalStack(labelViews, spacing: 4)
        labelStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        labelStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)

        let contentStack = NSStackView(views: [labelStack, control])
        contentStack.orientation = .horizontal
        contentStack.alignment = .centerY
        contentStack.distribution = .fill
        contentStack.spacing = 16
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(contentStack)

        NSLayoutConstraint.activate([
            row.widthAnchor.constraint(equalToConstant: Layout.contentWidth),
            contentStack.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            contentStack.topAnchor.constraint(equalTo: row.topAnchor, constant: 12),
            contentStack.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -12)
        ])

        return row
    }

    private func separator() -> NSBox {
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.widthAnchor.constraint(equalToConstant: Layout.contentWidth).isActive = true
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

    private func secondaryButton(
        title: String,
        action: Selector,
        controlSize: NSControl.ControlSize = .regular
    ) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = controlSize
        return button
    }

    private func selectPane(_ pane: Pane) {
        currentPane = pane
        generalPane.isHidden = pane != .general
        permissionsPane.isHidden = pane != .permissions
        resizeWindow(for: pane)

        switch pane {
        case .general:
            window?.toolbar?.selectedItemIdentifier = ToolbarID.general
            window?.title = "Settings"
        case .permissions:
            window?.toolbar?.selectedItemIdentifier = ToolbarID.permissions
            window?.title = "Settings"
        }
    }

    private func resizeWindow(for pane: Pane) {
        guard let window else {
            return
        }

        let targetContentHeight: CGFloat = switch pane {
        case .general:
            Layout.generalHeight
        case .permissions:
            Layout.permissionsHeight
        }

        let targetFrame = window.frameRect(
            forContentRect: NSRect(
                x: 0,
                y: 0,
                width: Layout.windowWidth,
                height: targetContentHeight
            )
        )
        var frame = window.frame
        let topEdge = frame.maxY
        frame.size = targetFrame.size
        frame.origin.y = topEdge - frame.height

        guard abs(window.frame.height - frame.height) > 0.5 else {
            return
        }
        window.setFrame(frame, display: true, animate: window.isVisible)
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
            requestAccessibilityButton.title = AccessibilityPermission.hasRequestedThisLaunch
                ? "Open System Settings"
                : "Request Permission"
        }
    }

    private func configureExcludedTitleTokenField() {
        excludedTitleTokenField.tokenizingCharacterSet = CharacterSet(charactersIn: ",\n")
        excludedTitleTokenField.placeholderString = "Window title"
        excludedTitleTokenField.controlSize = .regular
        excludedTitleTokenField.font = .systemFont(ofSize: 13)
        excludedTitleTokenField.delegate = self
        excludedTitleTokenField.target = self
        excludedTitleTokenField.action = #selector(updateExcludedWindowTitles)
        excludedTitleTokenField.translatesAutoresizingMaskIntoConstraints = false
        excludedTitleTokenField.widthAnchor.constraint(equalToConstant: 220).isActive = true
    }

    private func refreshExcludedTitleRules() {
        let patterns = AppSettings.excludedWindowTitlePatterns
        excludedTitleTokenField.stringValue = patterns.joined(separator: ", ")
        excludedTitleStatusLabel.stringValue = patterns.isEmpty
            ? "No title rules"
            : "\(patterns.count) title rule\(patterns.count == 1 ? "" : "s")"
        excludedTitleStatusLabel.textColor = .secondaryLabelColor
    }

    private func excludedWindowTitleTokens() -> [String] {
        AppSettings.sanitizeWindowTitlePatterns(
            excludedTitleTokenField.stringValue.components(separatedBy: CharacterSet(charactersIn: ",\n"))
        )
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

    @objc private func toggleMinimizedWindows() {
        AppSettings.showMinimizedWindows = minimizedWindowsSwitch.state == .on
    }

    @objc private func updateExcludedWindowTitles() {
        AppSettings.excludedWindowTitlePatterns = excludedWindowTitleTokens()
        refreshExcludedTitleRules()
    }

    @objc private func resetExcludedWindowTitles() {
        AppSettings.resetExcludedWindowTitlePatterns()
        refreshExcludedTitleRules()
    }

    @objc private func openLoginItemsSettings() {
        LaunchAtLoginManager.openSettings()
    }

    @objc private func requestAccessibilityPermission() {
        _ = AccessibilityPermission.requestIfNeeded()
        refreshAccessibilityStatus()
    }

    @objc private func refreshStatuses() {
        refresh()
    }

    @objc private func closeSettings() {
        window?.performClose(nil)
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

extension PreferencesWindowController: NSTokenFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let tokenField = obj.object as? NSTokenField,
              tokenField === excludedTitleTokenField else {
            return
        }

        updateExcludedWindowTitles()
    }
}
