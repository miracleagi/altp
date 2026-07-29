import Foundation
import CoreGraphics

struct QuickSwitchLayoutMetrics: Equatable {
    let itemWidth: CGFloat
    let itemHeight: CGFloat
    let itemSpacing: CGFloat
    let horizontalInset: CGFloat
    let verticalInset: CGFloat
    let iconSize: CGFloat
    let titleFontSize: CGFloat
    let appFontSize: CGFloat
    let cardCornerRadius: CGFloat
    let titleLineHeight: CGFloat
    let iconTopSingleLine: CGFloat
    let iconTopTwoLines: CGFloat
    let contentSideInset: CGFloat
}

struct QuickSwitchGridLayout: Equatable {
    let columnCount: Int
    let rowCount: Int
    let visibleRowCount: Int
    let panelSize: CGSize

    var showsAllWindows: Bool {
        visibleRowCount == rowCount
    }

    var requiresVerticalScrolling: Bool {
        !showsAllWindows
    }
}

enum QuickSwitchNavigationDirection {
    case previous
    case next
    case up
    case down
}

struct QuickSwitchNavigationResult: Equatable {
    let index: Int
    let preferredColumn: Int
}

enum QuickSwitchGridNavigation {
    static func destination(
        from currentIndex: Int?,
        preferredColumn: Int?,
        direction: QuickSwitchNavigationDirection,
        itemCount: Int,
        columnCount: Int
    ) -> QuickSwitchNavigationResult? {
        guard itemCount > 0, columnCount > 0 else {
            return nil
        }

        let safeColumnCount = columnCount
        guard let currentIndex,
              currentIndex >= 0,
              currentIndex < itemCount else {
            let initialIndex: Int
            switch direction {
            case .previous, .up:
                initialIndex = itemCount - 1
            case .next, .down:
                initialIndex = 0
            }
            return QuickSwitchNavigationResult(
                index: initialIndex,
                preferredColumn: initialIndex % safeColumnCount
            )
        }

        switch direction {
        case .previous, .next:
            let delta = direction == .next ? 1 : -1
            let index = (currentIndex + delta + itemCount) % itemCount
            return QuickSwitchNavigationResult(
                index: index,
                preferredColumn: index % safeColumnCount
            )
        case .up, .down:
            let column = min(
                max(preferredColumn ?? currentIndex % safeColumnCount, 0),
                safeColumnCount - 1
            )
            return QuickSwitchNavigationResult(
                index: verticalDestination(
                    from: currentIndex,
                    direction: direction == .down ? 1 : -1,
                    itemCount: itemCount,
                    columnCount: safeColumnCount,
                    preferredColumn: column
                ),
                preferredColumn: column
            )
        }
    }

    static func verticalDestination(
        from currentIndex: Int,
        direction: Int,
        itemCount: Int,
        columnCount: Int,
        preferredColumn: Int? = nil
    ) -> Int {
        guard itemCount > 0, columnCount > 0 else {
            return 0
        }

        let clampedIndex = min(max(currentIndex, 0), itemCount - 1)
        guard direction != 0 else {
            return clampedIndex
        }

        let rowCount = Int(
            ceil(Double(itemCount) / Double(columnCount))
        )
        let currentRow = clampedIndex / columnCount
        let currentColumn = clampedIndex % columnCount
        let targetColumn = min(
            max(preferredColumn ?? currentColumn, 0),
            columnCount - 1
        )
        let rowDelta = direction > 0 ? 1 : -1
        let targetRow = (currentRow + rowDelta + rowCount) % rowCount
        let targetRowStart = targetRow * columnCount
        let targetRowEnd = min(targetRowStart + columnCount, itemCount) - 1

        return min(targetRowStart + targetColumn, targetRowEnd)
    }
}

enum QuickSwitchLayoutPolicy {
    static let referenceScreenWidth: CGFloat = 1_728
    static let maximumVisibleItems = 10
    static let viewportSafetyHeight: CGFloat = 8
    private static let baseItemHeight: CGFloat = 124
    private static let compactPanelWidthRatio: CGFloat = 0.76
    private static let minimumItemWidth: CGFloat = 88
    static let panelVerticalMargin: CGFloat = 96

    static func metrics(forVisibleWidth visibleWidth: CGFloat) -> QuickSwitchLayoutMetrics {
        let widthRatio = max(visibleWidth, 1) / referenceScreenWidth
        let horizontalScale = min(max(widthRatio, 0.75), 1.43)
        let visualScale = min(
            max(CGFloat(pow(Double(widthRatio), 0.25)), 0.90),
            1.12
        )
        let itemSpacing = max(3, (4 * visualScale).rounded())
        let horizontalInset = max(5, (6 * visualScale).rounded())
        let targetCapacity = preferredVisibleItems(forVisibleWidth: visibleWidth)
        let targetPanelWidth = min(
            maximumPanelWidth(forVisibleWidth: visibleWidth),
            visibleWidth * compactPanelWidthRatio
        )
        let widthForTargetCapacity = (
            targetPanelWidth
                - horizontalInset * 2
                - CGFloat(targetCapacity - 1) * itemSpacing
        ) / CGFloat(targetCapacity)
        let scaledItemWidth = (140 * horizontalScale).rounded()
        let itemWidth = max(
            minimumItemWidth,
            min(scaledItemWidth, widthForTargetCapacity.rounded(.down))
        )

        return QuickSwitchLayoutMetrics(
            itemWidth: itemWidth,
            itemHeight: (baseItemHeight * visualScale).rounded(),
            itemSpacing: itemSpacing,
            horizontalInset: horizontalInset,
            verticalInset: max(7, (8 * visualScale).rounded()),
            iconSize: (52 * visualScale).rounded(),
            titleFontSize: 12 * visualScale,
            appFontSize: 10 * visualScale,
            cardCornerRadius: (8 * visualScale).rounded(),
            titleLineHeight: (15 * visualScale).rounded(),
            iconTopSingleLine: (14 * visualScale).rounded(),
            iconTopTwoLines: (7 * visualScale).rounded(),
            contentSideInset: max(5, (5 * visualScale).rounded())
        )
    }

    static func columnCapacity(
        windowCount: Int,
        visibleFrame: CGRect,
        metrics: QuickSwitchLayoutMetrics
    ) -> Int {
        guard windowCount > 0 else {
            return 1
        }

        let availableContentWidth = maximumPanelWidth(for: visibleFrame)
            - metrics.horizontalInset * 2
        let itemStride = metrics.itemWidth + metrics.itemSpacing
        let fittingItems = Int(
            ((availableContentWidth + metrics.itemSpacing) / itemStride).rounded(.down)
        )
        return min(
            max(windowCount, 1),
            preferredVisibleItems(forVisibleWidth: visibleFrame.width),
            max(fittingItems, 1)
        )
    }

    static func contentWidth(
        itemCount: Int,
        metrics: QuickSwitchLayoutMetrics
    ) -> CGFloat {
        let clampedCount = max(itemCount, 1)
        return CGFloat(clampedCount) * metrics.itemWidth
            + CGFloat(max(clampedCount - 1, 0)) * metrics.itemSpacing
            + metrics.horizontalInset * 2
    }

    static func contentHeight(
        rowCount: Int,
        metrics: QuickSwitchLayoutMetrics
    ) -> CGFloat {
        let clampedCount = max(rowCount, 1)
        return CGFloat(clampedCount) * metrics.itemHeight
            + CGFloat(max(clampedCount - 1, 0)) * metrics.itemSpacing
            + metrics.verticalInset * 2
    }

    static func panelHeightResolvingOverflow(
        plannedHeight: CGFloat,
        viewportHeight: CGFloat,
        contentHeight: CGFloat,
        maximumHeight: CGFloat
    ) -> CGFloat {
        let overflowHeight = contentHeight - viewportHeight
        guard overflowHeight > 0.5 else {
            return plannedHeight
        }

        return min(
            max(plannedHeight, maximumHeight),
            plannedHeight + ceil(overflowHeight) + viewportSafetyHeight
        )
    }

    static func gridLayout(
        windowCount: Int,
        visibleFrame: CGRect,
        metrics: QuickSwitchLayoutMetrics
    ) -> QuickSwitchGridLayout {
        let columnCount = columnCapacity(
            windowCount: windowCount,
            visibleFrame: visibleFrame,
            metrics: metrics
        )
        let clampedWindowCount = max(windowCount, 1)
        let rowCount = max(
            1,
            Int(ceil(Double(clampedWindowCount) / Double(columnCount)))
        )

        let maximumHeight = max(
            contentHeight(rowCount: 1, metrics: metrics) + viewportSafetyHeight,
            visibleFrame.height - panelVerticalMargin
        )
        let rowStride = metrics.itemHeight + metrics.itemSpacing
        let fittingRows = Int(
            (
                (
                    maximumHeight
                        - viewportSafetyHeight
                        - metrics.verticalInset * 2
                        + metrics.itemSpacing
                ) / rowStride
            ).rounded(.down)
        )
        let visibleRowCount = min(rowCount, max(fittingRows, 1))

        let requiredContentWidth = contentWidth(
            itemCount: columnCount,
            metrics: metrics
        )
        let maximumWidth = maximumPanelWidth(for: visibleFrame)
        let minimumWidth = min(maximumWidth, 220 * visualScale(for: metrics))
        let width = min(max(requiredContentWidth, minimumWidth), maximumWidth)
        let height = contentHeight(
            rowCount: visibleRowCount,
            metrics: metrics
        ) + viewportSafetyHeight

        return QuickSwitchGridLayout(
            columnCount: columnCount,
            rowCount: rowCount,
            visibleRowCount: visibleRowCount,
            panelSize: CGSize(width: width, height: height)
        )
    }

    private static func visualScale(for metrics: QuickSwitchLayoutMetrics) -> CGFloat {
        metrics.itemHeight / baseItemHeight
    }

    private static func maximumPanelWidth(for visibleFrame: CGRect) -> CGFloat {
        maximumPanelWidth(forVisibleWidth: visibleFrame.width)
    }

    private static func maximumPanelWidth(forVisibleWidth visibleWidth: CGFloat) -> CGFloat {
        max(220, min(visibleWidth - 40, visibleWidth * 0.78))
    }

    private static func preferredVisibleItems(forVisibleWidth visibleWidth: CGFloat) -> Int {
        switch visibleWidth {
        case ..<1_440:
            return 8
        case ..<2_100:
            return 9
        default:
            return maximumVisibleItems
        }
    }
}
