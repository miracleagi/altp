import AppKit

final class SearchPanelController: NSObject {
    private let catalog: WindowCatalog
    private let panel: SearchPanel
    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: "No matching windows")
    private let permissionBanner = NSView()
    private var eventMonitor: Any?

    private var allWindows: [WindowItem] = []
    private var filteredWindows: [WindowItem] = []
    private var sourceWindow: WindowItem?

    init(catalog: WindowCatalog) {
        self.catalog = catalog
        self.panel = SearchPanel(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 480),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        super.init()
        configurePanel()
        buildInterface()
        installEventMonitor()
    }

    deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }

    func toggle() {
        panel.isVisible ? hide() : show()
    }

    func show() {
        searchField.stringValue = ""
        reloadWindowList()
        positionPanel()

        panel.alphaValue = 1
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(searchField)
    }

    func hide() {
        panel.orderOut(nil)
        sourceWindow = nil
    }

    func reloadWindowList() {
        if AccessibilityPermission.isTrusted {
            allWindows = catalog.allWindows()
            sourceWindow = WindowRanking.currentWindow(in: allWindows)
            if let sourceWindow {
                WindowSelectionMemory.shared.recordObservation(sourceWindow)
            }
        } else {
            allWindows = []
            sourceWindow = nil
        }

        permissionBanner.isHidden = AccessibilityPermission.isTrusted
        applyFilter()
    }

    private func configurePanel() {
        panel.delegate = self
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
    }

    private func buildInterface() {
        let effectView = NSVisualEffectView()
        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 14
        effectView.layer?.masksToBounds = true
        panel.contentView = effectView

        let rootStack = NSStackView()
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 12
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 14),
            rootStack.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -14),
            rootStack.topAnchor.constraint(equalTo: effectView.topAnchor, constant: 14),
            rootStack.bottomAnchor.constraint(equalTo: effectView.bottomAnchor, constant: -14)
        ])

        searchField.placeholderString = "Search windows"
        searchField.font = .systemFont(ofSize: 22, weight: .regular)
        searchField.controlSize = .large
        searchField.focusRingType = .none
        searchField.sendsSearchStringImmediately = true
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        rootStack.addArrangedSubview(searchField)

        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: rootStack.leadingAnchor),
            searchField.trailingAnchor.constraint(equalTo: rootStack.trailingAnchor),
            searchField.heightAnchor.constraint(equalToConstant: 44)
        ])

        buildPermissionBanner(in: rootStack)
        buildWindowList(in: rootStack)
    }

    private func buildPermissionBanner(in rootStack: NSStackView) {
        permissionBanner.wantsLayer = true
        permissionBanner.layer?.cornerRadius = 8
        permissionBanner.layer?.backgroundColor = NSColor.systemYellow.withAlphaComponent(0.16).cgColor
        permissionBanner.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: "Accessibility permission is required to list and focus windows.")
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false

        let retryButton = NSButton(title: "Retry", target: self, action: #selector(retryAccessibilityPermission))
        retryButton.bezelStyle = .rounded
        retryButton.controlSize = .small
        retryButton.translatesAutoresizingMaskIntoConstraints = false

        let settingsButton = NSButton(title: "Open Settings", target: self, action: #selector(openAccessibilitySettings))
        settingsButton.bezelStyle = .rounded
        settingsButton.controlSize = .small
        settingsButton.translatesAutoresizingMaskIntoConstraints = false

        rootStack.addArrangedSubview(permissionBanner)

        let bannerStack = NSStackView(views: [label, retryButton, settingsButton])
        bannerStack.orientation = .horizontal
        bannerStack.alignment = .centerY
        bannerStack.spacing = 8
        bannerStack.translatesAutoresizingMaskIntoConstraints = false
        permissionBanner.addSubview(bannerStack)

        NSLayoutConstraint.activate([
            permissionBanner.leadingAnchor.constraint(equalTo: rootStack.leadingAnchor),
            permissionBanner.trailingAnchor.constraint(equalTo: rootStack.trailingAnchor),
            permissionBanner.heightAnchor.constraint(equalToConstant: 42),

            bannerStack.leadingAnchor.constraint(equalTo: permissionBanner.leadingAnchor, constant: 12),
            bannerStack.trailingAnchor.constraint(equalTo: permissionBanner.trailingAnchor, constant: -10),
            bannerStack.centerYAnchor.constraint(equalTo: permissionBanner.centerYAnchor)
        ])

        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        retryButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        settingsButton.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    private func buildWindowList(in rootStack: NSStackView) {
        let listContainer = NSView()
        listContainer.translatesAutoresizingMaskIntoConstraints = false
        rootStack.addArrangedSubview(listContainer)

        NSLayoutConstraint.activate([
            listContainer.leadingAnchor.constraint(equalTo: rootStack.leadingAnchor),
            listContainer.trailingAnchor.constraint(equalTo: rootStack.trailingAnchor),
            listContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 320)
        ])

        tableView.headerView = nil
        tableView.rowHeight = 62
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.selectionHighlightStyle = .regular
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.backgroundColor = .clear
        tableView.delegate = self
        tableView.dataSource = self
        tableView.doubleAction = #selector(activateSelectedWindow)
        tableView.target = self

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("WindowColumn"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = tableView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        listContainer.addSubview(scrollView)

        emptyLabel.font = .systemFont(ofSize: 15, weight: .medium)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        listContainer.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: listContainer.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: listContainer.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: listContainer.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: listContainer.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: listContainer.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: listContainer.centerYAnchor)
        ])
    }

    private func installEventMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isVisible else {
                return event
            }

            switch event.keyCode {
            case 36, 76:
                self.activateSelectedWindow()
                return nil
            case 53:
                self.hide()
                return nil
            case 125:
                self.moveSelection(delta: 1)
                return nil
            case 126:
                self.moveSelection(delta: -1)
                return nil
            default:
                return event
            }
        }
    }

    private func positionPanel() {
        let targetScreen = screenContainingMouse() ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen = targetScreen else {
            return
        }

        let visibleFrame = screen.visibleFrame
        let width = min(760, visibleFrame.width - 48)
        let height = min(480, visibleFrame.height - 96)
        let origin = NSPoint(
            x: visibleFrame.midX - width / 2,
            y: visibleFrame.midY - height / 2 + visibleFrame.height * 0.08
        )

        panel.setFrame(NSRect(x: origin.x, y: origin.y, width: width, height: height), display: true)
    }

    private func screenContainingMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { screen in
            screen.frame.contains(mouseLocation)
        }
    }

    private func applyFilter() {
        let query = SearchText.normalize(searchField.stringValue)
        let tokens = SearchText.tokens(in: query)
        let rankingReferenceTime = Date().timeIntervalSince1970

        let rankedWindows = allWindows
            .compactMap { item -> (WindowItem, Int)? in
                if !tokens.isEmpty {
                    guard tokens.allSatisfy({ item.searchableText.contains($0) }) else {
                        return nil
                    }
                }

                return (item, score(item: item, tokens: tokens, query: query))
            }

        if tokens.isEmpty {
            filteredWindows = WindowRanking.sortedForEmptyQuery(
                rankedWindows.map(\.0),
                sourceWindow: sourceWindow
            )
        } else {
            filteredWindows = rankedWindows
                .sorted { lhs, rhs in
                    if lhs.1 != rhs.1 {
                        return lhs.1 > rhs.1
                    }
                    return WindowRanking.isPreferred(
                        lhs.0,
                        over: rhs.0,
                        sourceWindow: sourceWindow,
                        referenceTime: rankingReferenceTime
                    )
                }
                .map(\.0)
        }

        tableView.reloadData()
        emptyLabel.isHidden = !filteredWindows.isEmpty || !AccessibilityPermission.isTrusted

        if filteredWindows.isEmpty {
            tableView.deselectAll(nil)
        } else if query.isEmpty,
                  let sourceWindow,
                  let nextWindowIndex = filteredWindows.firstIndex(where: {
                      !$0.representsSameWindow(as: sourceWindow)
                  }) {
            selectRow(nextWindowIndex)
        } else {
            selectRow(0)
        }
    }

    private func score(item: WindowItem, tokens: [String], query: String) -> Int {
        var score = tokens.isEmpty ? 0 : max(0, 1_000 - item.order)

        for token in tokens {
            let titleMatch = SearchText.matchQuality(token: token, in: item.displayTitle)
            let appNameMatch = SearchText.matchQuality(token: token, in: item.appName)

            if titleMatch == .prefix {
                score += 700
            } else if appNameMatch == .prefix {
                score += 550
            } else if titleMatch == .contains {
                score += 350
            } else if appNameMatch == .contains {
                score += 250
            } else {
                score += 50
            }
        }

        if item.isMinimized {
            score -= 50
        }

        score += WindowSelectionMemory.shared.score(for: item, query: query)
        return score
    }

    private func moveSelection(delta: Int) {
        guard !filteredWindows.isEmpty else {
            return
        }

        let current = tableView.selectedRow >= 0 ? tableView.selectedRow : 0
        let next = max(0, min(filteredWindows.count - 1, current + delta))
        selectRow(next)
    }

    private func selectRow(_ row: Int) {
        guard row >= 0, row < filteredWindows.count else {
            return
        }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
    }

    @objc private func activateSelectedWindow() {
        let row = tableView.selectedRow >= 0 ? tableView.selectedRow : 0
        guard row >= 0, row < filteredWindows.count else {
            NSSound.beep()
            return
        }

        let item = filteredWindows[row]
        let source = sourceWindow
        hide()
        let result = catalog.activate(item)
        if result == .success {
            WindowSelectionMemory.shared.recordSelection(
                item,
                query: searchField.stringValue,
                from: source
            )
        } else {
            NSSound.beep()
        }
    }

    @objc private func retryAccessibilityPermission() {
        _ = AccessibilityPermission.requestIfNeeded()
        reloadWindowList()
        panel.makeFirstResponder(searchField)
    }

    @objc private func openAccessibilitySettings() {
        AccessibilityPermission.openSettings()
    }
}

extension SearchPanelController: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        applyFilter()
    }
}

extension SearchPanelController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        filteredWindows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < filteredWindows.count else {
            return nil
        }

        let identifier = WindowCellView.identifier
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? WindowCellView
            ?? WindowCellView()
        cell.identifier = identifier
        cell.configure(with: filteredWindows[row])
        return cell
    }
}

extension SearchPanelController: NSWindowDelegate {
    func windowDidResignKey(_ notification: Notification) {
        hide()
    }
}

private final class SearchPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}

private final class WindowCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("WindowCellView")

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func configure(with item: WindowItem) {
        iconView.image = item.icon
        titleLabel.stringValue = item.displayTitle
        detailLabel.stringValue = item.subtitle
    }

    private func build() {
        wantsLayer = true

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.maximumNumberOfLines = 1
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(detailLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 36),
            iconView.heightAnchor.constraint(equalToConstant: 36),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),

            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4)
        ])
    }
}
