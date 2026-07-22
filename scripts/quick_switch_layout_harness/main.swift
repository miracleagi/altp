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
let compactPanel = QuickSwitchLayoutPolicy.panelSize(
    windowCount: 20,
    visibleFrame: compactFrame,
    metrics: compactMetrics
)
let builtInPanel = QuickSwitchLayoutPolicy.panelSize(
    windowCount: 20,
    visibleFrame: builtInFrame,
    metrics: builtInMetrics
)
let externalPanel = QuickSwitchLayoutPolicy.panelSize(
    windowCount: 20,
    visibleFrame: externalFrame,
    metrics: externalMetrics
)
let builtInCapacity = QuickSwitchLayoutPolicy.visibleItemCapacity(
    windowCount: 20,
    visibleFrame: builtInFrame,
    metrics: builtInMetrics
)
let externalCapacity = QuickSwitchLayoutPolicy.visibleItemCapacity(
    windowCount: 20,
    visibleFrame: externalFrame,
    metrics: externalMetrics
)
let compactCapacity = QuickSwitchLayoutPolicy.visibleItemCapacity(
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
    "the layout must show more windows as display width increases"
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
    QuickSwitchLayoutPolicy.panelSize(
        windowCount: compactCapacity + 1,
        visibleFrame: compactFrame,
        metrics: compactMetrics
    ).width == compactPanel.width &&
        QuickSwitchLayoutPolicy.panelSize(
            windowCount: builtInCapacity + 1,
            visibleFrame: builtInFrame,
            metrics: builtInMetrics
        ).width == builtInPanel.width &&
        QuickSwitchLayoutPolicy.panelSize(
            windowCount: externalCapacity + 1,
            visibleFrame: externalFrame,
            metrics: externalMetrics
        ).width == externalPanel.width,
    "the next window must scroll instead of expanding the compact panel"
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
