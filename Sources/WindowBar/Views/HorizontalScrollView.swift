import AppKit

final class HorizontalScrollView: NSScrollView {
    /// A side-docked bar scrolls its flipped document from the top instead.
    var vertical = false

    override func scrollWheel(with event: NSEvent) {
        guard let documentView else { return }
        let delta =
            abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
            ? event.scrollingDeltaX : event.scrollingDeltaY
        let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 16
        if vertical {
            let maxY = max(0, documentView.frame.height - contentView.bounds.height)
            let offset = min(maxY, max(0, contentView.bounds.minY - delta * multiplier))
            contentView.scroll(to: NSPoint(x: 0, y: offset))
        } else {
            let maxX = max(0, documentView.frame.width - contentView.bounds.width)
            let offset = min(maxX, max(0, contentView.bounds.minX - delta * multiplier))
            contentView.scroll(to: NSPoint(x: offset, y: 0))
        }
        reflectScrolledClipView(contentView)
    }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
