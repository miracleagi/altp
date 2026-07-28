import Foundation
import CoreGraphics

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let compactFrame = CGRect(x: 0, y: 0, width: 1_280, height: 800)
let builtInFrame = CGRect(x: 0, y: 0, width: 1_512, height: 945)
let externalFrame = CGRect(x: 0, y: 0, width: 2_560, height: 1_440)
let compactMetrics = QuickSwitchLayoutPolicy.metrics(forVisibleWidth: compactFrame.width)
let builtInMetrics = QuickSwitchLayoutPolicy.metrics(forVisibleWidth: builtInFrame.width)
let externalMetrics = QuickSwitchLayoutPolicy.metrics(forVisibleWidth: externalFrame.width)
let compactLayout = QuickSwitchLayoutPolicy.gridLayout(
    windowCount: 20,
    visibleFrame: compactFrame,
    metrics: compactMetrics
)
let builtInLayout = QuickSwitchLayoutPolicy.gridLayout(
    windowCount: 20,
    visibleFrame: builtInFrame,
    metrics: builtInMetrics
)
let externalLayout = QuickSwitchLayoutPolicy.gridLayout(
    windowCount: 20,
    visibleFrame: externalFrame,
    metrics: externalMetrics
)
let compactPanel = compactLayout.panelSize
let builtInPanel = builtInLayout.panelSize
let externalPanel = externalLayout.panelSize
let builtInCapacity = QuickSwitchLayoutPolicy.columnCapacity(
    windowCount: 20,
    visibleFrame: builtInFrame,
    metrics: builtInMetrics
)
let externalCapacity = QuickSwitchLayoutPolicy.columnCapacity(
    windowCount: 20,
    visibleFrame: externalFrame,
    metrics: externalMetrics
)
let compactCapacity = QuickSwitchLayoutPolicy.columnCapacity(
    windowCount: 20,
    visibleFrame: compactFrame,
    metrics: compactMetrics
)

expect(
    externalMetrics.itemWidth > builtInMetrics.itemWidth,
    "cards must grow horizontally on a wider external display"
)
expect(
    externalMetrics.iconSize > builtInMetrics.iconSize,
    "visual content must scale modestly on a wider external display"
)
expect(
    compactCapacity == 8 && builtInCapacity == 9 && externalCapacity == 10,
    "the layout must use more columns as display width increases"
)
expect(
    QuickSwitchLayoutPolicy.contentWidth(itemCount: compactCapacity, metrics: compactMetrics)
        <= compactPanel.width &&
        QuickSwitchLayoutPolicy.contentWidth(itemCount: builtInCapacity, metrics: builtInMetrics)
        <= builtInPanel.width &&
        QuickSwitchLayoutPolicy.contentWidth(itemCount: externalCapacity, metrics: externalMetrics)
        <= externalPanel.width,
    "all advertised visible cards must fit without clipping"
)
expect(
    QuickSwitchLayoutPolicy.gridLayout(
        windowCount: compactCapacity + 1,
        visibleFrame: compactFrame,
        metrics: compactMetrics
    ).panelSize.width == compactPanel.width &&
        QuickSwitchLayoutPolicy.gridLayout(
            windowCount: builtInCapacity + 1,
            visibleFrame: builtInFrame,
            metrics: builtInMetrics
        ).panelSize.width == builtInPanel.width &&
        QuickSwitchLayoutPolicy.gridLayout(
            windowCount: externalCapacity + 1,
            visibleFrame: externalFrame,
            metrics: externalMetrics
        ).panelSize.width == externalPanel.width,
    "the next window must wrap instead of expanding the compact panel"
)
expect(
    compactLayout.rowCount == 3 &&
        builtInLayout.rowCount == 3 &&
        externalLayout.rowCount == 2,
    "twenty windows must wrap into the expected number of rows"
)
expect(
    compactLayout.showsAllWindows &&
        builtInLayout.showsAllWindows &&
        externalLayout.showsAllWindows,
    "normal window counts must be fully visible without scrolling"
)
expect(
    QuickSwitchLayoutPolicy.contentHeight(
        rowCount: compactLayout.rowCount,
        metrics: compactMetrics
    ) <= compactPanel.height &&
        QuickSwitchLayoutPolicy.contentHeight(
            rowCount: builtInLayout.rowCount,
            metrics: builtInMetrics
        ) <= builtInPanel.height &&
        QuickSwitchLayoutPolicy.contentHeight(
            rowCount: externalLayout.rowCount,
            metrics: externalMetrics
        ) <= externalPanel.height,
    "every normal grid row must fit inside the panel"
)

let builtInWidthRatio = builtInPanel.width / builtInFrame.width
let externalWidthRatio = externalPanel.width / externalFrame.width
expect(
    abs(builtInWidthRatio - externalWidthRatio) < 0.08,
    "panel width ratios must stay visually consistent across displays"
)
expect(
    builtInWidthRatio <= 0.78 && externalWidthRatio <= 0.78,
    "the panel must preserve screen-edge breathing room"
)
expect(
    compactPanel.height < compactFrame.height &&
        builtInPanel.height < builtInFrame.height &&
        externalPanel.height < externalFrame.height,
    "the panel must fit vertically on both displays"
)
expect(
    builtInMetrics.itemWidth < 140 && builtInMetrics.itemHeight < 124,
    "the built-in display must use compact cards"
)

let compactFortyWindowLayout = QuickSwitchLayoutPolicy.gridLayout(
    windowCount: 40,
    visibleFrame: compactFrame,
    metrics: compactMetrics
)
expect(
    compactFortyWindowLayout.showsAllWindows,
    "a compact display must show forty windows at once"
)

let compactOverflowLayout = QuickSwitchLayoutPolicy.gridLayout(
    windowCount: 41,
    visibleFrame: compactFrame,
    metrics: compactMetrics
)
let builtInMaximumLayout = QuickSwitchLayoutPolicy.gridLayout(
    windowCount: 54,
    visibleFrame: builtInFrame,
    metrics: builtInMetrics
)
let builtInOverflowLayout = QuickSwitchLayoutPolicy.gridLayout(
    windowCount: 55,
    visibleFrame: builtInFrame,
    metrics: builtInMetrics
)
let externalMaximumLayout = QuickSwitchLayoutPolicy.gridLayout(
    windowCount: 90,
    visibleFrame: externalFrame,
    metrics: externalMetrics
)
let externalOverflowLayout = QuickSwitchLayoutPolicy.gridLayout(
    windowCount: 91,
    visibleFrame: externalFrame,
    metrics: externalMetrics
)
expect(
    compactOverflowLayout.requiresVerticalScrolling &&
        builtInMaximumLayout.showsAllWindows &&
        builtInOverflowLayout.requiresVerticalScrolling &&
        externalMaximumLayout.showsAllWindows &&
        externalOverflowLayout.requiresVerticalScrolling,
    "each display class must scroll only after its full-grid capacity is exceeded"
)
expect(
    QuickSwitchLayoutPolicy.contentHeight(
        rowCount: builtInOverflowLayout.visibleRowCount,
        metrics: builtInMetrics
    ) <= builtInFrame.height - 96 &&
        QuickSwitchLayoutPolicy.contentHeight(
            rowCount: builtInOverflowLayout.visibleRowCount + 1,
            metrics: builtInMetrics
        ) > builtInFrame.height - 96,
    "overflow must use every complete row that fits without clipping another row"
)

let extremeLayout = QuickSwitchLayoutPolicy.gridLayout(
    windowCount: 200,
    visibleFrame: builtInFrame,
    metrics: builtInMetrics
)
expect(
    extremeLayout.requiresVerticalScrolling &&
        extremeLayout.visibleRowCount < extremeLayout.rowCount,
    "only extreme window counts may fall back to vertical scrolling"
)
expect(
    extremeLayout.panelSize.height <= builtInFrame.height - 96,
    "a scrolling grid must preserve vertical screen margins"
)

expect(
    QuickSwitchGridNavigation.verticalDestination(
        from: 17,
        direction: 1,
        itemCount: 20,
        columnCount: 9
    ) == 19,
    "moving down into a short final row must stay as close as possible to the same column"
)
expect(
    QuickSwitchGridNavigation.verticalDestination(
        from: 19,
        direction: 1,
        itemCount: 20,
        columnCount: 9
    ) == 1,
    "moving down from the final row must wrap to the first row in the same column"
)
expect(
    QuickSwitchGridNavigation.verticalDestination(
        from: 8,
        direction: -1,
        itemCount: 20,
        columnCount: 9
    ) == 19,
    "moving up into a short final row must choose its nearest available item"
)
expect(
    compactMetrics.iconTopTwoLines
        + compactMetrics.iconSize
        + compactMetrics.contentSideInset
        + compactMetrics.titleLineHeight * 2
        + compactMetrics.appFontSize * 1.4
        + compactMetrics.verticalInset
        <= compactMetrics.itemHeight,
    "two-line titles must leave space for the application name"
)

print("Quick Switch layout harness passed")
