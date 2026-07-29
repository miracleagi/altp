import AppKit

struct QuickSwitchViewportState: Equatable {
    let viewportSize: CGSize
    let contentSize: CGSize

    var hasVerticalOverflow: Bool {
        contentSize.height > viewportSize.height + 0.5
    }
}

enum QuickSwitchCollectionViewport {
    @discardableResult
    static func synchronize(
        collectionView: NSCollectionView,
        scrollView: NSScrollView,
        flowLayout: NSCollectionViewFlowLayout,
        allowsVerticalScrolling: Bool
    ) -> QuickSwitchViewportState {
        scrollView.layoutSubtreeIfNeeded()

        let viewportSize = scrollView.contentSize
        guard viewportSize.width > 0, viewportSize.height > 0 else {
            return QuickSwitchViewportState(
                viewportSize: viewportSize,
                contentSize: .zero
            )
        }

        collectionView.setFrameSize(viewportSize)
        flowLayout.invalidateLayout()
        collectionView.layoutSubtreeIfNeeded()

        var contentSize = flowLayout.collectionViewContentSize
        let documentSize = NSSize(
            width: viewportSize.width,
            height: max(viewportSize.height, ceil(contentSize.height))
        )

        if collectionView.frame.size != documentSize {
            collectionView.setFrameSize(documentSize)
            flowLayout.invalidateLayout()
            collectionView.layoutSubtreeIfNeeded()
            contentSize = flowLayout.collectionViewContentSize
        }

        if !allowsVerticalScrolling {
            resetScrollPosition(collectionView: collectionView, scrollView: scrollView)
        } else {
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        return QuickSwitchViewportState(
            viewportSize: viewportSize,
            contentSize: contentSize
        )
    }

    static func reveal(
        _ indexPath: IndexPath,
        collectionView: NSCollectionView,
        scrollView: NSScrollView,
        allowsVerticalScrolling: Bool
    ) {
        guard allowsVerticalScrolling else {
            resetScrollPosition(collectionView: collectionView, scrollView: scrollView)
            return
        }

        collectionView.scrollToItems(
            at: [indexPath],
            scrollPosition: .nearestHorizontalEdge
        )
    }

    private static func resetScrollPosition(
        collectionView: NSCollectionView,
        scrollView: NSScrollView
    ) {
        let originY: CGFloat
        if collectionView.isFlipped {
            originY = collectionView.bounds.minY
        } else {
            originY = max(
                collectionView.bounds.minY,
                collectionView.bounds.maxY - scrollView.contentSize.height
            )
        }

        scrollView.contentView.scroll(
            to: NSPoint(x: collectionView.bounds.minX, y: originY)
        )
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}
