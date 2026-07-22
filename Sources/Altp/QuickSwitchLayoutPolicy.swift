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

enum QuickSwitchLayoutPolicy {
    static let referenceScreenWidth: CGFloat = 1_728
    static let maximumVisibleItems = 10
    private static let baseItemHeight: CGFloat = 124
    private static let compactPanelWidthRatio: CGFloat = 0.76
    private static let minimumItemWidth: CGFloat = 88

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

    static func visibleItemCapacity(
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

    static func panelSize(
        windowCount: Int,
        visibleFrame: CGRect,
        metrics: QuickSwitchLayoutMetrics
    ) -> CGSize {
        let visibleItems = visibleItemCapacity(
            windowCount: windowCount,
            visibleFrame: visibleFrame,
            metrics: metrics
        )
        let requiredContentWidth = contentWidth(itemCount: visibleItems, metrics: metrics)
        let maximumWidth = maximumPanelWidth(for: visibleFrame)
        let minimumWidth = min(maximumWidth, 220 * visualScale(for: metrics))
        let width = min(max(requiredContentWidth, minimumWidth), maximumWidth)

        let contentHeight = metrics.itemHeight + metrics.verticalInset * 2
        let height = min(contentHeight, visibleFrame.height - 96)
        return CGSize(width: width, height: height)
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
