import AppKit
import CoreGraphics

private enum QuickSwitchLayout {
    static let itemWidth: CGFloat = 168
    static let itemHeight: CGFloat = 142
    static let itemSpacing: CGFloat = 6
    static let horizontalInset: CGFloat = 8
    static let verticalInset: CGFloat = 10
    static let maximumVisibleItems = 7
}

final class QuickSwitchPanelController: NSObject {
    private let catalog: WindowCatalog
    private let panel: QuickSwitchPanel
    private let collectionView = NSCollectionView()
    private let scrollView = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: "No windows")
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var modifierReleaseTimer: Timer?
    private var windows: [WindowItem] = []
    private var sourceWindow: WindowItem?
    private var shouldActivateOnModifierRelease = false
    private var isActivatingSelection = false

    init(catalog: WindowCatalog) {
        self.catalog = catalog
        self.panel = QuickSwitchPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1_260, height: 162),
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
        shouldActivateOnModifierRelease = activateOnModifierRelease
        windows = WindowRanking.sortedForEmptyQuery(allWindows, sourceWindow: sourceWindow)
        collectionView.selectionIndexPaths = []
        collectionView.reloadData()
        emptyLabel.isHidden = !windows.isEmpty

        guard !windows.isEmpty else {
            NSSound.beep()
            return
        }

        positionPanel()
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
        effectView.layer?.cornerRadius = 14
        effectView.layer?.masksToBounds = true
        panel.contentView = effectView

        let layout = NSCollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = NSSize(
            width: QuickSwitchLayout.itemWidth,
            height: QuickSwitchLayout.itemHeight
        )
        layout.minimumInteritemSpacing = QuickSwitchLayout.itemSpacing
        layout.minimumLineSpacing = QuickSwitchLayout.itemSpacing
        layout.sectionInset = NSEdgeInsets(
            top: QuickSwitchLayout.verticalInset,
            left: QuickSwitchLayout.horizontalInset,
            bottom: QuickSwitchLayout.verticalInset,
            right: QuickSwitchLayout.horizontalInset
        )

        collectionView.collectionViewLayout = layout
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
        scrollView.horizontalScrollElasticity = .automatic
        scrollView.verticalScrollElasticity = .none
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
                self.moveSelection(delta: 1)
                return nil
            case 126:
                self.moveSelection(delta: -1)
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

    private func positionPanel() {
        let targetScreen = screenContainingMouse() ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen = targetScreen else {
            return
        }

        let visibleFrame = screen.visibleFrame
        let visibleItems = min(max(windows.count, 1), QuickSwitchLayout.maximumVisibleItems)
        let contentWidth = CGFloat(visibleItems) * QuickSwitchLayout.itemWidth
            + CGFloat(max(visibleItems - 1, 0)) * QuickSwitchLayout.itemSpacing
            + QuickSwitchLayout.horizontalInset * 2
        let width = min(max(contentWidth, 240), visibleFrame.width - 48)
        let contentHeight = QuickSwitchLayout.itemHeight + QuickSwitchLayout.verticalInset * 2
        let height = min(contentHeight, visibleFrame.height - 96)
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

        guard let layout = collectionView.collectionViewLayout,
              let attributes = collectionView.layoutAttributesForItem(at: indexPath) else {
            collectionView.scrollToItems(at: [indexPath], scrollPosition: .nearestHorizontalEdge)
            return
        }

        let clipView = scrollView.contentView
        let visibleRect = clipView.documentVisibleRect
        let itemFrame = attributes.frame
        let horizontalPadding: CGFloat = 12
        var targetX = visibleRect.origin.x

        if itemFrame.minX < visibleRect.minX + horizontalPadding {
            targetX = itemFrame.minX - horizontalPadding
        } else if itemFrame.maxX > visibleRect.maxX - horizontalPadding {
            targetX = itemFrame.maxX - visibleRect.width + horizontalPadding
        }

        let maximumX = max(0, layout.collectionViewContentSize.width - visibleRect.width)
        targetX = min(max(0, targetX), maximumX)

        guard abs(targetX - visibleRect.origin.x) > 0.5 else {
            return
        }

        clipView.scroll(to: NSPoint(x: targetX, y: visibleRect.origin.y))
        scrollView.reflectScrolledClipView(clipView)
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
        let result = catalog.activate(item)

        if result == .success {
            WindowSelectionMemory.shared.recordSelection(item, query: "", from: source)
        } else {
            NSLog("Altp quick switch activation failed with AXError \(result.rawValue)")
            NSSound.beep()
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

        windowItem.configure(with: windows[indexPath.item])
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
    private var titleHeightConstraint: NSLayoutConstraint?

    override var isSelected: Bool {
        didSet {
            updateSelectionAppearance()
        }
    }

    override func loadView() {
        view = NSView()
        buildInterface()
    }

    func configure(with item: WindowItem) {
        iconView.image = item.icon
        titleLabel.stringValue = item.displayTitle
        titleLabel.toolTip = item.displayTitle
        appLabel.stringValue = item.appName
        updateTitleLayout(for: item.displayTitle)
        updateSelectionAppearance()
    }

    private func buildInterface() {
        view.wantsLayer = true
        view.layer?.cornerRadius = 10

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(iconView)

        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.maximumNumberOfLines = 2
        titleLabel.cell?.wraps = true
        titleLabel.cell?.usesSingleLineMode = false
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        appLabel.font = .systemFont(ofSize: 11)
        appLabel.textColor = .secondaryLabelColor
        appLabel.lineBreakMode = .byTruncatingTail
        appLabel.maximumNumberOfLines = 1
        appLabel.alignment = .center
        appLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(appLabel)

        let iconTopConstraint = iconView.topAnchor.constraint(equalTo: view.topAnchor, constant: 20)
        let titleHeightConstraint = titleLabel.heightAnchor.constraint(equalToConstant: 16)
        self.iconTopConstraint = iconTopConstraint
        self.titleHeightConstraint = titleHeightConstraint

        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            iconTopConstraint,
            iconView.widthAnchor.constraint(equalToConstant: 64),
            iconView.heightAnchor.constraint(equalToConstant: 64),

            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),
            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 6),
            titleHeightConstraint,

            appLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            appLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            appLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            appLabel.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -8)
        ])
    }

    private func updateTitleLayout(for title: String) {
        let availableWidth = QuickSwitchLayout.itemWidth - 12
        let measuredWidth = (title as NSString).size(
            withAttributes: [.font: titleLabel.font as Any]
        ).width
        let usesTwoLines = measuredWidth > availableWidth

        titleHeightConstraint?.constant = usesTwoLines ? 32 : 16
        iconTopConstraint?.constant = usesTwoLines ? 12 : 20
    }

    private func updateSelectionAppearance() {
        view.layer?.backgroundColor = isSelected
            ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.32).cgColor
            : NSColor.clear.cgColor
        view.layer?.borderWidth = isSelected ? 1 : 0
        view.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
    }
}
