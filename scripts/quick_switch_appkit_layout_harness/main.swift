import AppKit
import Carbon.HIToolbox

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

private func contains(_ outer: NSRect, _ inner: NSRect, tolerance: CGFloat = 0.5) -> Bool {
    inner.minX >= outer.minX - tolerance
        && inner.maxX <= outer.maxX + tolerance
        && inner.minY >= outer.minY - tolerance
        && inner.maxY <= outer.maxY + tolerance
}

private final class HarnessItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("HarnessItem")

    override func loadView() {
        view = NSView()
    }
}

private final class HarnessDataSource: NSObject, NSCollectionViewDataSource {
    var itemCount: Int

    init(itemCount: Int) {
        self.itemCount = itemCount
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        itemCount
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        collectionView.makeItem(
            withIdentifier: HarnessItem.identifier,
            for: indexPath
        )
    }
}

private final class HarnessScene {
    let panel: NSPanel
    let scrollView: NSScrollView
    let collectionView: NSCollectionView
    let flowLayout: NSCollectionViewFlowLayout
    let gridLayout: QuickSwitchGridLayout
    let viewportState: QuickSwitchViewportState
    private let dataSource: HarnessDataSource

    init(
        itemCount: Int,
        visibleFrame: NSRect,
        panelHeight: CGFloat? = nil
    ) {
        let metrics = QuickSwitchLayoutPolicy.metrics(
            forVisibleWidth: visibleFrame.width
        )
        gridLayout = QuickSwitchLayoutPolicy.gridLayout(
            windowCount: itemCount,
            visibleFrame: visibleFrame,
            metrics: metrics
        )

        let initialPanelSize = NSSize(
            width: gridLayout.panelSize.width,
            height: panelHeight ?? gridLayout.panelSize.height
        )
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: initialPanelSize),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        let effectView = NSVisualEffectView()
        panel.contentView = effectView

        flowLayout = NSCollectionViewFlowLayout()
        flowLayout.scrollDirection = .vertical
        flowLayout.itemSize = NSSize(
            width: metrics.itemWidth,
            height: metrics.itemHeight
        )
        flowLayout.minimumInteritemSpacing = metrics.itemSpacing
        flowLayout.minimumLineSpacing = metrics.itemSpacing
        flowLayout.sectionInset = NSEdgeInsets(
            top: metrics.verticalInset,
            left: metrics.horizontalInset,
            bottom: metrics.verticalInset,
            right: metrics.horizontalInset
        )

        collectionView = NSCollectionView()
        collectionView.collectionViewLayout = flowLayout
        collectionView.autoresizingMask = [.width]
        collectionView.register(
            HarnessItem.self,
            forItemWithIdentifier: HarnessItem.identifier
        )
        dataSource = HarnessDataSource(itemCount: itemCount)
        collectionView.dataSource = dataSource

        scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets()
        scrollView.scrollerInsets = NSEdgeInsets()
        scrollView.documentView = collectionView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: effectView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor)
        ])

        collectionView.reloadData()
        effectView.layoutSubtreeIfNeeded()
        viewportState = QuickSwitchCollectionViewport.synchronize(
            collectionView: collectionView,
            scrollView: scrollView,
            flowLayout: flowLayout,
            allowsVerticalScrolling: gridLayout.requiresVerticalScrolling
        )
    }

    func frameForItem(at index: Int) -> NSRect? {
        flowLayout.layoutAttributesForItem(
            at: IndexPath(item: index, section: 0)
        )?.frame
    }

    @discardableResult
    func resizePanel(
        height: CGFloat,
        allowsVerticalScrolling: Bool
    ) -> QuickSwitchViewportState {
        var frame = panel.frame
        frame.size.height = height
        panel.setFrame(frame, display: false)
        panel.contentView?.layoutSubtreeIfNeeded()
        return QuickSwitchCollectionViewport.synchronize(
            collectionView: collectionView,
            scrollView: scrollView,
            flowLayout: flowLayout,
            allowsVerticalScrolling: allowsVerticalScrolling
        )
    }

    @discardableResult
    func reload(
        itemCount: Int,
        panelSize: NSSize,
        allowsVerticalScrolling: Bool
    ) -> QuickSwitchViewportState {
        dataSource.itemCount = itemCount
        panel.setFrame(
            NSRect(origin: panel.frame.origin, size: panelSize),
            display: false
        )
        collectionView.reloadData()
        panel.contentView?.layoutSubtreeIfNeeded()
        return QuickSwitchCollectionViewport.synchronize(
            collectionView: collectionView,
            scrollView: scrollView,
            flowLayout: flowLayout,
            allowsVerticalScrolling: allowsVerticalScrolling
        )
    }
}

_ = NSApplication.shared

let customModifierShortcut = KeyboardShortcut(
    keyCode: UInt32(kVK_ANSI_K),
    modifiers: UInt32(controlKey) | UInt32(cmdKey)
)
expect(
    customModifierShortcut.eventModifierFlags == [.control, .command]
        && customModifierShortcut.activatesOnModifierRelease,
    "custom quick-switch modifiers must control release activation"
)
let modifierlessShortcut = KeyboardShortcut(
    keyCode: UInt32(kVK_F8),
    modifiers: 0
)
expect(
    modifierlessShortcut.eventModifierFlags.isEmpty
        && !modifierlessShortcut.activatesOnModifierRelease,
    "a modifierless shortcut must stay open for arrow and Return navigation"
)

let commonDisplayFrames = [
    NSRect(x: 0, y: 0, width: 1_512, height: 945),
    NSRect(x: 0, y: 0, width: 2_560, height: 1_440)
]

for visibleFrame in commonDisplayFrames {
    let scene = HarnessScene(itemCount: 22, visibleFrame: visibleFrame)
    expect(
        scene.gridLayout.rowCount == 3 && scene.gridLayout.showsAllWindows,
        "twenty-two items must be a complete three-row page"
    )
    expect(
        !scene.viewportState.hasVerticalOverflow,
        "the twenty-two-item viewport must have no vertical overflow"
    )

    guard let finalItemFrame = scene.frameForItem(at: 21) else {
        fputs("FAIL: missing layout attributes for the twenty-second item\n", stderr)
        exit(1)
    }
    expect(
        contains(scene.scrollView.contentView.documentVisibleRect, finalItemFrame),
        "the entire third row must be inside the document-visible rect"
    )

    let originBeforeSelection = scene.scrollView.contentView.bounds.origin
    QuickSwitchCollectionViewport.reveal(
        IndexPath(item: 21, section: 0),
        collectionView: scene.collectionView,
        scrollView: scene.scrollView,
        allowsVerticalScrolling: false
    )
    let originAfterSelection = scene.scrollView.contentView.bounds.origin
    expect(
        abs(originAfterSelection.x - originBeforeSelection.x) < 0.01
            && abs(originAfterSelection.y - originBeforeSelection.y) < 0.01,
        "selecting the final item must not scroll a complete page"
    )
}

let builtInFrame = NSRect(x: 0, y: 0, width: 1_512, height: 945)
let builtInMetrics = QuickSwitchLayoutPolicy.metrics(
    forVisibleWidth: builtInFrame.width
)
let builtInTwentyTwoWindowLayout = QuickSwitchLayoutPolicy.gridLayout(
    windowCount: 22,
    visibleFrame: builtInFrame,
    metrics: builtInMetrics
)
private let constrainedScene = HarnessScene(
    itemCount: 22,
    visibleFrame: builtInFrame,
    panelHeight: builtInTwentyTwoWindowLayout.panelSize.height
        - QuickSwitchLayoutPolicy.viewportSafetyHeight
        - 1
)
expect(
    constrainedScene.viewportState.hasVerticalOverflow,
    "the regression fixture must reproduce a one-point clipped third row"
)
let correctedPanelHeight = QuickSwitchLayoutPolicy.panelHeightResolvingOverflow(
    plannedHeight: builtInTwentyTwoWindowLayout.panelSize.height,
    viewportHeight: constrainedScene.viewportState.viewportSize.height,
    contentHeight: constrainedScene.viewportState.contentSize.height,
    maximumHeight: builtInFrame.height
        - QuickSwitchLayoutPolicy.panelVerticalMargin
)
let correctedViewportState = constrainedScene.resizePanel(
    height: correctedPanelHeight,
    allowsVerticalScrolling: false
)
expect(
    !correctedViewportState.hasVerticalOverflow,
    "runtime overflow correction must restore a complete three-row page"
)
guard let correctedFinalItemFrame = constrainedScene.frameForItem(at: 21) else {
    fputs("FAIL: missing corrected layout attributes for the final item\n", stderr)
    exit(1)
}
expect(
    contains(
        constrainedScene.scrollView.contentView.documentVisibleRect,
        correctedFinalItemFrame
    ),
    "runtime overflow correction must fully reveal the third row"
)

private let overflowScene = HarnessScene(
    itemCount: 55,
    visibleFrame: builtInFrame
)
expect(
    overflowScene.gridLayout.requiresVerticalScrolling
        && overflowScene.viewportState.hasVerticalOverflow,
    "an oversized grid must retain a working vertical-scroll fallback"
)
let overflowOriginBeforeSelection = overflowScene.scrollView.contentView.bounds.origin
QuickSwitchCollectionViewport.reveal(
    IndexPath(item: 54, section: 0),
    collectionView: overflowScene.collectionView,
    scrollView: overflowScene.scrollView,
    allowsVerticalScrolling: true
)
overflowScene.panel.contentView?.layoutSubtreeIfNeeded()
let overflowOriginAfterSelection = overflowScene.scrollView.contentView.bounds.origin
expect(
    overflowOriginAfterSelection.y > overflowOriginBeforeSelection.y,
    "revealing a lower row must scroll vertically"
)
guard let overflowFinalItemFrame = overflowScene.frameForItem(at: 54) else {
    fputs("FAIL: missing layout attributes for the overflow item\n", stderr)
    exit(1)
}
expect(
    contains(
        overflowScene.scrollView.contentView.documentVisibleRect,
        overflowFinalItemFrame
    ),
    "vertical scrolling must reveal the selected overflow item"
)

let restoredViewportState = overflowScene.reload(
    itemCount: 22,
    panelSize: builtInTwentyTwoWindowLayout.panelSize,
    allowsVerticalScrolling: false
)
expect(
    !restoredViewportState.hasVerticalOverflow,
    "returning from an overflow grid must restore a complete page"
)
let restoredOrigin = overflowScene.scrollView.contentView.bounds.origin
let expectedTopY: CGFloat
if overflowScene.collectionView.isFlipped {
    expectedTopY = overflowScene.collectionView.bounds.minY
} else {
    expectedTopY = max(
        overflowScene.collectionView.bounds.minY,
        overflowScene.collectionView.bounds.maxY
            - overflowScene.scrollView.contentSize.height
    )
}
expect(
    abs(restoredOrigin.y - expectedTopY) < 0.01,
    "returning from an overflow grid must reset the old scroll position"
)
guard let restoredFinalItemFrame = overflowScene.frameForItem(at: 21) else {
    fputs("FAIL: missing restored layout attributes for the final item\n", stderr)
    exit(1)
}
expect(
    contains(
        overflowScene.scrollView.contentView.documentVisibleRect,
        restoredFinalItemFrame
    ),
    "the third row must remain visible after reusing a previously scrolled view"
)

print("Quick Switch AppKit layout harness passed")
