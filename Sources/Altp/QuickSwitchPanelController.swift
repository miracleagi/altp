import AppKit
import CoreGraphics

final class QuickSwitchPanelController: NSObject {
    private let catalog: WindowCatalog
    private let panel: QuickSwitchPanel
    private let collectionView = NSCollectionView()
    private let flowLayout = NSCollectionViewFlowLayout()
    private let scrollView = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: "No windows")
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var modifierReleaseTimer: Timer?
    private var windows: [WindowItem] = []
    private var sourceWindow: WindowItem?
    private var shouldActivateOnModifierRelease = false
    private var isActivatingSelection = false
    private var layoutColumnCount = 1
    private var layoutMetrics = QuickSwitchLayoutPolicy.metrics(
        forVisibleWidth: QuickSwitchLayoutPolicy.referenceScreenWidth
    )

    init(catalog: WindowCatalog) {
        self.catalog = catalog
        self.panel = QuickSwitchPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1_100, height: 142),
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
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
        }
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
        }
        stopModifierReleasePolling()
    }

    func showOrAdvance(activateOnModifierRelease: Bool = false) {
        if panel.isVisible {
            shouldActivateOnModifierRelease = shouldActivateOnModifierRelease || activateOnModifierRelease
            startModifierReleasePollingIfNeeded()
            if let screen = targetScreen() {
                if updateLayout(for: screen) {
                    collectionView.reloadData()
                }
                positionPanel(on: screen)
            }
            moveSelection(delta: 1)
            return
        }

        show(activateOnModifierRelease: activateOnModifierRelease)
    }

    func hide() {
        panel.orderOut(nil)
        sourceWindow = nil
        shouldActivateOnModifierRelease = false
        isActivatingSelection = false
        stopModifierReleasePolling()
    }

    private func show(activateOnModifierRelease: Bool) {
        guard AccessibilityPermission.isTrusted else {
            NSSound.beep()
            return
        }

        let allWindows = catalog.allWindows()
        sourceWindow = WindowRanking.currentWindow(in: allWindows)
        if let sourceWindow {
            WindowSelectionMemory.shared.recordObservation(sourceWindow)
        }
        shouldActivateOnModifierRelease = activateOnModifierRelease
        windows = WindowRanking.sortedForEmptyQuery(allWindows, sourceWindow: sourceWindow)
        collectionView.selectionIndexPaths = []
        emptyLabel.isHidden = !windows.isEmpty

        guard !windows.isEmpty else {
            NSSound.beep()
            return
        }

        guard let screen = targetScreen() else {
            NSSound.beep()
            return
        }
        updateLayout(for: screen)
        collectionView.reloadData()
        positionPanel(on: screen)
        selectRow(defaultSelectionRow())

        panel.alphaValue = 1
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(collectionView)
        startModifierReleasePollingIfNeeded()
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
        effectView.layer?.cornerRadius = 12
        effectView.layer?.masksToBounds = true
        panel.contentView = effectView

        flowLayout.scrollDirection = .vertical
        collectionView.collectionViewLayout = flowLayout
        applyLayoutMetrics()
        collectionView.backgroundColors = [.clear]
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = false
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.register(
            QuickSwitchWindowItem.self,
            forItemWithIdentifier: QuickSwitchWindowItem.identifier
        )

        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.horizontalScrollElasticity = .none
        scrollView.verticalScrollElasticity = .automatic
        scrollView.documentView = collectionView
        scrollView.hasHorizontalScroller = false
        scrollView.horizontalScroller = nil
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(scrollView)

        emptyLabel.font = .systemFont(ofSize: 15, weight: .medium)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: effectView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: effectView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: effectView.centerYAnchor)
        ])
    }

    private func installEventMonitor() {
        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .flagsChanged, .leftMouseDown]
        ) { [weak self] event in
            guard let self, self.panel.isVisible else {
                return event
            }

            if event.type == .flagsChanged {
                self.activateIfModifierWasReleased(event.modifierFlags)
                return event
            }

            if event.type == .leftMouseDown {
                if event.clickCount == 2 {
                    self.activateItem(at: event.locationInWindow)
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
                self.moveSelectionVertically(direction: 1)
                return nil
            case 126:
                self.moveSelectionVertically(direction: -1)
                return nil
            case 123:
                self.moveSelection(delta: -1)
                return nil
            case 124:
                self.moveSelection(delta: 1)
                return nil
            default:
                return event
            }
        }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            DispatchQueue.main.async {
                self?.activateIfModifierWasReleased(event.modifierFlags)
            }
        }
    }

    private func positionPanel(on screen: NSScreen) {
        let visibleFrame = screen.visibleFrame
        let gridLayout = QuickSwitchLayoutPolicy.gridLayout(
            windowCount: windows.count,
            visibleFrame: visibleFrame,
            metrics: layoutMetrics
        )
        layoutColumnCount = gridLayout.columnCount
        scrollView.verticalScrollElasticity = gridLayout.requiresVerticalScrolling
            ? .automatic
            : .none

        let panelSize = gridLayout.panelSize
        let edgeMargin: CGFloat = 24
        let preferredY = visibleFrame.midY
            - panelSize.height / 2
            + visibleFrame.height * 0.08
        let maximumY = visibleFrame.maxY - panelSize.height - edgeMargin
        let origin = NSPoint(
            x: visibleFrame.midX - panelSize.width / 2,
            y: min(max(preferredY, visibleFrame.minY + edgeMargin), maximumY)
        )

        panel.setFrame(
            NSRect(origin: origin, size: panelSize),
            display: true
        )
    }

    private func targetScreen() -> NSScreen? {
        screenContainingMouse() ?? NSScreen.main ?? NSScreen.screens.first
    }

    @discardableResult
    private func updateLayout(for screen: NSScreen) -> Bool {
        let updatedMetrics = QuickSwitchLayoutPolicy.metrics(
            forVisibleWidth: screen.visibleFrame.width
        )
        guard updatedMetrics != layoutMetrics else {
            return false
        }

        layoutMetrics = updatedMetrics
        applyLayoutMetrics()
        flowLayout.invalidateLayout()
        return true
    }

    private func applyLayoutMetrics() {
        flowLayout.itemSize = NSSize(
            width: layoutMetrics.itemWidth,
            height: layoutMetrics.itemHeight
        )
        flowLayout.minimumInteritemSpacing = layoutMetrics.itemSpacing
        flowLayout.minimumLineSpacing = layoutMetrics.itemSpacing
        flowLayout.sectionInset = NSEdgeInsets(
            top: layoutMetrics.verticalInset,
            left: layoutMetrics.horizontalInset,
            bottom: layoutMetrics.verticalInset,
            right: layoutMetrics.horizontalInset
        )
    }

    private func screenContainingMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { screen in
            screen.frame.contains(mouseLocation)
        }
    }

    private func defaultSelectionRow() -> Int {
        guard let sourceWindow else {
            return 0
        }

        return windows.firstIndex { !$0.representsSameWindow(as: sourceWindow) } ?? 0
    }

    private func moveSelection(delta: Int) {
        guard !windows.isEmpty else {
            return
        }

        let current = collectionView.selectionIndexPaths.first?.item ?? 0
        let next = (current + delta + windows.count) % windows.count
        selectRow(next)
    }

    private func moveSelectionVertically(direction: Int) {
        guard !windows.isEmpty else {
            return
        }

        let current = collectionView.selectionIndexPaths.first?.item ?? 0
        let next = QuickSwitchGridNavigation.verticalDestination(
            from: current,
            direction: direction,
            itemCount: windows.count,
            columnCount: layoutColumnCount
        )
        selectRow(next)
    }

    private func selectRow(_ row: Int) {
        guard row >= 0, row < windows.count else {
            return
        }

        let indexPath = IndexPath(item: row, section: 0)
        collectionView.selectionIndexPaths = [indexPath]
        scrollItemToVisible(at: indexPath)
    }

    private func scrollItemToVisible(at indexPath: IndexPath) {
        panel.contentView?.layoutSubtreeIfNeeded()
        collectionView.layoutSubtreeIfNeeded()
        collectionView.scrollToItems(
            at: [indexPath],
            scrollPosition: .nearestVerticalEdge
        )
    }

    private func activateIfModifierWasReleased(_ modifierFlags: NSEvent.ModifierFlags) {
        guard shouldActivateOnModifierRelease,
              panel.isVisible,
              !isOptionPressed(in: modifierFlags) else {
            return
        }

        activateSelectedWindow()
    }

    private func startModifierReleasePollingIfNeeded() {
        guard shouldActivateOnModifierRelease, modifierReleaseTimer == nil else {
            return
        }

        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.activateIfModifierIsNoLongerPressed()
        }
        modifierReleaseTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopModifierReleasePolling() {
        modifierReleaseTimer?.invalidate()
        modifierReleaseTimer = nil
    }

    private func activateIfModifierIsNoLongerPressed() {
        guard shouldActivateOnModifierRelease,
              panel.isVisible,
              !isOptionPressedInSession() else {
            return
        }

        activateSelectedWindow()
    }

    private func isOptionPressed(in flags: NSEvent.ModifierFlags) -> Bool {
        flags.intersection(.deviceIndependentFlagsMask).contains(.option)
    }

    private func isOptionPressedInSession() -> Bool {
        CGEventSource.flagsState(.combinedSessionState).contains(.maskAlternate)
    }

    @objc private func activateSelectedWindow() {
        guard !isActivatingSelection else {
            return
        }
        isActivatingSelection = true

        let row = collectionView.selectionIndexPaths.first?.item ?? 0
        guard row >= 0, row < windows.count else {
            hide()
            NSSound.beep()
            return
        }

        let item = windows[row]
        let source = sourceWindow
        hide()
        catalog.activate(item) { result in
            if result == .success {
                WindowSelectionMemory.shared.recordSelection(item, query: "", from: source)
            } else {
                NSLog("Altp quick switch activation failed with AXError \(result.rawValue)")
                NSSound.beep()
            }
        }
    }

    private func activateItem(at windowLocation: NSPoint) {
        let collectionLocation = collectionView.convert(windowLocation, from: nil)
        guard let indexPath = collectionView.indexPathForItem(at: collectionLocation) else {
            return
        }

        selectRow(indexPath.item)
        activateSelectedWindow()
    }
}

extension QuickSwitchPanelController: NSCollectionViewDataSource, NSCollectionViewDelegate {
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        windows.count
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        let item = collectionView.makeItem(
            withIdentifier: QuickSwitchWindowItem.identifier,
            for: indexPath
        )
        guard let windowItem = item as? QuickSwitchWindowItem,
              indexPath.item < windows.count else {
            return item
        }

        windowItem.configure(
            with: windows[indexPath.item],
            layoutMetrics: layoutMetrics
        )
        return windowItem
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

private final class QuickSwitchWindowItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("QuickSwitchWindowItem")

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let appLabel = NSTextField(labelWithString: "")
    private var iconTopConstraint: NSLayoutConstraint?
    private var iconWidthConstraint: NSLayoutConstraint?
    private var iconHeightConstraint: NSLayoutConstraint?
    private var titleHeightConstraint: NSLayoutConstraint?
    private var titleLeadingConstraint: NSLayoutConstraint?
    private var titleTrailingConstraint: NSLayoutConstraint?
    private var titleTopConstraint: NSLayoutConstraint?
    private var appBottomConstraint: NSLayoutConstraint?
    private var layoutMetrics = QuickSwitchLayoutPolicy.metrics(
        forVisibleWidth: QuickSwitchLayoutPolicy.referenceScreenWidth
    )

    override var isSelected: Bool {
        didSet {
            updateSelectionAppearance()
        }
    }

    override func loadView() {
        view = NSView()
        buildInterface()
    }

    func configure(
        with item: WindowItem,
        layoutMetrics: QuickSwitchLayoutMetrics
    ) {
        self.layoutMetrics = layoutMetrics
        applyLayoutMetrics()
        iconView.image = item.icon
        titleLabel.stringValue = item.displayTitle
        titleLabel.toolTip = item.displayTitle
        appLabel.stringValue = item.appName
        updateTitleLayout(for: item.displayTitle)
        updateSelectionAppearance()
    }

    private func buildInterface() {
        view.wantsLayer = true
        view.layer?.cornerRadius = layoutMetrics.cardCornerRadius

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(iconView)

        titleLabel.font = .systemFont(ofSize: layoutMetrics.titleFontSize, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.maximumNumberOfLines = 2
        titleLabel.cell?.wraps = true
        titleLabel.cell?.usesSingleLineMode = false
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        appLabel.font = .systemFont(ofSize: layoutMetrics.appFontSize)
        appLabel.textColor = .secondaryLabelColor
        appLabel.lineBreakMode = .byTruncatingTail
        appLabel.maximumNumberOfLines = 1
        appLabel.alignment = .center
        appLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(appLabel)

        let iconTopConstraint = iconView.topAnchor.constraint(
            equalTo: view.topAnchor,
            constant: layoutMetrics.iconTopSingleLine
        )
        let iconWidthConstraint = iconView.widthAnchor.constraint(equalToConstant: layoutMetrics.iconSize)
        let iconHeightConstraint = iconView.heightAnchor.constraint(equalToConstant: layoutMetrics.iconSize)
        let titleHeightConstraint = titleLabel.heightAnchor.constraint(
            equalToConstant: layoutMetrics.titleLineHeight
        )
        let titleLeadingConstraint = titleLabel.leadingAnchor.constraint(
            equalTo: view.leadingAnchor,
            constant: layoutMetrics.contentSideInset
        )
        let titleTrailingConstraint = titleLabel.trailingAnchor.constraint(
            equalTo: view.trailingAnchor,
            constant: -layoutMetrics.contentSideInset
        )
        let titleTopConstraint = titleLabel.topAnchor.constraint(
            equalTo: iconView.bottomAnchor,
            constant: layoutMetrics.contentSideInset
        )
        let appBottomConstraint = appLabel.bottomAnchor.constraint(
            lessThanOrEqualTo: view.bottomAnchor,
            constant: -layoutMetrics.verticalInset
        )
        self.iconTopConstraint = iconTopConstraint
        self.iconWidthConstraint = iconWidthConstraint
        self.iconHeightConstraint = iconHeightConstraint
        self.titleHeightConstraint = titleHeightConstraint
        self.titleLeadingConstraint = titleLeadingConstraint
        self.titleTrailingConstraint = titleTrailingConstraint
        self.titleTopConstraint = titleTopConstraint
        self.appBottomConstraint = appBottomConstraint

        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            iconTopConstraint,
            iconWidthConstraint,
            iconHeightConstraint,

            titleLeadingConstraint,
            titleTrailingConstraint,
            titleTopConstraint,
            titleHeightConstraint,

            appLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            appLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            appLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            appBottomConstraint
        ])
    }

    private func applyLayoutMetrics() {
        view.layer?.cornerRadius = layoutMetrics.cardCornerRadius
        titleLabel.font = .systemFont(ofSize: layoutMetrics.titleFontSize, weight: .medium)
        appLabel.font = .systemFont(ofSize: layoutMetrics.appFontSize)
        iconWidthConstraint?.constant = layoutMetrics.iconSize
        iconHeightConstraint?.constant = layoutMetrics.iconSize
        titleLeadingConstraint?.constant = layoutMetrics.contentSideInset
        titleTrailingConstraint?.constant = -layoutMetrics.contentSideInset
        titleTopConstraint?.constant = layoutMetrics.contentSideInset
        appBottomConstraint?.constant = -layoutMetrics.verticalInset
    }

    private func updateTitleLayout(for title: String) {
        let availableWidth = layoutMetrics.itemWidth - layoutMetrics.contentSideInset * 2
        let measuredWidth = (title as NSString).size(
            withAttributes: [.font: titleLabel.font as Any]
        ).width
        let usesTwoLines = measuredWidth > availableWidth

        titleHeightConstraint?.constant = layoutMetrics.titleLineHeight * (usesTwoLines ? 2 : 1)
        iconTopConstraint?.constant = usesTwoLines
            ? layoutMetrics.iconTopTwoLines
            : layoutMetrics.iconTopSingleLine
    }

    private func updateSelectionAppearance() {
        view.layer?.backgroundColor = isSelected
            ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.32).cgColor
            : NSColor.clear.cgColor
        view.layer?.borderWidth = isSelected ? 1 : 0
        view.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
    }
}
