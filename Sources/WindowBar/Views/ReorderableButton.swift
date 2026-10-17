import AppKit
import QuartzCore
import WindowBarCore

class ReorderableButton: NSButton, NSDraggingSource {
    enum Kind: String { case window, launcher }
    private(set) var unreadBadge: UnreadBadge?
    private var attentionPulsing = false
    func updateAttention(
        _ badge: UnreadBadge?, pulsing: Bool,
        reduceMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    ) {
        unreadBadge = badge
        if let badge {
            switch badge {
            case .dot: setAccessibilityValue("Unread activity")
            case .alert: setAccessibilityValue("Alert waiting for input")
            case .count: setAccessibilityValue(badge.label + " unread")
            }
        } else {
            setAccessibilityValue(nil)
        }
        let animate = badge != nil && pulsing && !reduceMotion
        if animate != attentionPulsing {
            attentionPulsing = animate
            wantsLayer = true
            layer?.removeAnimation(forKey: "unreadPulse")
            if animate {
                let animation = CABasicAnimation(keyPath: "backgroundColor")
                animation.fromValue = NSColor.controlAccentColor.withAlphaComponent(0.05).cgColor
                animation.toValue = NSColor.controlAccentColor.withAlphaComponent(0.3).cgColor
                animation.duration = 0.5
                animation.autoreverses = true
                animation.repeatCount = 3
                layer?.cornerRadius = 10
                layer?.add(animation, forKey: "unreadPulse")
            }
        }
        needsDisplay = true
    }
    func drawUnreadBadge() {
        guard let unreadBadge else { return }
        let width: CGFloat = unreadBadge.label.count > 2 ? 24 : 16
        let rect = NSRect(
            x: max(0, bounds.maxX - width - 1), y: isFlipped ? 1 : bounds.maxY - 15, width: width, height: 14)
        NSColor.systemRed.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        NSAttributedString(
            string: unreadBadge.label,
            attributes: [
                .font: NSFont.systemFont(ofSize: 9, weight: .bold),
                .foregroundColor: NSColor.white, .paragraphStyle: paragraph,
            ]
        ).draw(in: rect)
    }

    var dragIdentifier = ""
    var kind: Kind = .window
    var reordersVertically = false
    var onReorder: ((String, String, Bool) -> Void)?
    var onDragStart: (() -> Void)?
    private var dropHighlight = false
    private var type: NSPasteboard.PasteboardType {
        NSPasteboard.PasteboardType("local.windowbar.\(kind.rawValue)")
    }

    func configureReordering(id: String, kind: Kind) {
        dragIdentifier = id
        self.kind = kind
        registerForDraggedTypes([type])
    }

    override func mouseDown(with event: NSEvent) {
        let start = convert(event.locationInWindow, from: nil)
        guard isEnabled else { return }
        highlight(true)
        defer { highlight(false) }
        while let next = window?.nextEvent(
            matching: [.leftMouseDragged, .leftMouseUp], until: .distantFuture, inMode: .eventTracking,
            dequeue: true)
        {
            let point = convert(next.locationInWindow, from: nil)
            if next.type == .leftMouseUp {
                if bounds.contains(point) { performClick(nil) }
                return
            }
            if hypot(point.x - start.x, point.y - start.y) > 5 {
                onDragStart?()
                let item = NSPasteboardItem()
                item.setString(dragIdentifier, forType: type)
                let dragging = NSDraggingItem(pasteboardWriter: item)
                let image = NSImage(size: bounds.size)
                if let bitmap = bitmapImageRepForCachingDisplay(in: bounds) {
                    cacheDisplay(in: bounds, to: bitmap)
                    image.addRepresentation(bitmap)
                }
                dragging.setDraggingFrame(bounds, contents: image)
                beginDraggingSession(with: [dragging], event: next, source: self)
                return
            }
        }
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext)
        -> NSDragOperation
    {
        context == .withinApplication ? .move : []
    }

    private func accepts(_ sender: NSDraggingInfo) -> Bool {
        guard let source = sender.draggingSource as? ReorderableButton,
            source.kind == kind, source.dragIdentifier != dragIdentifier,
            sender.draggingPasteboard.string(forType: type) == source.dragIdentifier
        else { return false }
        return true
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropHighlight = accepts(sender)
        needsDisplay = true
        return dropHighlight ? .move : []
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { draggingEntered(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) {
        dropHighlight = false
        needsDisplay = true
    }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { accepts(sender) }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer {
            dropHighlight = false
            needsDisplay = true
        }
        guard accepts(sender), let id = sender.draggingPasteboard.string(forType: type) else { return false }
        let point = convert(sender.draggingLocation, from: nil)
        let after =
            reordersVertically
            ? (isFlipped ? point.y > bounds.midY : point.y < bounds.midY) : point.x > bounds.midX
        onReorder?(id, dragIdentifier, after)
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawDropHighlight()
        drawUnreadBadge()
    }

    func drawDropHighlight() {
        guard dropHighlight else { return }
        NSColor.controlAccentColor.setStroke()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 9, yRadius: 9)
        path.lineWidth = 2
        path.stroke()
    }
}
