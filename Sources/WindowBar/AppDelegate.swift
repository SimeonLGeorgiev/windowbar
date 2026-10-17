import AppKit
import ApplicationServices
import WindowBarCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let recoveryMode = ProcessInfo.processInfo.environment["WINDOWBAR_RECOVERY_MODE"] == "1"
    private var panels: [TaskbarPanel] = []
    private var bars: [BarView] = []
    private var statusItem: NSStatusItem?
    private var timer: Timer?
    private var edgeTimer: Timer?
    private var autoHideControllers: [BarAutoHideController] = []
    private var trackingMenus = 0
    private var switcher: WindowSwitcherController?
    private var scanning = false
    private var entries: [WindowEntry] = []
    private let scanner = DispatchQueue(label: "windowbar.accessibility", qos: .utility)
    private let workAreas = WindowWorkAreaController()
    private var zoomMonitor: Any?
    private var allDisplays = UserDefaults.standard.bool(forKey: "allDisplays")
    private var hidden = false
    private let demo: Bool
    private let screenshots: Bool
    private var backdrop: TaskbarPanel?
    private let dock: DockReplacing
    private let windowService: WindowDiscovering
    private let windowActions: WindowActing
    private let launcherMenus: LauncherMenuProviding
    private var scanGeneration = ScanGeneration()
    private let features: FeatureCoordinator
    private let diagnostics: Diagnostics
    private let previews = HoverPreviewController()
    private let rowSummary = RowSummaryController()
    private let peek = WindowPeekController()
    private let workAreaQueue = DispatchQueue(label: "local.windowbar.work-area", qos: .userInitiated)
    private var recency = WindowRecency()
    private var attention = AppAttention()
    private let badgeReader: AppBadgeReading
    private let windowBadgeReader = WindowBadgeReader()
    private lazy var shortcuts = GlobalShortcuts()
    private lazy var managementMenus = BarManagementMenus(features: features)
    private let settingsProcess = SettingsProcessController()
    private var lastTrusted: Bool?
    private var terminationSignals: [DispatchSourceSignal] = []

    init(
        demo: Bool = false, screenshots: Bool = false, dock: DockReplacing = DockController(),
        windowService: WindowDiscovering = AccessibilityWindowService(),
        windowActions: WindowActing = WindowActions(),
        launcherMenus: LauncherMenuProviding = LauncherMenuBuilder(),
        features: FeatureCoordinator = FeatureCoordinator(), diagnostics: Diagnostics = .shared,
        badgeReader: AppBadgeReading = DockBadgeReader()
    ) {
        self.demo = demo
        self.screenshots = screenshots
        self.dock = dock
        self.windowService = windowService
        self.windowActions = windowActions
        self.launcherMenus = launcherMenus
        self.features = features
        self.diagnostics = diagnostics
        self.badgeReader = badgeReader
        super.init()
        if recoveryMode {
            replacesDock = false
            allDisplays = true
        }
    }
    private var replacesDock = UserDefaults.standard.object(forKey: "replacesDock") as? Bool ?? false
    private var launchers: [LauncherEntry] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        launchers = dockLaunchers()
        managementMenus.onPinsChanged = { [weak self] in self?.changePins {} }
        managementMenus.onOrderChanged = { [weak self] in self?.render() }
        managementMenus.onRefresh = { [weak self] in self?.refresh() }
        managementMenus.onError = { [weak self] _ in
            NSSound.beep()
            self?.diagnostics.record(.settingsChangeFailed)
        }
        if !demo {
            do {
                try features.preferences.importLaunchersIfNeeded(launchers)
                launchers = features.preferences.launchers()
            } catch { diagnostics.record(.scanFailed) }
            shortcuts.onAction = { [weak self] in self?.performShortcut($0) }
            do {
                try shortcuts.configure(
                    recoveryMode ? [] : features.preferences.value.activeShortcuts)
            } catch { diagnostics.record(.shortcutRegistrationFailed) }
            for value in [SIGTERM, SIGINT, SIGHUP] {
                signal(value, SIG_IGN)
                let source = DispatchSource.makeSignalSource(signal: value, queue: .main)
                source.setEventHandler { NSApp.terminate(nil) }
                source.resume()
                terminationSignals.append(source)
            }
        }
        if !recoveryMode && !demo && replacesDock && AXIsProcessTrusted() { _ = dock.enable() }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(
            systemSymbolName: "rectangle.split.3x1", accessibilityDescription: "WindowBar")
        statusItem?.menu = makeMenu()
        if screenshots { createBackdrop() }
        peek.onSelect = { [weak self] in self?.select($0) }
        previews.onSelect = { [weak self] in self?.select($0) }
        previews.onMinimize = { [weak self] in self?.minimize($0) }
        previews.onClose = { [weak self] in self?.closeWindow($0) }
        previews.onShow = { [weak self] in self?.rowSummary.hide() }
        rebuildPanels()
        configureZoomMonitor()
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(preferencesChanged), name: .windowBarPreferencesChanged, object: nil)
        configureAutoHideTimer()
        NotificationCenter.default.addObserver(
            self, selector: #selector(menuBegan), name: NSMenu.didBeginTrackingNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(menuEnded), name: NSMenu.didEndTrackingNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(rebuildPanels),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(refreshAppearance),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(activeApplicationChanged),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        timer = Timer.scheduledTimer(
            timeInterval: 1.5, target: self, selector: #selector(refresh), userInfo: nil, repeats: true)
        refresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        edgeTimer?.invalidate()
        settingsProcess.stop()
        switcher?.dismiss()
        cancelHover()
        if let zoomMonitor { NSEvent.removeMonitor(zoomMonitor) }
        zoomMonitor = nil
        workAreaQueue.sync { workAreas.stop() }
        for source in terminationSignals { source.cancel() }
        if !demo { diagnostics.record(.shutdownRequested) }
        let restored = dock.restore()
        if !demo { diagnostics.finishSession(restoredDock: restored) }
    }

    private func createBackdrop() {
        guard let screen = NSScreen.screens.first else { return }
        let frame = NSRect(
            x: screen.visibleFrame.minX + 12, y: screen.visibleFrame.minY,
            width: screen.visibleFrame.width - 24, height: 620)
        let panel = TaskbarPanel(
            contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
            defer: false)
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.title = "WindowBar Screenshots"
        panel.contentView = ScreenshotBackdrop(frame: NSRect(origin: .zero, size: frame.size))
        panel.orderFrontRegardless()
        backdrop = panel
    }

    @objc private func rebuildPanels() {
        cancelHover()
        for panel in panels { panel.close() }
        panels = []
        bars = []
        autoHideControllers = []
        // The first screen is the display with the menu bar, not the focused window's display.
        let screens = allDisplays ? NSScreen.screens : Array(NSScreen.screens.prefix(1))
        for screen in screens {
            let frame = barFrame(for: screen)
            let panel = TaskbarPanel(
                contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
                defer: false)
            panel.isReleasedWhenClosed = false
            panel.level = .floating
            // Transient, not stationary: Show Desktop and Mission Control clear the bar like other windows.
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
            panel.hidesOnDeactivate = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.title = "WindowBar"
            let bar = BarView(frame: NSRect(origin: .zero, size: frame.size))
            if recoveryMode {
                bar.blendingMode = .withinWindow
                bar.state = .inactive
                bar.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            }
            bar.onSearch = { [weak self] in self?.showSwitcher() }
            bar.onGroupToggle = { [weak self] in self?.cancelHover() }
            bar.onSelect = { [weak self] in self?.select($0) }
            bar.onMinimize = { [weak self] in self?.minimize($0) }
            bar.onClose = { [weak self] in self?.closeWindow($0) }
            bar.onLaunch = { [weak self] in self?.launch($0) }
            bar.makeLauncherMenu = { [weak self] launcher, windows in
                guard let self else { return NSMenu() }
                let menu = self.launcherMenus.makeMenu(
                    launcher: launcher, windows: windows, onSelect: { [weak self] in self?.select($0) })
                self.managementMenus.augmentLauncher(menu, launcher: launcher, launchers: self.launchers)
                return menu
            }
            bar.onWindowReorder = { [weak self] source, target, after in
                self?.cancelHover()
                self?.features.moveWindow(source, relativeTo: target, after: after)
                self?.render()
            }
            bar.onLauncherReorder = { [weak self] source, target, after in
                guard let self else { return }
                self.cancelHover()
                self.changePins { try self.features.moveLauncher(source, relativeTo: target, after: after) }
            }
            bar.onLauncherHover = { [weak self] launcher, _, button, entered in
                guard let self else { return }
                let windows = self.windows(for: launcher)
                if entered && windows.contains(where: \.focused) {
                    self.cancelHover()
                    return
                }
                let id = self.recency.mostRecent(in: windows.map(\.id))
                let target = windows.first { $0.id == id }
                if entered { self.previews.hide() }
                self.hoverPeek(
                    target, source: "launcher:" + launcher.url.path, button: button, entered: entered)
            }
            bar.onHover = { [weak self] entry, button, entered in
                guard let self else { return }
                self.hoverPeek(entry, source: "window:" + entry.id, button: button, entered: entered)
                if self.recoveryMode { return }
                self.previews.hover(
                    entry, button: button, entered: entered,
                    mode: self.features.preferences.value.previewMode,
                    actionsEnabled: self.features.preferences.value.hoverActionsEnabled
                )
            }
            bar.onRowPointer = { [weak self] in self?.rowPointer($0, button: $1, entered: $2) }
            bar.onDragStart = { [weak self] in self?.cancelHover() }
            bar.augmentWindowMenu = { [weak self] menu, entry in
                guard let self else { return }
                self.managementMenus.augmentWindow(menu, entry: entry, entries: self.entries)
            }
            bar.menuButton.target = self
            bar.menuButton.action = #selector(showMenu(_:))
            bar.collapseButton.target = self
            bar.collapseButton.action = #selector(toggleCollapsed)
            bar.permissionButton.target = self
            bar.permissionButton.action = #selector(enableAccessibility)
            panel.contentView = bar
            panels.append(panel)
            bars.append(bar)
            let autoHide = BarAutoHideController()
            autoHide.layout(
                shownFrame: frame, screenFrame: screen.frame, edge: features.preferences.value.barEdge,
                panel: panel)
            autoHideControllers.append(autoHide)
            if !hidden { panel.orderFrontRegardless() }
        }
        render()
    }

    private func barFrame(for screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let bottom = dock.isEnabled && !demo ? screen.frame.minY : visible.minY
        let edge = features.preferences.value.barEdge
        guard edge != .bottom else {
            let width = max(200, visible.width - 24)
            return NSRect(x: visible.minX + 12, y: bottom + 8, width: width, height: BarLayout.height)
        }
        let width = CGFloat(
            features.preferences.value.sideCollapsed ? ColumnLayout.collapsedWidth : ColumnLayout.width)
        let originX = edge == .left ? visible.minX + 8 : visible.maxX - width - 8
        return NSRect(x: originX, y: bottom + 8, width: width, height: max(200, visible.maxY - bottom - 16))
    }

    @objc private func refresh() {
        // Dock size/auto-hide changes need no relaunch.
        let screens = allDisplays ? NSScreen.screens : Array(NSScreen.screens.prefix(1))
        for (index, screen) in screens.enumerated() where panels.indices.contains(index) {
            autoHideControllers[index].layout(
                shownFrame: barFrame(for: screen), screenFrame: screen.frame,
                edge: features.preferences.value.barEdge, panel: panels[index])
        }
        if demo {
            entries = sampleWindows()
            render()
            return
        }
        let trusted = AXIsProcessTrusted()
        if lastTrusted != trusted {
            lastTrusted = trusted
            diagnostics.record(.permissionChanged)
        }
        guard trusted else {
            scanGeneration.invalidate()
            _ = dock.restore()
            entries = []
            render()
            return
        }
        if replacesDock && !hidden { _ = dock.enable() }
        guard !scanning else { return }
        scanning = true
        let captured = scanGeneration.value
        let service = windowService
        let badgeReader = self.badgeReader
        let windowBadgeReader = self.windowBadgeReader
        let readsBadges = !recoveryMode && features.preferences.value.notificationMode != .off
        scanner.async { [weak self] in
            let windows = service.readWindows()
            let badges = readsBadges ? windowBadgeReader.read(windows, adding: badgeReader.read()) : nil
            DispatchQueue.main.async {
                guard let self else { return }
                self.scanning = false
                guard self.scanGeneration.accepts(captured) else {
                    self.refresh()
                    return
                }
                self.entries = windows
                if let badges {
                    self.attention.update(
                        badges, focusedApp: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                        now: ProcessInfo.processInfo.systemUptime)
                }
                self.render()
            }
        }
    }

    private func render() {
        entries = features.ordered(entries)
        let available = Set(entries.map(\.id))
        let hoverable = Set(entries.filter { !$0.focused }.map(\.id))
        previews.retainOnly(hoverable)
        peek.retainOnly(hoverable)
        recency.update(available: available, focused: entries.first(where: \.focused)?.id)
        let trusted = demo || AXIsProcessTrusted()
        let screens = allDisplays ? NSScreen.screens : Array(NSScreen.screens.prefix(1))
        for (index, screen) in screens.enumerated() where panels.indices.contains(index) {
            autoHideControllers[index].layout(
                shownFrame: barFrame(for: screen), screenFrame: screen.frame,
                edge: features.preferences.value.barEdge, panel: panels[index])
        }
        switcher?.update(entries: entries, preferences: features.preferences.value)
        updateAutoHide()
        let displays = NSScreen.screens.map { DisplayRegion(id: displayID($0), frame: $0.frame) }
        for (bar, screen) in zip(bars, screens) {
            let visible = features.visible(entries, displayID: displayID(screen), displays: displays)
            var displayedPreferences = features.preferences.value
            if recoveryMode { displayedPreferences.searchEnabled = false }
            bar.update(
                entries: visible, trusted: trusted, launchers: launchers,
                preferences: displayedPreferences)
            bar.updateAttention(attention, mode: features.preferences.value.notificationMode)
        }
        updateReservedWindowSpace()
    }

    private func updateReservedWindowSpace() {
        let areas = reservedWindowAreas()
        let windows = entries
        let mouseDown = NSEvent.pressedMouseButtons != 0
        workAreaQueue.async { [workAreas] in
            workAreas.update(entries: windows, areas: areas, mouseDown: mouseDown)
        }
    }

    private func reservedWindowAreas() -> [ReservedWindowArea] {
        guard !demo && !recoveryMode else { return [] }
        let screens = allDisplays ? NSScreen.screens : Array(NSScreen.screens.prefix(1))
        let reservesSpace = !hidden && !features.preferences.value.autoHideEnabled && AXIsProcessTrusted()
        return
            reservesSpace
            ? screens.map {
                ReservedWindowArea(
                    displayID: displayID($0), visibleFrame: $0.visibleFrame, barFrame: barFrame(for: $0),
                    edge: features.preferences.value.barEdge)
            } : []
    }

    private func configureZoomMonitor() {
        guard !demo && !recoveryMode else { return }
        zoomMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            guard let self, event.clickCount == 2, !self.hidden,
                !self.features.preferences.value.autoHideEnabled,
                let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
            else { return }
            let windows = self.entries
            let areas = self.reservedWindowAreas()
            let layoutQueue = self.workAreaQueue
            let pointer = NSEvent.mouseLocation
            let now = event.timestamp
            layoutQueue.async { [workAreas = self.workAreas] in
                guard
                    let focused = Accessibility.element(
                        attribute(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute)),
                    let index = windows.firstIndex(where: {
                        $0.pid == pid && $0.element.map { CFEqual($0, focused) } == true
                    })
                else { return }
                let entry = windows[index]
                workAreas.requestRestore(id: entry.id, pointer: pointer, now: now)
                // Apply zoom clearance without waiting for a full scan of every app.
                layoutQueue.asyncAfter(deadline: .now() + 0.15) {
                    guard let state = AccessibilityWindowResizer().state(of: entry) else { return }
                    var updated = windows
                    updated[index].frame = state.frame
                    workAreas.update(
                        entries: updated, areas: areas, mouseDown: NSEvent.pressedMouseButtons != 0)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.refresh() }
        }
    }

    private func select(_ entry: WindowEntry) {
        guard demo || entry.element != nil else { return }
        cancelHover()
        switcher?.dismiss()
        scanGeneration.invalidate()
        entries = entries.map { existing in
            var updated = existing
            updated.focused = existing.id == entry.id
            return updated
        }
        render()
        for bar in bars { bar.revealWindow(entry.id) }
        if demo { return }
        windowActions.select(entry) { [weak self] in self?.refresh() }
    }

    private func minimize(_ entry: WindowEntry) {
        cancelHover()
        scanGeneration.invalidate()
        if entry.minimized {
            select(entry)
        } else {
            windowActions.minimize(entry)
            refresh()
        }
    }

    private func closeWindow(_ entry: WindowEntry) {
        cancelHover()
        scanGeneration.invalidate()
        windowActions.close(entry)
        refresh()
    }

    @objc private func enableAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        {
            NSWorkspace.shared.open(url)
        }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let title = NSMenuItem(
            title: recoveryMode ? "WindowBar · Recovery" : (demo ? "WindowBar · Demo" : "WindowBar"),
            action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        let items: [(String, Selector, String)] = [
            (hidden ? "Show bar" : "Hide bar", #selector(toggleVisibility), ""),
            ("Replace macOS Dock", #selector(toggleDock), ""),
            ("Show on all displays", #selector(toggleDisplays), ""),
            ("Search windows…", #selector(showSwitcher), ""),
            ("Settings…", #selector(showSettings), ","),
            ("Open Downloads", #selector(openDownloads), ""),
            ("Open Trash", #selector(openTrash), ""),
            ("Refresh windows", #selector(refresh), ""),
            ("Enable Accessibility…", #selector(enableAccessibility), ""),
            ("Quit WindowBar", #selector(quit), "q"),
        ]
        for (title, action, shortcut) in items {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: shortcut)
            item.target = self
            if action == #selector(showSwitcher) { item.isEnabled = features.preferences.value.searchEnabled }
            if recoveryMode
                && [#selector(showSettings), #selector(showSwitcher), #selector(toggleDock)].contains(action)
            {
                item.isEnabled = false
            }
            if action == #selector(toggleDisplays) { item.state = allDisplays ? .on : .off }
            if action == #selector(toggleDock) { item.state = replacesDock ? .on : .off }
            menu.addItem(item)
            if action == #selector(toggleDisplays) { menu.addItem(barPositionItem()) }
        }
        return menu
    }

    @objc private func showMenu(_ sender: NSButton) {
        makeMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 8), in: sender)
    }

    @objc private func toggleVisibility() {
        cancelHover()
        hidden.toggle()
        configureAutoHideTimer()
        if hidden {
            dock.restore()
        } else if replacesDock && !demo && AXIsProcessTrusted() {
            _ = dock.enable()
        }
        for panel in panels { if hidden { panel.orderOut(nil) } else { panel.orderFrontRegardless() } }
        updateReservedWindowSpace()
        statusItem?.menu = makeMenu()
    }

    @objc private func toggleDock() {
        guard !recoveryMode else { return }
        replacesDock.toggle()
        if replacesDock && !hidden && !demo && AXIsProcessTrusted() {
            _ = dock.enable()
        } else {
            dock.restore()
        }
        UserDefaults.standard.set(replacesDock, forKey: "replacesDock")
        refresh()
        statusItem?.menu = makeMenu()
    }

    @objc private func openDownloads() {
        if let url = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openTrash() {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        NSWorkspace.shared.open(url)
    }

    @objc private func toggleDisplays() {
        allDisplays.toggle()
        UserDefaults.standard.set(allDisplays, forKey: "allDisplays")
        rebuildPanels()
        statusItem?.menu = makeMenu()
    }

    @objc private func quit() { NSApp.terminate(nil) }

    private func displayID(_ screen: NSScreen) -> UInt32 {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
            ?? CGMainDisplayID()
    }

    @objc private func refreshAppearance() {
        cancelHover()
        rebuildPanels()
    }

    @objc private func showSettings() {
        guard !recoveryMode else { return }
        cancelHover()
        do { try settingsProcess.show() } catch { diagnostics.record(.settingsChangeFailed) }
    }

    @objc private func preferencesChanged() {
        guard !recoveryMode else { return }
        let previous = features.preferences.value
        let updated = features.preferences.persistedValue()
        do {
            try updated.validate()
            if !demo { try shortcuts.configure(updated.activeShortcuts) }
            try features.preferences.save(updated)
            cancelHover()
            configureAutoHideTimer()
            launchers = features.preferences.launchers()
            render()
            statusItem?.menu = makeMenu()
            settingsProcess.preferencesApplied()
            if !demo { diagnostics.record(.preferencesChanged) }
        } catch {
            if !demo { try? shortcuts.configure(previous.activeShortcuts) }
            try? features.preferences.save(previous)
            DistributedNotificationCenter.default().postNotificationName(
                .windowBarPreferencesRejected, object: nil, userInfo: nil, deliverImmediately: true)
            diagnostics.record(.settingsChangeFailed)
        }
    }

    @objc private func showSwitcher() {
        guard !recoveryMode else { return }
        guard features.preferences.value.searchEnabled else { return }
        cancelHover()
        let previousApp = NSWorkspace.shared.frontmostApplication
        if switcher == nil { switcher = WindowSwitcherController() }
        switcher?.onSelect = { [weak self] in self?.select($0) }
        switcher?.onCancel = {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier
                == ProcessInfo.processInfo.processIdentifier
            {
                previousApp?.activate(options: [])
            }
        }
        switcher?.update(entries: entries, preferences: features.preferences.value)
        switcher?.present()
    }

    @objc private func menuBegan() { trackingMenus += 1 }
    @objc private func menuEnded() { trackingMenus = max(0, trackingMenus - 1) }

    private func configureAutoHideTimer() {
        edgeTimer?.invalidate()
        edgeTimer = nil
        guard !recoveryMode, features.preferences.value.autoHideEnabled, !hidden else { return }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.updateAutoHide() }
        edgeTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func updateAutoHide() {
        guard !hidden else { return }
        let value = features.preferences.value
        let point = NSEvent.mouseLocation
        for (panel, controller) in zip(panels, autoHideControllers) {
            let interacting =
                trackingMenus > 0 || settingsProcess.processIdentifier != nil
                || switcher?.window?.isVisible == true
                || previews.interactionFrame?.contains(point) == true
                || peek.isActive
                || (!controller.hidden && NSEvent.pressedMouseButtons != 0)
            controller.update(
                panel: panel, enabled: value.autoHideEnabled && !recoveryMode, delay: value.autoHideDelay,
                pointer: point, interaction: interacting, now: ProcessInfo.processInfo.systemUptime)
        }
    }

    private func cancelHover() {
        peek.hide()
        previews.hide()
        rowSummary.hide()
    }

    @objc private func activeApplicationChanged() {
        cancelHover()
        attention.update(
            attention.badges, focusedApp: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            now: ProcessInfo.processInfo.systemUptime)
        refresh()
    }

    private func hoverPeek(_ entry: WindowEntry?, source: String, button: NSView, entered: Bool) {
        guard let host = button.window, let screen = host.screen else { return }
        var available = screen.visibleFrame
        var reservedBottom: CGFloat = 82
        switch features.preferences.value.barEdge {
        case .bottom: break
        case .left:
            available = NSRect(
                x: host.frame.maxX, y: available.minY, width: available.maxX - host.frame.maxX,
                height: available.height)
            reservedBottom = 16
        case .right:
            available.size.width = host.frame.minX - available.minX
            reservedBottom = 16
        }
        peek.hover(
            entry, source: source, entered: entered,
            enabled: features.preferences.value.hoverPeekEnabled && !demo && !recoveryMode,
            sourceFrame: host.convertToScreen(button.convert(button.bounds, to: nil)),
            screenFrame: available, reservedBottom: reservedBottom)
    }

    private func windows(for launcher: LauncherEntry) -> [WindowEntry] {
        let identifier = Bundle(url: launcher.url)?.bundleIdentifier
        let pids = Set(
            identifier.map {
                NSRunningApplication.runningApplications(withBundleIdentifier: $0).map(\.processIdentifier)
            } ?? [])
        return entries.filter { pids.contains($0.pid) || ($0.element == nil && $0.appName == launcher.name) }
    }

    private func launch(_ launcher: LauncherEntry) {
        if let target = peek.activeEntry, windows(for: launcher).contains(where: { $0.id == target.id }) {
            select(target)
        } else {
            cancelHover()
            NSWorkspace.shared.open(launcher.url)
        }
    }

    private func rowPointer(_ entry: WindowEntry, button: NSView, entered: Bool) {
        let value = features.preferences.value
        if entered && value.barEdge != .bottom && value.sideCollapsed {
            rowSummary.show(entry, beside: button)
        } else if !entered {
            rowSummary.hide(entry.id)
        }
    }

    private func barPositionItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Bar position", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let current = features.preferences.value.barEdge
        for (edge, title) in [
            (BarPreferences.BarEdge.bottom, "Bottom"), (.left, "Left side"), (.right, "Right side"),
        ] {
            let option = NSMenuItem(title: title, action: #selector(changeBarEdge(_:)), keyEquivalent: "")
            option.target = self
            option.representedObject = edge.rawValue
            option.state = edge == current ? .on : .off
            submenu.addItem(option)
        }
        item.submenu = submenu
        item.isEnabled = !recoveryMode
        return item
    }

    @objc private func changeBarEdge(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let edge = BarPreferences.BarEdge(rawValue: raw)
        else { return }
        cancelHover()
        var value = features.preferences.value
        value.barEdge = edge
        do {
            try features.preferences.save(value)
            render()
            statusItem?.menu = makeMenu()
            settingsProcess.preferencesApplied()
        } catch { NSSound.beep() }
    }

    @objc private func toggleCollapsed() {
        cancelHover()
        var value = features.preferences.value
        value.sideCollapsed.toggle()
        do {
            try features.preferences.save(value)
            let screens = allDisplays ? NSScreen.screens : Array(NSScreen.screens.prefix(1))
            for (index, screen) in screens.enumerated() where panels.indices.contains(index) {
                autoHideControllers[index].layout(
                    shownFrame: barFrame(for: screen), screenFrame: screen.frame, edge: value.barEdge,
                    panel: panels[index], animated: true)
            }
            render()
            settingsProcess.preferencesApplied()
        } catch { NSSound.beep() }
    }

    private func changePins(_ change: () throws -> Void) {
        do {
            try change()
            launchers = features.preferences.launchers()
            render()
            settingsProcess.preferencesApplied()
        } catch { NSSound.beep() }
    }

    private func performShortcut(_ action: ShortcutAction) {
        if action == .searchWindows {
            showSwitcher()
            return
        }
        if let index = action.pinnedIndex {
            guard launchers.indices.contains(index) else { return }
            NSWorkspace.shared.open(launchers[index].url)
            return
        }
        let regions = NSScreen.screens.map { DisplayRegion(id: displayID($0), frame: $0.frame) }
        let screenID =
            entries.first(where: \.focused).flatMap {
                DisplayFilter.displayID(for: $0.frame, displays: regions)
            }
            ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }).map {
                displayID($0)
            }
            ?? CGMainDisplayID()
        let visible = features.navigationEntries(
            features.visible(entries, displayID: screenID, displays: regions))
        guard
            let index = ShortcutBinding.cycleIndex(
                count: visible.count, focusedIndex: visible.firstIndex(where: \.focused),
                forward: action == .nextWindow)
        else { return }
        select(visible[index])
    }
}
