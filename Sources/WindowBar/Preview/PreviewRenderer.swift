import AppKit
import WindowBarCore

/// Renders only owned, offscreen AppKit views. No menu tracking, capture or activation.
enum PreviewRenderer {
    enum RenderingError: Error { case bitmapUnavailable }

    static func write(to url: URL) throws {
        let view = BarView(frame: NSRect(x: 0, y: 0, width: 1320, height: BarLayout.height))
        view.update(entries: sampleWindows(), trusted: true, launchers: sampleLaunchers())
        view.layoutSubtreeIfNeeded()
        try writeView(view, to: url)
    }

    static func documentation(in directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let previous = app.appearance
        defer { app.appearance = previous }
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            app.appearance = NSAppearance(named: appearance)
            let scene = ScreenshotBackdrop(frame: NSRect(x: 0, y: 0, width: 1320, height: 340))
            let panel = TaskbarPanel(
                contentRect: scene.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
                defer: false)
            panel.isReleasedWhenClosed = false
            panel.contentView = scene
            let bar = BarView(frame: NSRect(x: 0, y: 8, width: 1320, height: BarLayout.height))
            bar.update(entries: sampleWindows(), trusted: true, launchers: sampleLaunchers())
            scene.addSubview(bar)
            scene.layoutSubtreeIfNeeded()
            // A deterministic material backing stands in for the desktop behind the shelf.
            bar.blendingMode = .withinWindow
            bar.layer?.backgroundColor =
                appearance == .aqua
                ? NSColor(calibratedWhite: 0.94, alpha: 1).cgColor
                : NSColor(calibratedWhite: 0.16, alpha: 1).cgColor
            try writeView(bar, to: directory.appendingPathComponent("quiet-shelf-\(name).png"))
            if name == "dark" {
                try writeView(scene, to: directory.appendingPathComponent("overview.png"))
                try writeView(bar, to: directory.appendingPathComponent("windowbar.png"))
                var left = BarPreferences()
                left.pinnedSide = .left
                bar.update(
                    entries: sampleWindows(), trusted: true, launchers: sampleLaunchers(), preferences: left)
                try writeView(bar, to: directory.appendingPathComponent("pins-left.png"))
            }
            panel.close()
        }
        app.appearance = NSAppearance(named: .darkAqua)
        if let chrome = sampleLaunchers().first(where: { $0.name == "Google Chrome" }) {
            let menu = LauncherMenuBuilder(profiles: SampleChromeProfiles()).makeMenu(
                launcher: chrome, windows: sampleWindows().filter { $0.appName == chrome.name },
                onSelect: { _ in })
            let view = menuSnapshot(menu)
            try writeView(view, to: directory.appendingPathComponent("chrome-menu.png"))
        }
        let suite = "local.windowbar.screenshot.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = PreferencesStore(defaults: defaults)
        try preferences.importLaunchersIfNeeded(sampleLaunchers())
        let controller = SettingsWindowController(
            features: FeatureCoordinator(preferences: preferences),
            startup: LoginItemService(backend: FeatureVerification.LoginBackend(), installed: { true }),
            decorateWindow: false)
        defer { controller.close() }
        if let view = controller.tabs.selectedTabViewItem?.view {
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 1).cgColor
            view.layoutSubtreeIfNeeded()
            try writeView(view, to: directory.appendingPathComponent("settings.png"))
        }
        controller.tabs.selectTabViewItem(at: 1)
        if let view = controller.tabs.selectedTabViewItem?.view {
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 1).cgColor
            try writeView(view, to: directory.appendingPathComponent("behavior.png"))
        }
        controller.tabs.selectTabViewItem(at: 2)
        if let view = controller.tabs.selectedTabViewItem?.view {
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 1).cgColor
            try writeView(view, to: directory.appendingPathComponent("pinned-settings.png"))
        }
        controller.tabs.selectTabViewItem(at: 3)
        if let view = controller.tabs.selectedTabViewItem?.view {
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 1).cgColor
            try writeView(view, to: directory.appendingPathComponent("appearance-settings.png"))
        }
        let switcher = WindowSwitcherController(decorateWindow: false)
        defer { switcher.close() }
        switcher.update(entries: sampleWindows(), preferences: BarPreferences())
        switcher.search.stringValue = "chrome"
        switcher.filter()
        if let view = switcher.window?.contentView {
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 1).cgColor
            try writeView(view, to: directory.appendingPathComponent("search.png"))
        }
        let panel = TaskbarPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1600, height: 66),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        defer { panel.close() }
        let grouped = BarView(frame: NSRect(origin: .zero, size: panel.frame.size))
        panel.contentView = grouped
        var grouping = BarPreferences()
        grouping.groupingMode = .appAndProfile
        grouped.update(
            entries: sampleWindows(), trusted: true, launchers: sampleLaunchers(), preferences: grouping)
        grouped.layoutSubtreeIfNeeded()
        grouped.blendingMode = .withinWindow
        grouped.layer?.backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 1).cgColor
        try writeView(grouped, to: directory.appendingPathComponent("grouping.png"))
        var tinted = BarPreferences()
        tinted.barTint = .strong
        grouped.update(
            entries: sampleWindows(), trusted: true, launchers: sampleLaunchers(), preferences: tinted)
        grouped.layoutSubtreeIfNeeded()
        try writeView(grouped, to: directory.appendingPathComponent("bar-tint.png"))
        try sideColumns(in: directory)
        try edgeLines(in: directory)
        if let button = FeatureViewVerification.descendants(grouped).compactMap({ $0 as? WindowButton })
            .first(where: { !$0.entry.focused })
        {
            let hover = HoverPreviewController(showWindows: false)
            hover.hover(button.entry, button: button, entered: true, mode: .titles, actionsEnabled: true)
            FeatureViewVerification.wait(0.52)
            if let view = hover.previewContent {
                view.wantsLayer = true
                view.layer?.backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 1).cgColor
                try writeView(view, to: directory.appendingPathComponent("hover-actions.png"))
            }
            hover.hide()
        }
    }

    private static func sideColumns(in directory: URL) throws {
        for (name, collapsed) in [("side-dock", false), ("side-dock-collapsed", true)] {
            var side = BarPreferences()
            side.barEdge = .right
            side.sideCollapsed = collapsed
            let width = CGFloat(collapsed ? ColumnLayout.collapsedWidth : ColumnLayout.width)
            let panel = TaskbarPanel(
                contentRect: NSRect(x: 0, y: 0, width: width, height: 760),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            defer { panel.close() }
            let column = BarView(frame: NSRect(origin: .zero, size: panel.frame.size))
            panel.contentView = column
            column.update(
                entries: sampleWindows(), trusted: true, launchers: sampleLaunchers(), preferences: side)
            column.layoutSubtreeIfNeeded()
            column.blendingMode = .withinWindow
            column.layer?.backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 1).cgColor
            try writeView(column, to: directory.appendingPathComponent("\(name).png"))
        }
    }

    /// The auto-hidden bar's line along the bottom of a dark stand-in desktop, in both states.
    private static func edgeLines(in directory: URL) throws {
        let scene = NSView(frame: NSRect(x: 0, y: 0, width: 1320, height: 48))
        scene.wantsLayer = true
        scene.layer?.backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 1).cgColor
        let strip = EdgeStripView(frame: NSRect(x: 0, y: 0, width: scene.frame.width, height: 6))
        scene.addSubview(strip)
        for (name, alerting) in [("edge-line", false), ("edge-line-alert", true)] {
            strip.alerting = alerting
            try writeView(scene, to: directory.appendingPathComponent("\(name).png"))
        }
    }

    /// Render the actual menu's item state using native labels and separators, without
    /// opening a popup over the user's current work.
    private static func menuSnapshot(_ menu: NSMenu) -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 330, height: CGFloat(menu.items.count * 26 + 20)))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 1).cgColor
        view.layer?.cornerRadius = 10
        var y = view.bounds.height - 32
        for item in menu.items {
            if item.isSeparatorItem {
                let separator = NSBox(frame: NSRect(x: 12, y: y + 10, width: 306, height: 1))
                separator.boxType = .separator
                view.addSubview(separator)
            } else {
                let label = NSTextField(labelWithString: (item.state == .on ? "✓ " : "   ") + item.title)
                label.font = .systemFont(ofSize: 12)
                label.textColor = item.isEnabled ? .labelColor : .secondaryLabelColor
                label.frame = NSRect(x: 12, y: y, width: 306, height: 22)
                view.addSubview(label)
            }
            y -= 26
        }
        return view
    }

    static func writeView(_ view: NSView, to url: URL) throws {
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw RenderingError.bitmapUnavailable
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw RenderingError.bitmapUnavailable
        }
        try png.write(to: url)
    }
}
