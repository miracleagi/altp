import AppKit
import Carbon
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
    private var activationModifierFlags: NSEvent.ModifierFlags = []
    private var isActivatingSelection = false
    private var layoutColumnCount = 1
    private var preferredNavigationColumn: Int?
    private var requiresVerticalScrolling = false
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
            if activateOnModifierRelease {
                activationModifierFlags = AppSettings.quickSwitchShortcut.eventModifierFlags
            }
            startModifierReleasePollingIfNeeded()
            if let screen = targetScreen() {
                if updateLayout(for: screen) {
                    collectionView.reloadData()
                }
                positionPanel(on: screen)
            }
            navigate(.next)
            return
        }

        show(activateOnModifierRelease: activateOnModifierRelease)
    }

    func hide() {
        panel.orderOut(nil)
        sourceWindow = nil
        shouldActivateOnModifierRelease = false
        activationModifierFlags = []
        isActivatingSelection = false
        preferredNavigationColumn = nil
        stopModifierReleasePolling()
    }

    private func show(activateOnModifierRelease: Bool) {
        guard AccessibilityPermission.isTrusted else {
            NSSound.beep()
            return
        }

        let sourceFocusSnapshot = WindowRanking.captureCurrentFocus()
        shouldActivateOnModifierRelease = activateOnModifierRelease
        activationModifierFlags = activateOnModifierRelease
            ? AppSettings.quickSwitchShortcut.eventModifierFlags
            : []
        panel.alphaValue = 0
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(collectionView)

        let allWindows = catalog.allWindows()
        sourceWindow = WindowRanking.currentWindow(
            in: allWindows,
            focusSnapshot: sourceFocusSnapshot
        )
        if let sourceWindow {
            WindowSelectionMemory.shared.recordObservation(sourceWindow)
        }
        windows = WindowRanking.sortedForEmptyQuery(allWindows, sourceWindow: sourceWindow)
        collectionView.selectionIndexPaths = []
        preferredNavigationColumn = nil
        emptyLabel.isHidden = !windows.isEmpty

        guard !windows.isEmpty else {
            hide()
            NSSound.beep()
            return
        }

        guard let screen = targetScreen() else {
            hide()
            NSSound.beep()
            return
        }
        updateLayout(for: screen)
        collectionView.reloadData()
        positionPanel(on: screen)
        selectRow(defaultSelectionRow())

        panel.alphaValue = 1
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
        collectionView.autoresizingMask = [.width]
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
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets()
        scrollView.scrollerInsets = NSEdgeInsets()
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
                guard event.window === self.panel else {
                    return event
                }
                self.updatePreferredNavigationColumn(at: event.locationInWindow)
                if event.clickCount == 2 {
                    self.activateItem(at: event.locationInWindow)
                    return nil
                }
                return event
            }

            guard self.panel.isKeyWindow || event.window === self.panel else {
                return event
            }
            return self.handleKeyDown(event) ? nil : event
        }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: .flagsChanged
        ) { [weak self] event in
            DispatchQueue.main.async {
                self?.activateIfModifierWasReleased(event.modifierFlags)
            }
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard panel.isVisible else {
            return false
        }

        switch event.keyCode {
        case UInt16(kVK_Return), UInt16(kVK_ANSI_KeypadEnter):
            activateSelectedWindow()
        case UInt16(kVK_Tab):
            navigate(event.modifierFlags.contains(.shift) ? .previous : .next)
        case UInt16(kVK_Escape):
            hide()
        case UInt16(kVK_DownArrow):
            navigate(.down)
        case UInt16(kVK_UpArrow):
            navigate(.up)
        case UInt16(kVK_LeftArrow):
            navigate(.previous)
        case UInt16(kVK_RightArrow):
            navigate(.next)
        default:
            return false
        }
        return true
    }

    private func positionPanel(on screen: NSScreen) {
        let visibleFrame = screen.visibleFrame
        let gridLayout = QuickSwitchLayoutPolicy.gridLayout(
            windowCount: windows.count,
            visibleFrame: visibleFrame,
            metrics: layoutMetrics
        )
        if layoutColumnCount != gridLayout.columnCount {
            layoutColumnCount = gridLayout.columnCount
            preferredNavigationColumn = selectedWindowIndex.map {
                $0 % layoutColumnCount
            }
        }

        var panelSize = gridLayout.panelSize
        setPanelFrame(size: panelSize, on: visibleFrame, display: false)
        panel.contentView?.layoutSubtreeIfNeeded()

        var viewportState = QuickSwitchCollectionViewport.synchronize(
            collectionView: collectionView,
            scrollView: scrollView,
            flowLayout: flowLayout,
            allowsVerticalScrolling: gridLayout.requiresVerticalScrolling
        )

        if gridLayout.showsAllWindows, viewportState.hasVerticalOverflow {
            let maximumHeight = max(
                panelSize.height,
                visibleFrame.height - QuickSwitchLayoutPolicy.panelVerticalMargin
            )
            panelSize.height = QuickSwitchLayoutPolicy.panelHeightResolvingOverflow(
                plannedHeight: panelSize.height,
                viewportHeight: viewportState.viewportSize.height,
                contentHeight: viewportState.contentSize.height,
                maximumHeight: maximumHeight
            )
            setPanelFrame(size: panelSize, on: visibleFrame, display: false)
            panel.contentView?.layoutSubtreeIfNeeded()
            viewportState = QuickSwitchCollectionViewport.synchronize(
                collectionView: collectionView,
                scrollView: scrollView,
                flowLayout: flowLayout,
                allowsVerticalScrolling: false
            )
        }

        requiresVerticalScrolling = gridLayout.requiresVerticalScrolling
            || viewportState.hasVerticalOverflow
        scrollView.verticalScrollElasticity = requiresVerticalScrolling
            ? .automatic
            : .none
        setPanelFrame(size: panelSize, on: visibleFrame, display: true)
    }

    private func setPanelFrame(
        size panelSize: NSSize,
        on visibleFrame: NSRect,
        display: Bool
    ) {
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
            display: display
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

    private var selectedWindowIndex: Int? {
        guard let index = collectionView.selectionIndexPaths.first?.item,
              windows.indices.contains(index) else {
            return nil
        }
        return index
    }

    private func navigate(_ direction: QuickSwitchNavigationDirection) {
        guard let result = QuickSwitchGridNavigation.destination(
            from: selectedWindowIndex,
            preferredColumn: preferredNavigationColumn,
            direction: direction,
            itemCount: windows.count,
            columnCount: layoutColumnCount
        ) else {
            return
        }

        preferredNavigationColumn = result.preferredColumn
        selectRow(result.index, updatesPreferredColumn: false)
    }

    private func selectRow(
        _ row: Int,
        updatesPreferredColumn: Bool = true
    ) {
        guard row >= 0, row < windows.count else {
            return
        }

        if updatesPreferredColumn {
            preferredNavigationColumn = row % max(layoutColumnCount, 1)
        }
        let indexPath = IndexPath(item: row, section: 0)
        collectionView.selectionIndexPaths = [indexPath]
        scrollItemToVisible(at: indexPath)
    }

    private func scrollItemToVisible(at indexPath: IndexPath) {
        guard requiresVerticalScrolling else {
            return
        }

        collectionView.layoutSubtreeIfNeeded()
        if let attributes = flowLayout.layoutAttributesForItem(at: indexPath),
           scrollView.contentView.documentVisibleRect.contains(attributes.frame) {
            return
        }
        QuickSwitchCollectionViewport.reveal(
            indexPath,
            collectionView: collectionView,
            scrollView: scrollView,
            allowsVerticalScrolling: requiresVerticalScrolling
        )
    }

    private func activateIfModifierWasReleased(_ modifierFlags: NSEvent.ModifierFlags) {
        guard shouldActivateOnModifierRelease,
              panel.isVisible,
              !activationModifiersArePressed(in: modifierFlags) else {
            return
        }

        activateSelectedWindow()
    }

    private func startModifierReleasePollingIfNeeded() {
        guard shouldActivateOnModifierRelease,
              !activationModifierFlags.isEmpty,
              modifierReleaseTimer == nil else {
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
              !activationModifiersArePressedInSession() else {
            return
        }

        activateSelectedWindow()
    }

    private func activationModifiersArePressed(
        in flags: NSEvent.ModifierFlags
    ) -> Bool {
        !flags
            .intersection(.deviceIndependentFlagsMask)
            .intersection(activationModifierFlags)
            .isEmpty
    }

    private func activationModifiersArePressedInSession() -> Bool {
        let sessionFlags = CGEventSource.flagsState(.combinedSessionState)
        return (activationModifierFlags.contains(.control)
                    && sessionFlags.contains(.maskControl))
            || (activationModifierFlags.contains(.option)
                    && sessionFlags.contains(.maskAlternate))
            || (activationModifierFlags.contains(.shift)
                    && sessionFlags.contains(.maskShift))
            || (activationModifierFlags.contains(.command)
                    && sessionFlags.contains(.maskCommand))
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
        guard let indexPath = indexPath(at: windowLocation) else {
            return
        }

        selectRow(indexPath.item)
        activateSelectedWindow()
    }

    private func updatePreferredNavigationColumn(at windowLocation: NSPoint) {
        guard let indexPath = indexPath(at: windowLocation) else {
            return
        }
        preferredNavigationColumn = indexPath.item % max(layoutColumnCount, 1)
    }

    private func indexPath(at windowLocation: NSPoint) -> IndexPath? {
        let collectionLocation = collectionView.convert(windowLocation, from: nil)
        return collectionView.indexPathForItem(at: collectionLocation)
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
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.panel.isVisible,
                  !self.panel.isKeyWindow else {
                return
            }
            self.hide()
        }
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
