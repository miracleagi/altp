import Foundation
import CoreGraphics

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let builtInFrame = CGRect(x: 0, y: 0, width: 1_512, height: 945)
let externalFrame = CGRect(x: 0, y: 0, width: 2_560, height: 1_440)
let builtInMetrics = QuickSwitchLayoutPolicy.metrics(forVisibleWidth: builtInFrame.width)
let externalMetrics = QuickSwitchLayoutPolicy.metrics(forVisibleWidth: externalFrame.width)
let builtInPanel = QuickSwitchLayoutPolicy.panelSize(
    windowCount: 7,
    visibleFrame: builtInFrame,
    metrics: builtInMetrics
)
let externalPanel = QuickSwitchLayoutPolicy.panelSize(
    windowCount: 7,
    visibleFrame: externalFrame,
    metrics: externalMetrics
)

expect(
    externalMetrics.itemWidth > builtInMetrics.itemWidth,
    "cards must grow horizontally on a wider external display"
)
expect(
    externalMetrics.iconSize > builtInMetrics.iconSize,
    "visual content must scale modestly on a wider external display"
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
    builtInPanel.height < builtInFrame.height && externalPanel.height < externalFrame.height,
    "the panel must fit vertically on both displays"
)

print("Quick Switch layout harness passed")
