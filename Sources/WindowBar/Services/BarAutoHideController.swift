import AppKit
import QuartzCore
import WindowBarCore

final class BarAutoHideController {
    private var state = AutoHideState()
    private var content: NSView?
    private var transition = ScanGeneration()
    private(set) var shownFrame: NSRect = .zero
    private(set) var edgeFrame: NSRect = .zero
    var hidden: Bool { state.hidden }

    func layout(
        shownFrame: NSRect, screenFrame: NSRect, edge barEdge: BarPreferences.BarEdge = .bottom, panel: NSPanel,
        animated: Bool = false
    ) {
        let edge: NSRect
        switch barEdge {
        case .bottom:
            edge = NSRect(x: shownFrame.minX, y: screenFrame.minY, width: shownFrame.width, height: 4)
        case .left:
            edge = NSRect(x: screenFrame.minX, y: shownFrame.minY, width: 4, height: shownFrame.height)
        case .right:
            edge = NSRect(x: screenFrame.maxX - 4, y: shownFrame.minY, width: 4, height: shownFrame.height)
        }
        guard self.shownFrame != shownFrame || edgeFrame != edge else { return }
        if content == nil { content = panel.contentView }
        let wasShown = !state.hidden && panel.frame == self.shownFrame
        self.shownFrame = shownFrame
        edgeFrame = edge
        guard animated, wasShown, panel.isVisible, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        else {
            apply(panel, animated: false)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(shownFrame, display: true)
        }
    }

    func update(
        panel: NSPanel, enabled: Bool, delay: Double, pointer: NSPoint,
        interaction: Bool, now: TimeInterval, animated: Bool = true
    ) {
        let previous = state.hidden
        _ = state.update(
            enabled: enabled, pointerInside: panel.frame == shownFrame && shownFrame.contains(pointer),
            atEdge: edgeFrame.contains(pointer), interaction: interaction, now: now, delay: delay)
        if previous != state.hidden { apply(panel, animated: animated) }
    }

    private func apply(_ panel: NSPanel, animated: Bool) {
        transition.invalidate()
        let captured = transition.value
        let animate =
            animated && panel.isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if state.hidden {
            if animate {
                NSAnimationContext.runAnimationGroup(
                    { context in
                        context.duration = 0.18
                        panel.animator().alphaValue = 0
                    },
                    completionHandler: { [weak self, weak panel] in
                        guard let self, let panel, self.transition.accepts(captured), self.state.hidden else {
                            return
                        }
                        self.installStrip(panel)
                    })
            } else {
                installStrip(panel)
            }
        } else {
            let wasStrip = panel.frame == edgeFrame
            if animate && wasStrip { panel.alphaValue = 0 }
            // Resize before re-attaching, so the bar never lays out at strip width.
            panel.setFrame(shownFrame, display: false)
            panel.contentView = content
            content?.layoutSubtreeIfNeeded()
            panel.ignoresMouseEvents = false
            panel.hasShadow = true
            if animate {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.18
                    panel.animator().alphaValue = 1
                }
            } else {
                panel.alphaValue = 1
            }
        }
    }

    private func installStrip(_ panel: NSPanel) {
        // Stay inside this screen, including vertically stacked display arrangements.
        let strip = NSVisualEffectView(frame: NSRect(origin: .zero, size: edgeFrame.size))
        strip.material = .popover
        strip.state = .active
        strip.wantsLayer = true
        strip.layer?.cornerRadius = 2
        panel.contentView = strip
        panel.ignoresMouseEvents = true
        panel.hasShadow = false
        panel.setFrame(edgeFrame, display: false)
        panel.alphaValue = 1
    }
}
