import AppKit
import WindowBarCore

/// A full-window visual peek never changes another app's focus, minimization, or stacking.
final class WindowPeekController {
    private let provider: WindowPreviewProviding
    private let showWindows: Bool
    private let automaticTicks: Bool
    private var generation = ScanGeneration()
    private var timer: Timer?
    private var monitor: Any?
    private var panel: TaskbarPanel?
    private var source: String?
    private var sourceFrame = CGRect.zero
    private var destination = CGRect.zero
    private var enteredAt: TimeInterval?
    private var outsideSince: TimeInterval?
    private var pending: WindowEntry?
    private var capturingID: String?
    private(set) var activeEntry: WindowEntry?
    private(set) var imageButton: NSButton?
    var onSelect: ((WindowEntry) -> Void)?
    var isActive: Bool { activeEntry != nil }
    var previewFrame: CGRect? { activeEntry == nil ? nil : panel?.frame }

    init(
        provider: WindowPreviewProviding = WindowPreviews(
            backend: ScreenCaptureBackend(maximumWidth: 2560, maximumHeight: 1600)),
        showWindows: Bool = true, automaticTicks: Bool = true
    ) {
        self.provider = provider
        self.showWindows = showWindows
        self.automaticTicks = automaticTicks
    }

    deinit {
        timer?.invalidate()
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    func hover(
        _ entry: WindowEntry?, source: String, entered: Bool, enabled: Bool,
        sourceFrame: CGRect, screenFrame: CGRect, reservedBottom: CGFloat = 82,
        now: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        if !entered {
            guard self.source == source else { return }
            if activeEntry == nil { hide() }
            return
        }
        hide()
        guard enabled, let entry, !entry.focused, !entry.minimized, let frame = entry.frame,
            let destination = PeekLayout.frame(window: frame, screen: screenFrame, reservedBottom: reservedBottom)
        else { return }
        self.source = source
        self.sourceFrame = sourceFrame
        self.destination = destination
        enteredAt = now
        pending = entry
        if automaticTicks {
            let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
                self?.tick(now: ProcessInfo.processInfo.systemUptime, pointer: NSEvent.mouseLocation)
            }
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
            if showWindows {
                monitor = NSEvent.addGlobalMonitorForEvents(matching: [
                    .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown,
                ]) { [weak self] _ in
                    self?.hide()
                }
            }
        }
    }

    func tick(now: TimeInterval, pointer: CGPoint) {
        if activeEntry != nil, let preview = panel?.frame {
            if PeekLayout.containsPointer(pointer, source: sourceFrame, preview: preview) {
                outsideSince = nil
            } else {
                let started = outsideSince ?? now
                outsideSince = started
                if now - started >= 0.15 { hide() }
            }
            return
        }
        guard sourceFrame.contains(pointer) else {
            hide()
            return
        }
        guard let pending, let enteredAt, now - enteredAt >= 0.6 else { return }
        self.pending = nil
        capturingID = pending.id
        let captured = generation.value
        provider.preview(pending) { [weak self] result in
            guard let self, self.generation.accepts(captured) else { return }
            self.capturingID = nil
            guard case .image(let image) = result else {
                self.hide()
                return
            }
            self.show(pending, image: image, generation: captured)
        }
    }

    func hide() {
        generation.invalidate()
        timer?.invalidate()
        timer = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        panel?.orderOut(nil)
        panel?.contentView = nil
        imageButton = nil
        activeEntry = nil
        pending = nil
        capturingID = nil
        enteredAt = nil
        outsideSince = nil
        source = nil
    }

    func retainOnly(_ identifiers: Set<String>) {
        let id = activeEntry?.id ?? pending?.id ?? capturingID
        if let id, !identifiers.contains(id) { hide() }
    }

    private func show(_ entry: WindowEntry, image: NSImage, generation captured: UInt64) {
        if panel == nil {
            let panel = TaskbarPanel(
                contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            // Keep the taskbar and its hover cards above the full-window preview.
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue + 1)
            self.panel = panel
        }
        let button = PeekImageButton(frame: CGRect(origin: .zero, size: destination.size))
        button.image = image
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyUpOrDown
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 10
        button.layer?.masksToBounds = true
        button.layer?.borderWidth = 1
        button.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.5).cgColor
        button.setAccessibilityLabel("Preview of \(entry.appName): \(entry.title). Click to switch.")
        button.onClick = { [weak self] in
            guard let self, self.generation.accepts(captured), self.activeEntry?.id == entry.id else {
                return
            }
            self.hide()
            self.onSelect?(entry)
        }
        panel?.contentView = button
        panel?.setFrame(destination, display: false)
        imageButton = button
        activeEntry = entry
        if showWindows { panel?.orderFrontRegardless() }
    }
}

private final class PeekImageButton: NSButton {
    var onClick: (() -> Void)?
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        target = self
        action = #selector(click)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    @objc private func click() { onClick?() }
}
