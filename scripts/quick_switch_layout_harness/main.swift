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
    ) + QuickSwitchLayoutPolicy.viewportSafetyHeight <= compactPanel.height &&
        QuickSwitchLayoutPolicy.contentHeight(
            rowCount: builtInLayout.rowCount,
            metrics: builtInMetrics
        ) + QuickSwitchLayoutPolicy.viewportSafetyHeight <= builtInPanel.height &&
        QuickSwitchLayoutPolicy.contentHeight(
            rowCount: externalLayout.rowCount,
            metrics: externalMetrics
        ) + QuickSwitchLayoutPolicy.viewportSafetyHeight <= externalPanel.height,
    "every normal grid row must fit with viewport safety space"
)

let compactTwentyTwoWindowLayout = QuickSwitchLayoutPolicy.gridLayout(
    windowCount: 22,
    visibleFrame: compactFrame,
    metrics: compactMetrics
)
let builtInTwentyTwoWindowLayout = QuickSwitchLayoutPolicy.gridLayout(
    windowCount: 22,
    visibleFrame: builtInFrame,
    metrics: builtInMetrics
)
let externalTwentyTwoWindowLayout = QuickSwitchLayoutPolicy.gridLayout(
    windowCount: 22,
    visibleFrame: externalFrame,
    metrics: externalMetrics
)
expect(
    compactTwentyTwoWindowLayout.rowCount == 3 &&
        builtInTwentyTwoWindowLayout.rowCount == 3 &&
        externalTwentyTwoWindowLayout.rowCount == 3,
    "twenty-two windows must form three complete rows on common displays"
)
expect(
    compactTwentyTwoWindowLayout.showsAllWindows &&
        builtInTwentyTwoWindowLayout.showsAllWindows &&
        externalTwentyTwoWindowLayout.showsAllWindows,
    "twenty-two windows must remain on one page"
)
expect(
    QuickSwitchLayoutPolicy.contentHeight(
        rowCount: builtInTwentyTwoWindowLayout.rowCount,
        metrics: builtInMetrics
    ) + QuickSwitchLayoutPolicy.viewportSafetyHeight
        <= builtInTwentyTwoWindowLayout.panelSize.height,
    "the twenty-two-window grid must not rely on exact-height viewport equality"
)
let correctedTwentyTwoWindowHeight =
    QuickSwitchLayoutPolicy.panelHeightResolvingOverflow(
        plannedHeight: builtInTwentyTwoWindowLayout.panelSize.height,
        viewportHeight: builtInTwentyTwoWindowLayout.panelSize.height - 1,
        contentHeight: builtInTwentyTwoWindowLayout.panelSize.height,
        maximumHeight: builtInFrame.height
            - QuickSwitchLayoutPolicy.panelVerticalMargin
    )
expect(
    correctedTwentyTwoWindowHeight
        == builtInTwentyTwoWindowLayout.panelSize.height
            + QuickSwitchLayoutPolicy.viewportSafetyHeight
            + 1,
    "a one-point runtime overflow must expand the panel with fresh safety space"
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
    ) + QuickSwitchLayoutPolicy.viewportSafetyHeight
        <= builtInFrame.height - QuickSwitchLayoutPolicy.panelVerticalMargin &&
        QuickSwitchLayoutPolicy.contentHeight(
            rowCount: builtInOverflowLayout.visibleRowCount + 1,
            metrics: builtInMetrics
        ) + QuickSwitchLayoutPolicy.viewportSafetyHeight
            > builtInFrame.height - QuickSwitchLayoutPolicy.panelVerticalMargin,
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
    extremeLayout.panelSize.height
        <= builtInFrame.height - QuickSwitchLayoutPolicy.panelVerticalMargin,
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

let firstSelection = QuickSwitchGridNavigation.destination(
    from: nil,
    preferredColumn: nil,
    direction: .next,
    itemCount: 22,
    columnCount: 9
)
let lastSelection = QuickSwitchGridNavigation.destination(
    from: nil,
    preferredColumn: nil,
    direction: .previous,
    itemCount: 22,
    columnCount: 9
)
expect(
    firstSelection?.index == 0 && lastSelection?.index == 21,
    "an empty selection must recover without skipping the first or last item"
)
expect(
    QuickSwitchGridNavigation.destination(
        from: nil,
        preferredColumn: nil,
        direction: .next,
        itemCount: 0,
        columnCount: 9
    ) == nil,
    "an empty grid must not manufacture a selection"
)
expect(
    QuickSwitchGridNavigation.destination(
        from: 0,
        preferredColumn: nil,
        direction: .next,
        itemCount: 5,
        columnCount: 0
    ) == nil,
    "an invalid column count must not manufacture a selection"
)

let shortRowDown = QuickSwitchGridNavigation.destination(
    from: 17,
    preferredColumn: nil,
    direction: .down,
    itemCount: 22,
    columnCount: 9
)
let shortRowWrapped = QuickSwitchGridNavigation.destination(
    from: shortRowDown?.index,
    preferredColumn: shortRowDown?.preferredColumn,
    direction: .down,
    itemCount: 22,
    columnCount: 9
)
let shortRowCompleted = QuickSwitchGridNavigation.destination(
    from: shortRowWrapped?.index,
    preferredColumn: shortRowWrapped?.preferredColumn,
    direction: .down,
    itemCount: 22,
    columnCount: 9
)
expect(
    shortRowDown == QuickSwitchNavigationResult(index: 21, preferredColumn: 8)
        && shortRowWrapped == QuickSwitchNavigationResult(index: 8, preferredColumn: 8)
        && shortRowCompleted == QuickSwitchNavigationResult(index: 17, preferredColumn: 8),
    "vertical navigation must preserve its intended column across a short final row"
)
let shortRowUp = QuickSwitchGridNavigation.destination(
    from: 8,
    preferredColumn: nil,
    direction: .up,
    itemCount: 22,
    columnCount: 9
)
let shortRowUpAgain = QuickSwitchGridNavigation.destination(
    from: shortRowUp?.index,
    preferredColumn: shortRowUp?.preferredColumn,
    direction: .up,
    itemCount: 22,
    columnCount: 9
)
expect(
    shortRowUp == QuickSwitchNavigationResult(index: 21, preferredColumn: 8)
        && shortRowUpAgain == QuickSwitchNavigationResult(index: 17, preferredColumn: 8),
    "upward navigation must restore its intended column after crossing a short row"
)
expect(
    QuickSwitchGridNavigation.destination(
        from: 21,
        preferredColumn: 8,
        direction: .previous,
        itemCount: 22,
        columnCount: 9
    ) == QuickSwitchNavigationResult(index: 20, preferredColumn: 2),
    "horizontal navigation must reset the preferred column to the visible item"
)
expect(
    QuickSwitchGridNavigation.destination(
        from: 99,
        preferredColumn: 8,
        direction: .next,
        itemCount: 22,
        columnCount: 9
    ) == QuickSwitchNavigationResult(index: 0, preferredColumn: 0),
    "an invalid stale selection must recover to a valid boundary item"
)

for itemCount in 1...64 {
    for columnCount in 1...12 {
        let rowCount = Int(
            ceil(Double(itemCount) / Double(columnCount))
        )
        for index in 0..<itemCount {
            guard let next = QuickSwitchGridNavigation.destination(
                from: index,
                preferredColumn: nil,
                direction: .next,
                itemCount: itemCount,
                columnCount: columnCount
            ),
            let previous = QuickSwitchGridNavigation.destination(
                from: next.index,
                preferredColumn: next.preferredColumn,
                direction: .previous,
                itemCount: itemCount,
                columnCount: columnCount
            ) else {
                expect(false, "valid horizontal navigation must return a destination")
                continue
            }
            expect(
                previous.index == index,
                "horizontal navigation must be reversible"
            )

            var vertical = QuickSwitchNavigationResult(
                index: index,
                preferredColumn: index % columnCount
            )
            for _ in 0..<rowCount {
                guard let nextRow = QuickSwitchGridNavigation.destination(
                    from: vertical.index,
                    preferredColumn: vertical.preferredColumn,
                    direction: .down,
                    itemCount: itemCount,
                    columnCount: columnCount
                ) else {
                    expect(false, "valid vertical navigation must return a destination")
                    break
                }
                vertical = nextRow
            }
            expect(
                vertical.index == index,
                "a full vertical cycle must return to its starting item"
            )
        }
    }
}

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
