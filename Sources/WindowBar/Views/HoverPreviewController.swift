import AppKit
import WindowBarCore

final class HoverPreviewController: NSObject {
    private let provider: WindowPreviewProviding
    private let showWindows: Bool
    private var generation = ScanGeneration()
    private var pending: DispatchWorkItem?
    private var panel: TaskbarPanel?
    private(set) var shownEntryID: String?
    private var hoveredEntryID: String?
    private var actionsEnabled = false
    private var pointerTimer: Timer?
    private var outsideSince: TimeInterval?
    private var sourceFrame = NSRect.zero
    private(set) var actionButtons: [String: NSButton] = [:]
    var onSelect: ((WindowEntry) -> Void)?
    var onMinimize: ((WindowEntry) -> Void)?
    var onClose: ((WindowEntry) -> Void)?
    var onShow: (() -> Void)?
    var previewContent: NSView? { panel?.contentView }
    var interactionFrame: NSRect? {
        guard shownEntryID != nil, let panel else { return nil }
        return sourceFrame.union(panel.frame)
    }
    private var shownEntry: WindowEntry?

    init(provider: WindowPreviewProviding = WindowPreviews(), showWindows: Bool = true) {
        self.provider = provider
        self.showWindows = showWindows
        super.init()
    }

    func hover(
        _ entry: WindowEntry, button: WindowButton, entered: Bool, mode: BarPreferences.PreviewMode,
        actionsEnabled: Bool = false
    ) {
        if !entered {
            if shownEntryID == nil { hide() }
            return
        }
        hide()
        guard !entry.focused else { return }
        self.actionsEnabled = actionsEnabled
        hoveredEntryID = entry.id
        let captured = generation.value
        let task = DispatchWorkItem { [weak self, weak button] in
            guard let self, let button, self.generation.accepts(captured) else { return }
            self.show(entry, above: button, image: nil, unavailable: false)
            if mode == .thumbnails {
                self.provider.preview(entry) { [weak self, weak button] result in
                    guard let self, let button, self.generation.accepts(captured) else { return }
                    switch result {
                    case .image(let image): self.show(entry, above: button, image: image, unavailable: false)
                    case .unavailable: self.show(entry, above: button, image: nil, unavailable: true)
                    }
                }
            }
        }
        pending = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: task)
    }

    func hide() {
        generation.invalidate()
        pending?.cancel()
        pending = nil
        pointerTimer?.invalidate()
        pointerTimer = nil
        outsideSince = nil
        shownEntry = nil
        actionButtons = [:]
        panel?.orderOut(nil)
        shownEntryID = nil
        hoveredEntryID = nil
    }

    func retainOnly(_ ids: Set<String>) {
        if let hoveredEntryID, !ids.contains(hoveredEntryID) { hide() }
    }

    private func show(_ entry: WindowEntry, above button: WindowButton, image: NSImage?, unavailable: Bool) {
        onShow?()
        let actionHeight: CGFloat = actionsEnabled ? 36 : 0
        let height: CGFloat = (image == nil ? (unavailable ? 104 : 80) : 230) + actionHeight
        let width: CGFloat = 280
        if panel == nil {
            let window = TaskbarPanel(
                contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
                defer: false)
            window.isReleasedWhenClosed = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .floating
            window.hasShadow = true
            window.hidesOnDeactivate = false
            window.ignoresMouseEvents = !actionsEnabled
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel = window
        }
        panel?.ignoresMouseEvents = !actionsEnabled
        let content = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        content.material = .popover
        content.state = .active
        content.wantsLayer = true
        content.layer?.cornerRadius = 12
        let title = NSTextField(wrappingLabelWithString: entry.title)
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        title.frame = NSRect(x: 12, y: height - 48, width: width - 24, height: 36)
        content.addSubview(title)
        let subtitle = NSTextField(
            labelWithString: entry.appName + (entry.profile.map { " · \($0.name)" } ?? "")
                + (entry.minimized ? " · Minimized" : ""))
        subtitle.font = .systemFont(ofSize: 10)
        subtitle.textColor = .secondaryLabelColor
        subtitle.frame = NSRect(x: 12, y: height - 67, width: width - 24, height: 16)
        content.addSubview(subtitle)
        if let image {
            let thumbnail = NSImageView(
                frame: NSRect(
                    x: 10, y: 10 + actionHeight, width: width - 20, height: height - 84 - actionHeight))
            thumbnail.image = image
            thumbnail.imageScaling = .scaleProportionallyUpOrDown
            content.addSubview(thumbnail)
        } else if unavailable {
            let label = NSTextField(labelWithString: "Thumbnail unavailable · see Preview settings")
            label.font = .systemFont(ofSize: 10)
            label.textColor = .secondaryLabelColor
            label.frame = NSRect(x: 12, y: 12 + actionHeight, width: width - 24, height: 16)
            content.addSubview(label)
        }
        shownEntry = entry
        actionButtons = [:]
        if actionsEnabled {
            for (index, specification) in [
                ("select", "Switch", #selector(selectWindow)),
                ("minimize", entry.minimized ? "Restore" : "Minimize", #selector(minimizeWindow)),
                ("close", "Close", #selector(closeWindow)),
            ].enumerated() {
                let button = HoverActionButton(title: specification.1)
                let captured = generation.value
                button.onClick = { [weak self] in
                    guard let self, self.generation.accepts(captured), self.shownEntryID == entry.id else {
                        return
                    }
                    self.perform(specification.2)
                }
                button.bezelStyle = .rounded
                button.frame = NSRect(x: 10 + CGFloat(index) * 88, y: 7, width: 84, height: 26)
                button.setAccessibilityLabel(
                    specification.1 + " " + entry.appName + " window: " + entry.title)
                content.addSubview(button)
                actionButtons[specification.0] = button
            }
        }
        panel?.contentView = content
        if let host = button.window {
            let rect = host.convertToScreen(button.convert(button.bounds, to: nil))
            sourceFrame = rect
            let screen = host.screen?.visibleFrame ?? rect.insetBy(dx: -width, dy: -height)
            var x = max(screen.minX + 8, min(rect.midX - width / 2, screen.maxX - width - 8))
            var y = min(rect.maxY + 12, screen.maxY - height - 8)
            // A side-docked bar is taller than wide; open the card beside it instead of above.
            if host.frame.height > host.frame.width {
                x = host.frame.midX < screen.midX ? host.frame.maxX + 8 : host.frame.minX - width - 8
                y = max(screen.minY + 8, min(rect.midY - height / 2, screen.maxY - height - 8))
            }
            panel?.setFrame(NSRect(x: x, y: y, width: width, height: height), display: false)
        }
        shownEntryID = entry.id
        if showWindows {
            panel?.orderFrontRegardless()
            if pointerTimer == nil {
                pointerTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                    self?.updatePointer(
                        NSEvent.mouseLocation, now: ProcessInfo.processInfo.systemUptime,
                        mousePressed: NSEvent.pressedMouseButtons != 0)
                }
            }
        }
    }
    func updatePointer(_ point: NSPoint, now: TimeInterval, mousePressed: Bool = false) {
        guard let panel, shownEntryID != nil else { return }
        // Keep the short path between the originating button and the card interactive.
        let besideSource = panel.frame.minY < sourceFrame.maxY
        let bridge =
            besideSource
            ? NSRect(
                x: min(sourceFrame.maxX, panel.frame.maxX), y: max(sourceFrame.minY, panel.frame.minY),
                width: max(0, max(panel.frame.minX, sourceFrame.minX) - min(sourceFrame.maxX, panel.frame.maxX)),
                height: max(0, min(sourceFrame.maxY, panel.frame.maxY) - max(sourceFrame.minY, panel.frame.minY)))
            : NSRect(
                x: max(sourceFrame.minX, panel.frame.minX), y: sourceFrame.maxY,
                width: max(0, min(sourceFrame.maxX, panel.frame.maxX) - max(sourceFrame.minX, panel.frame.minX)),
                height: max(0, panel.frame.minY - sourceFrame.maxY))
        if sourceFrame.contains(point) || panel.frame.contains(point) || bridge.contains(point)
            || mousePressed
        {
            outsideSince = nil
        } else {
            let started = outsideSince ?? now
            outsideSince = started
            if now - started >= 0.2 { hide() }
        }
    }
    private func perform(_ selector: Selector) {
        switch selector {
        case #selector(selectWindow): selectWindow()
        case #selector(minimizeWindow): minimizeWindow()
        case #selector(closeWindow): closeWindow()
        default: break
        }
    }
    @objc private func selectWindow() {
        guard let entry = shownEntry else { return }
        hide()
        onSelect?(entry)
    }
    @objc private func minimizeWindow() {
        guard let entry = shownEntry else { return }
        hide()
        if entry.minimized { onSelect?(entry) } else { onMinimize?(entry) }
    }
    @objc private func closeWindow() {
        guard let entry = shownEntry else { return }
        hide()
        onClose?(entry)
    }
}

private final class HoverActionButton: NSButton {
    var onClick: (() -> Void)?
    init(title: String) {
        super.init(frame: .zero)
        self.title = title
        target = self
        action = #selector(click)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func click() { onClick?() }
}
