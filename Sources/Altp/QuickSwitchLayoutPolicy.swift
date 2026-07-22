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
    static let maximumVisibleItems = 7

    static func metrics(forVisibleWidth visibleWidth: CGFloat) -> QuickSwitchLayoutMetrics {
        let widthRatio = max(visibleWidth, 1) / referenceScreenWidth
        let horizontalScale = min(max(widthRatio, 0.78), 1.43)
        let visualScale = min(
            max(CGFloat(pow(Double(widthRatio), 0.35)), 0.90),
            1.18
        )

        return QuickSwitchLayoutMetrics(
            itemWidth: (168 * horizontalScale).rounded(),
            itemHeight: (142 * visualScale).rounded(),
            itemSpacing: (6 * visualScale).rounded(),
            horizontalInset: (8 * visualScale).rounded(),
            verticalInset: (10 * visualScale).rounded(),
            iconSize: (64 * visualScale).rounded(),
            titleFontSize: 13 * visualScale,
            appFontSize: 11 * visualScale,
            cardCornerRadius: (10 * visualScale).rounded(),
            titleLineHeight: (16 * visualScale).rounded(),
            iconTopSingleLine: (20 * visualScale).rounded(),
            iconTopTwoLines: (12 * visualScale).rounded(),
            contentSideInset: max(6, (6 * visualScale).rounded())
        )
    }

    static func panelSize(
        windowCount: Int,
        visibleFrame: CGRect,
        metrics: QuickSwitchLayoutMetrics
    ) -> CGSize {
        let visibleItems = min(max(windowCount, 1), maximumVisibleItems)
        let contentWidth = CGFloat(visibleItems) * metrics.itemWidth
            + CGFloat(max(visibleItems - 1, 0)) * metrics.itemSpacing
            + metrics.horizontalInset * 2
        let maximumWidth = max(
            240,
            min(visibleFrame.width - 48, visibleFrame.width * 0.78)
        )
        let minimumWidth = min(maximumWidth, 240 * visualScale(for: metrics))
        let width = min(max(contentWidth, minimumWidth), maximumWidth)

        let contentHeight = metrics.itemHeight + metrics.verticalInset * 2
        let height = min(contentHeight, visibleFrame.height - 96)
        return CGSize(width: width, height: height)
    }

    private static func visualScale(for metrics: QuickSwitchLayoutMetrics) -> CGFloat {
        metrics.itemHeight / 142
    }
}
