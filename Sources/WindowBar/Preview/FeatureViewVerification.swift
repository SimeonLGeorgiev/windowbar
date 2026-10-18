import AppKit
import WindowBarCore

enum FeatureViewVerification {
    final class Drag: NSObject, NSDraggingInfo {
        var draggingDestinationWindow: NSWindow?
        var draggingSourceOperationMask: NSDragOperation = .move
        var draggingLocation = NSPoint.zero
        var draggedImageLocation = NSPoint.zero
        var draggedImage: NSImage? { nil }
        let draggingPasteboard = NSPasteboard.withUniqueName()
        var draggingSource: Any?
        var draggingSequenceNumber = 1
        var draggingFormation: NSDraggingFormation = .none
        var animatesToDestination = false
        var numberOfValidItemsForDrop = 1
        var springLoadingHighlight: NSSpringLoadingHighlight = .none
        func slideDraggedImage(to screenPoint: NSPoint) {}
        override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
        func resetSpringLoading() {}
        func enumerateDraggingItems(
            options: NSDraggingItemEnumerationOptions, for view: NSView?, classes: [AnyClass],
            searchOptions: [NSPasteboard.ReadingOptionKey: Any],
            using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
        ) {}

        init(source: ReorderableButton, target: ReorderableButton, after: Bool) {
            super.init()
            draggingSource = source
            draggingDestinationWindow = target.window
            draggingLocation = target.convert(
                NSPoint(x: after ? target.bounds.maxX - 2 : 2, y: target.bounds.midY), to: nil)
            draggingPasteboard.setString(
                source.dragIdentifier,
                forType: NSPasteboard.PasteboardType("local.windowbar.\(source.kind.rawValue)"))
        }
    }

    final class DeferredPreview: WindowPreviewProviding {
        var completion: ((PreviewResult) -> Void)?
        var calls = 0
        func preview(_ entry: WindowEntry, completion: @escaping (PreviewResult) -> Void) {
            calls += 1
            self.completion = completion
        }
    }

    static func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    static func wait(_ seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: min(deadline, Date().addingTimeInterval(0.01)))
            Thread.sleep(forTimeInterval: 0.001)
        }
    }

    static func waitUntil(_ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(2)
        repeat {
            if condition() { return true }
            wait(0.02)
        } while Date() < deadline
        return condition()
    }

    static func run(features: FeatureCoordinator, directory: URL) throws {
        let require = FeatureVerification.require
        let panel = TaskbarPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 66),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        defer { panel.close() }
        let bar = BarView(frame: NSRect(x: 0, y: 0, width: 1200, height: 66))
        panel.contentView = bar
        var entries = sampleWindows()
        entries[0].profile = ChromeProfile(directory: "Profile 1", name: "Work")
        let launchers = [
            LauncherEntry(url: directory.appendingPathComponent("One.app"), name: "One", icon: NSImage()),
            LauncherEntry(url: directory.appendingPathComponent("Two.app"), name: "Two", icon: NSImage()),
        ]
        bar.update(entries: entries, trusted: true, launchers: launchers)
        bar.layoutSubtreeIfNeeded()
        let buttons = descendants(bar).compactMap { $0 as? WindowButton }
        let pins = descendants(bar).compactMap { $0 as? LauncherButton }
        try require(buttons.count == 5 && pins.count == 2, "Native bar did not render all entries")
        try require(
            bar.launchScroll.frame.maxX < bar.scroll.frame.minX, "Default pinned apps are not on the left")
        try require(!panel.canBecomeKey && !panel.canBecomeMain, "Taskbar would steal keyboard focus")
        let focused = buttons.first { $0.entry.focused }!
        let normal = buttons.first { !$0.entry.focused }!
        try require(
            abs(focused.frame.width / normal.frame.width - 1.3) < 0.01, "Focused button lost its larger width"
        )
        try require(
            focused.accessibilityLabel()?.contains("Work") == true,
            "Profile name is missing from accessibility")
        print("PASS: native Quiet Shelf layout, leading pins, focus size, and profile accessibility")

        var selected: String?
        bar.onSelect = { selected = $0.id }
        normal.performClick(nil)
        try require(selected == normal.entry.id, "Native button did not route window selection")
        bar.onWindowReorder = { source, target, after in
            features.moveWindow(source, relativeTo: target, after: after)
        }
        _ = features.ordered(entries)
        let drag = Drag(source: buttons[0], target: buttons[4], after: true)
        try require(
            buttons[4].draggingEntered(drag) == .move && buttons[4].prepareForDragOperation(drag),
            "Valid window drag rejected")
        try require(buttons[4].performDragOperation(drag), "Window drop failed")
        try require(
            features.ordered(entries).last?.id == buttons[0].entry.id, "Drop did not reorder the window")
        let mixed = Drag(source: pins[0], target: buttons[4], after: false)
        try require(
            buttons[4].draggingEntered(mixed).isEmpty && !buttons[4].performDragOperation(mixed),
            "App pin was accepted as a window")
        var pinDrop = false
        bar.onLauncherReorder = { source, target, after in
            pinDrop = source == pins[0].dragIdentifier && target == pins[1].dragIdentifier && after
        }
        try require(
            pins[1].performDragOperation(Drag(source: pins[0], target: pins[1], after: true)) && pinDrop,
            "Pinned-icon drag was not routed")
        print("PASS: native selection, window/app drag drops, and cross-type rejection")

        let crowded = (0..<30).map { index -> WindowEntry in
            let entry = entries[index % entries.count]
            return WindowEntry(
                id: "crowded-\(index)", pid: entry.pid, appName: entry.appName, title: entry.title,
                icon: entry.icon, element: nil, minimized: false, focused: index == 29, profile: entry.profile
            )
        }
        bar.frame.size.width = 600
        bar.update(entries: crowded, trusted: true, launchers: launchers)
        bar.layoutSubtreeIfNeeded()
        let crowdedButtons = descendants(bar).compactMap { $0 as? WindowButton }
        try require(
            crowdedButtons.count == 30
                && crowdedButtons.allSatisfy { $0.frame.minY == 0 && $0.frame.width >= 42 },
            "Crowded bar broke one-row targets")
        try require(bar.document.frame.width > bar.scroll.frame.width, "Crowded list did not scroll")
        bar.revealWindow("crowded-29")
        try require(
            bar.scroll.contentView.bounds.minX > 0, "Keyboard selection did not reveal offscreen window")
        print("PASS: 30-window shrink/overflow and selected-window reveal")

        let deferred = DeferredPreview()
        let hover = HoverPreviewController(provider: deferred, showWindows: false)
        let target = crowdedButtons.first { !$0.entry.focused }!
        hover.hover(target.entry, button: target, entered: true, mode: .thumbnails)
        wait(0.25)
        try require(hover.shownEntryID == nil, "Hover preview appeared before its intent delay")
        try require(
            waitUntil { hover.shownEntryID == target.entry.id && deferred.calls == 1 },
            "Hover intent delay did not show preview")
        hover.hide()
        deferred.completion?(.image(NSImage(size: NSSize(width: 80, height: 60))))
        try require(hover.shownEntryID == nil, "Stale capture reopened dismissed hover")
        hover.hover(target.entry, button: target, entered: true, mode: .titles)
        hover.retainOnly([])
        wait(0.52)
        try require(hover.shownEntryID == nil, "Removed window's pending hover opened")
        hover.hover(target.entry, button: target, entered: true, mode: .titles)
        try require(
            waitUntil { hover.shownEntryID == target.entry.id } && deferred.calls == 1,
            "Title-only hover did not appear or requested capture")
        hover.hide()
        print("PASS: hover delay, title fallback, stale-capture dismissal, and removed-window cancellation")

        let login = FeatureVerification.LoginBackend()
        let settings = SettingsWindowController(
            features: features, startup: LoginItemService(backend: login, installed: { true }),
            installer: ApplicationInstaller(
                destination: directory.appendingPathComponent("Installed.app"), isRunning: { _ in false },
                verify: { _ in }), logDirectory: directory, decorateWindow: false)
        defer { settings.close() }
        settings.scope.selectItem(at: 1)
        settings.changeScope()
        settings.preview.selectItem(at: 1)
        settings.changePreview()
        try require(
            features.preferences.value.windowScope == .currentDisplay
                && features.preferences.value.previewMode == .thumbnails,
            "Native settings did not persist choices")
        settings.startupToggle.state = .on
        settings.toggleStartup()
        try require(login.registrations == 1, "Login control did not use its injected service")
        settings.shortcutsToggle.state = .on
        settings.toggleShortcuts()
        try require(features.preferences.value.shortcutsEnabled, "Shortcuts control did not persist")
        try require(
            settings.tabs.tabViewItems.count == 6 && settings.window?.isVisible == false,
            "Settings pages are missing or interrupted desktop")
        try require(
            settings.tabs.selectedTabViewItem?.label == "General" && settings.startupToggle.frame.height > 0,
            "General settings page was not selected or laid out")
        let recorder = ShortcutRecorderButton(binding: ShortcutBinding.defaults[0])
        var recorded: ShortcutBinding?
        recorder.onRecord = { recorded = $0 }
        recorder.performClick(nil)
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.command, .option], timestamp: 0,
            windowNumber: 0, context: nil, characters: "a", charactersIgnoringModifiers: "a",
            isARepeat: false, keyCode: 0)!
        recorder.keyDown(with: event)
        try require(
            recorded?.keyCode == 0 && recorded?.modifiers == ShortcutBinding.command | ShortcutBinding.option,
            "Shortcut recorder did not preserve key/modifier combination")
        print("PASS: native settings controls, isolated login action, and shortcut recording")

        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            bar.appearance = NSAppearance(named: appearance)
            bar.layoutSubtreeIfNeeded()
            guard let bitmap = bar.bitmapImageRepForCachingDisplay(in: bar.bounds) else {
                throw FeatureVerification.Failure.check("Native rendering failed")
            }
            bar.cacheDisplay(in: bar.bounds, to: bitmap)
            try require(bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0, "Empty light/dark rendering")
        }
        try require(!panel.isVisible, "Offscreen tests displayed a taskbar")
        print("PASS: native light/dark rendering with all test windows kept offscreen")
    }
}
