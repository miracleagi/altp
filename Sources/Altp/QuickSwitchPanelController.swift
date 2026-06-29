import AppKit

final class QuickSwitchPanelController: NSObject {
    private let catalog: WindowCatalog
    private let panel: QuickSwitchPanel
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: "No windows")
    private var eventMonitor: Any?
    private var windows: [WindowItem] = []

    init(catalog: WindowCatalog) {
        self.catalog = catalog
        self.panel = QuickSwitchPanel(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 420),
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

    func showOrAdvance() {
        if panel.isVisible {
            moveSelection(delta: 1)
            return
        }

        show()
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func show() {
        guard AccessibilityPermission.isTrusted else {
            _ = AccessibilityPermission.requestIfNeeded()
            NSSound.beep()
            return
        }

        windows = catalog.allWindows()
        tableView.reloadData()
        emptyLabel.isHidden = !windows.isEmpty

        guard !windows.isEmpty else {
            NSSound.beep()
            return
        }

        selectRow(windows.count > 1 ? 1 : 0)
        positionPanel()

        panel.alphaValue = 1
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(tableView)
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

        tableView.headerView = nil
        tableView.rowHeight = 58
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
        effectView.addSubview(scrollView)

        emptyLabel.font = .systemFont(ofSize: 15, weight: .medium)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 10),
            scrollView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -10),
            scrollView.topAnchor.constraint(equalTo: effectView.topAnchor, constant: 10),
            scrollView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor, constant: -10),

            emptyLabel.centerXAnchor.constraint(equalTo: effectView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: effectView.centerYAnchor)
        ])
    }

    private func installEventMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.panel.isVisible else {
                return event
            }

            if event.type == .flagsChanged {
                if !event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.option) {
                    self.activateSelectedWindow()
                    return nil
                }
                return event
            }

            switch event.keyCode {
            case 36, 76:
                self.activateSelectedWindow()
                return nil
            case 48:
                self.moveSelection(delta: event.modifierFlags.contains(.shift) ? -1 : 1)
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
        let width = min(680, visibleFrame.width - 48)
        let visibleRows = min(max(windows.count, 1), 7)
        let height = min(CGFloat(visibleRows) * 60 + 20, visibleFrame.height - 96)
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

    private func moveSelection(delta: Int) {
        guard !windows.isEmpty else {
            return
        }

        let current = tableView.selectedRow >= 0 ? tableView.selectedRow : 0
        let next = (current + delta + windows.count) % windows.count
        selectRow(next)
    }

    private func selectRow(_ row: Int) {
        guard row >= 0, row < windows.count else {
            return
        }

        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
    }

    @objc private func activateSelectedWindow() {
        let row = tableView.selectedRow >= 0 ? tableView.selectedRow : 0
        guard row >= 0, row < windows.count else {
            hide()
            NSSound.beep()
            return
        }

        let item = windows[row]
        hide()
        let result = catalog.activate(item)
        WindowSelectionMemory.shared.recordSelection(item, query: "")

        if result != .success {
            NSSound.beep()
        }
    }
}

extension QuickSwitchPanelController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        windows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < windows.count else {
            return nil
        }

        let identifier = QuickSwitchWindowCellView.identifier
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? QuickSwitchWindowCellView
            ?? QuickSwitchWindowCellView()
        cell.identifier = identifier
        cell.configure(with: windows[row])
        return cell
    }
}

extension QuickSwitchPanelController: NSWindowDelegate {
    func windowDidResignKey(_ notification: Notification) {
        hide()
    }
}

private final class QuickSwitchPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}

private final class QuickSwitchWindowCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("QuickSwitchWindowCellView")

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
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),

            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4)
        ])
    }
}
