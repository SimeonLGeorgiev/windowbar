import AppKit
import QuartzCore
import WindowBarCore

/// A collapsed side bar shows only icons; this slides the full row text out beside the hovered button.
final class RowSummaryController {
    private var panel: TaskbarPanel?
    private let title = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(labelWithString: "")
    private(set) var shownEntryID: String?

    func show(_ entry: WindowEntry, beside button: NSView) {
        guard let host = button.window, let screen = host.screen?.visibleFrame else { return }
        let panel = self.panel ?? makePanel()
        title.stringValue = entry.title.isEmpty ? entry.appName : entry.title
        subtitle.stringValue =
            (entry.profile.map { "\(entry.appName) · \($0.name)" } ?? entry.appName)
            + (entry.minimized ? " · Minimized" : "")
        subtitle.textColor = entry.focused ? accent : .secondaryLabelColor
        let textWidth = max(title.intrinsicContentSize.width, subtitle.intrinsicContentSize.width)
        let width = min(360, max(120, ceil(textWidth) + 28))
        let height: CGFloat = 48
        title.frame = NSRect(x: 14, y: 24, width: width - 28, height: 17)
        subtitle.frame = NSRect(x: 14, y: 8, width: width - 28, height: 15)
        let row = host.convertToScreen(button.convert(button.bounds, to: nil))
        let onLeft = host.frame.midX < screen.midX
        let originX = onLeft ? host.frame.maxX + 6 : host.frame.minX - width - 6
        let originY = max(screen.minY + 4, min(row.midY - height / 2, screen.maxY - height - 4))
        let target = NSRect(x: originX, y: originY, width: width, height: height)
        let alreadyShown = shownEntryID != nil && panel.isVisible
        shownEntryID = entry.id
        if alreadyShown || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.setFrame(target, display: true)
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            return
        }
        panel.setFrame(target.offsetBy(dx: onLeft ? -10 : 10, dy: 0), display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 1
        }
    }

    func hide(_ id: String? = nil) {
        guard id == nil || id == shownEntryID else { return }
        shownEntryID = nil
        panel?.orderOut(nil)
    }

    private func makePanel() -> TaskbarPanel {
        let panel = TaskbarPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        let content = NSVisualEffectView()
        content.material = .popover
        content.state = .active
        content.wantsLayer = true
        content.layer?.cornerRadius = 10
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        title.lineBreakMode = .byTruncatingTail
        subtitle.font = .systemFont(ofSize: 10)
        subtitle.lineBreakMode = .byTruncatingTail
        content.addSubview(title)
        content.addSubview(subtitle)
        panel.contentView = content
        self.panel = panel
        return panel
    }
}
