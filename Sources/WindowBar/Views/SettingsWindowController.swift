import AppKit
import ApplicationServices
import ServiceManagement
import WindowBarCore

final class SettingsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate,
    NSWindowDelegate
{
    let features: FeatureCoordinator
    let startup: LoginItemService
    let installer: ApplicationInstaller
    var onPreferencesChanged: ((BarPreferences) throws -> Void)?
    var onError: ((Error) -> Void)?
    var onClose: (() -> Void)?
    let tabs = NSTabView()
    let startupToggle = NSButton(checkboxWithTitle: "Start at login", target: nil, action: nil)
    let startupStatus = NSTextField(wrappingLabelWithString: "")
    let scope = NSPopUpButton()
    let preview = NSPopUpButton()
    let shortcutsToggle = NSButton(
        checkboxWithTitle: "Enable global keyboard shortcuts", target: nil, action: nil)
    let searchToggle = NSButton(
        checkboxWithTitle: "Enable searchable window switcher", target: nil, action: nil)
    let minimizedToggle = NSButton(
        checkboxWithTitle: "Include minimized windows in search", target: nil, action: nil)
    let grouping = NSPopUpButton()
    let hoverActionsToggle = NSButton(
        checkboxWithTitle: "Show Switch, Minimize / Restore, and Close on hover", target: nil, action: nil)
    let autoHideToggle = NSButton(
        checkboxWithTitle: "Auto-hide at the screen edge", target: nil, action: nil)
    let hideDelay = NSSlider(value: 0.8, minValue: 0.2, maxValue: 3, target: nil, action: nil)
    let hideDelayLabel = NSTextField(labelWithString: "")
    let notificationMode = NSPopUpButton()
    let pinnedSide = NSPopUpButton()
    let barEdge = NSPopUpButton()
    let barTint = NSPopUpButton()
    let edgeLineWidth = NSPopUpButton()
    let edgeAlertToggle = NSButton(
        checkboxWithTitle: "Turn the edge line red when new unread activity arrives while hidden",
        target: nil, action: nil)
    let peekToggle = NSButton(
        checkboxWithTitle: "Peek at windows after hovering for 0.6 seconds", target: nil, action: nil)
    let pinnedTable = NSTableView()
    let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let shortcutRows = NSStackView()
    private let diagnosticsLabel = NSTextField(wrappingLabelWithString: "")
    private let permissionLabel = NSTextField(wrappingLabelWithString: "")
    private let loginSettings = NSButton(title: "Login Items Settings…", target: nil, action: nil)
    private let logDirectory: URL

    init(
        features: FeatureCoordinator, startup: LoginItemService = LoginItemService(),
        installer: ApplicationInstaller = ApplicationInstaller(),
        logDirectory: URL = Diagnostics.shared.directory, decorateWindow: Bool = true
    ) {
        self.features = features
        self.startup = startup
        self.installer = installer
        self.logDirectory = logDirectory
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 540),
            styleMask: decorateWindow ? [.titled, .closable, .miniaturizable] : [.borderless],
            backing: .buffered, defer: false)
        window.title = "WindowBar Settings"
        window.isReleasedWhenClosed = false
        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 540))
        super.init(window: window)
        window.delegate = self
        tabs.frame = NSRect(x: 20, y: 64, width: 580, height: 456)
        tabs.autoresizingMask = [.width, .height]
        window.contentView?.addSubview(tabs)
        errorLabel.font = .systemFont(ofSize: 11)
        errorLabel.textColor = .systemRed
        errorLabel.frame = NSRect(x: 24, y: 14, width: 570, height: 42)
        window.contentView?.addSubview(errorLabel)
        generalPage()
        behaviorPage()
        pinnedPage()
        appearancePage()
        shortcutsPage()
        diagnosticsPage()
        tabs.selectTabViewItem(at: 0)
        refresh()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present() {
        refresh()
        window?.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) { onClose?() }

    func showExternalError(_ message: String) {
        refresh()
        errorLabel.stringValue = message
    }

    private func page(_ title: String) -> NSView {
        let item = NSTabViewItem(identifier: title)
        item.label = title
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 420))
        item.view = view
        tabs.addTabViewItem(item)
        return view
    }

    @discardableResult private func label(_ text: String, y: CGFloat, in view: NSView) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.frame = NSRect(x: 20, y: y, width: 520, height: 42)
        field.font = .systemFont(ofSize: 12)
        view.addSubview(field)
        return field
    }

    private func button(_ title: String, action: Selector, x: CGFloat = 20, y: CGFloat, in view: NSView) {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.frame = NSRect(x: x, y: y, width: 200, height: 30)
        view.addSubview(button)
    }

    private func generalPage() {
        let view = page("General")
        startupToggle.target = self
        startupToggle.action = #selector(toggleStartup)
        startupToggle.frame = NSRect(x: 20, y: 364, width: 250, height: 24)
        view.addSubview(startupToggle)
        startupStatus.frame = NSRect(x: 20, y: 306, width: 520, height: 50)
        startupStatus.font = .systemFont(ofSize: 11)
        startupStatus.textColor = .secondaryLabelColor
        view.addSubview(startupStatus)
        button("Install in Applications…", action: #selector(install), y: 270, in: view)
        loginSettings.target = self
        loginSettings.action = #selector(openLoginSettings)
        loginSettings.bezelStyle = .rounded
        loginSettings.frame = NSRect(x: 250, y: 270, width: 220, height: 30)
        view.addSubview(loginSettings)
        label("Windows to show", y: 213, in: view)
        scope.addItems(withTitles: ["All windows", "Only windows on this display"])
        scope.frame = NSRect(x: 245, y: 230, width: 285, height: 28)
        scope.target = self
        scope.action = #selector(changeScope)
        view.addSubview(scope)
        label("Hover previews", y: 162, in: view)
        preview.addItems(withTitles: ["Title and profile", "Window thumbnail"])
        preview.frame = NSRect(x: 245, y: 180, width: 285, height: 28)
        preview.target = self
        preview.action = #selector(changePreview)
        view.addSubview(preview)
        permissionLabel.frame = NSRect(x: 20, y: 90, width: 520, height: 70)
        permissionLabel.font = .systemFont(ofSize: 11)
        permissionLabel.textColor = .secondaryLabelColor
        view.addSubview(permissionLabel)
        button("Enable thumbnail access…", action: #selector(requestCapture), y: 48, in: view)
        label("Appearance and motion follow your macOS settings.", y: 0, in: view).textColor =
            .secondaryLabelColor
    }

    private func behaviorPage() {
        let view = page("Behavior")
        for (button, y) in [
            (searchToggle, 366.0), (minimizedToggle, 336.0),
            (hoverActionsToggle, 224.0), (peekToggle, 194.0), (autoHideToggle, 162.0),
        ] {
            button.frame = NSRect(x: 20, y: y, width: 520, height: 26)
            button.target = self
            button.action = #selector(changeBehavior)
            view.addSubview(button)
        }
        label("Bar position", y: 285, in: view)
        barEdge.addItems(withTitles: ["Bottom (default)", "Left side", "Right side"])
        barEdge.frame = NSRect(x: 220, y: 298, width: 310, height: 28)
        barEdge.target = self
        barEdge.action = #selector(changeBarEdge)
        view.addSubview(barEdge)
        label("Window grouping", y: 251, in: view)
        grouping.addItems(withTitles: ["None — individual windows", "By app", "By app and Chrome profile"])
        grouping.frame = NSRect(x: 220, y: 264, width: 310, height: 28)
        grouping.target = self
        grouping.action = #selector(changeBehavior)
        view.addSubview(grouping)
        label("Hide delay", y: 114, in: view)
        hideDelay.frame = NSRect(x: 160, y: 130, width: 260, height: 24)
        hideDelay.target = self
        hideDelay.action = #selector(changeBehavior)
        view.addSubview(hideDelay)
        hideDelayLabel.frame = NSRect(x: 438, y: 130, width: 90, height: 24)
        view.addSubview(hideDelayLabel)
        label("Unread activity", y: 66, in: view)
        notificationMode.addItems(withTitles: ["Badges + brief pulse", "Badges only", "Off"])
        notificationMode.frame = NSRect(x: 220, y: 82, width: 310, height: 28)
        notificationMode.target = self
        notificationMode.action = #selector(changeBehavior)
        view.addSubview(notificationMode)
        label("Mirrors app Dock badges when available. Reduce Motion uses a steady badge.", y: 12, in: view)
            .textColor = .secondaryLabelColor
    }

    private func pinnedPage() {
        let view = page("Pinned Apps")
        label("Pinned apps position", y: 348, in: view)
        pinnedSide.addItems(withTitles: ["Right (bottom on a side bar)", "Left (default; top on a side bar)"])
        pinnedSide.frame = NSRect(x: 270, y: 364, width: 260, height: 28)
        pinnedSide.target = self
        pinnedSide.action = #selector(changePinnedSide)
        view.addSubview(pinnedSide)
        let scroll = NSScrollView(frame: NSRect(x: 20, y: 78, width: 520, height: 270))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("app"))
        column.title = "Pinned app"
        column.width = 500
        pinnedTable.addTableColumn(column)
        pinnedTable.headerView = nil
        pinnedTable.rowHeight = 32
        pinnedTable.delegate = self
        pinnedTable.dataSource = self
        scroll.documentView = pinnedTable
        view.addSubview(scroll)
        button("Add App…", action: #selector(addApp), y: 34, in: view)
        button("Remove", action: #selector(removeApp), x: 238, y: 34, in: view)
        let up = NSButton(title: "↑", target: self, action: #selector(movePinUp))
        let down = NSButton(title: "↓", target: self, action: #selector(movePinDown))
        up.frame = NSRect(x: 450, y: 34, width: 40, height: 30)
        down.frame = NSRect(x: 500, y: 34, width: 40, height: 30)
        view.addSubview(up)
        view.addSubview(down)
        label("Drag icons on the bar to reorder them. These pins belong to WindowBar.", y: -5, in: view)
            .textColor = .secondaryLabelColor
    }

    private func appearancePage() {
        let view = page("Appearance")
        label("Bar tint", y: 351, in: view)
        barTint.addItems(withTitles: ["Off — frosted glass (default)", "Light accent color", "Strong accent color"])
        barTint.frame = NSRect(x: 220, y: 364, width: 310, height: 28)
        view.addSubview(barTint)
        label("Edge line width", y: 301, in: view)
        edgeLineWidth.addItems(withTitles: BarPreferences.edgeLineWidths.map { "\(Int($0)) pt" })
        edgeLineWidth.frame = NSRect(x: 220, y: 314, width: 310, height: 28)
        view.addSubview(edgeLineWidth)
        edgeAlertToggle.frame = NSRect(x: 20, y: 270, width: 520, height: 26)
        view.addSubview(edgeAlertToggle)
        for control in [barTint, edgeLineWidth, edgeAlertToggle] as [NSControl] {
            control.target = self
            control.action = #selector(changeAppearance)
        }
        label(
            "Colors follow the accent color in System Settings → Appearance. "
                + "The edge line shows while auto-hide hides the bar; it turns red until the bar shows again.",
            y: 200, in: view
        ).textColor = .secondaryLabelColor
    }

    private func shortcutsPage() {
        let view = page("Shortcuts")
        shortcutsToggle.frame = NSRect(x: 20, y: 368, width: 420, height: 24)
        shortcutsToggle.target = self
        shortcutsToggle.action = #selector(toggleShortcuts)
        view.addSubview(shortcutsToggle)
        let scroll = NSScrollView(frame: NSRect(x: 20, y: 62, width: 520, height: 296))
        scroll.hasVerticalScroller = true
        shortcutRows.orientation = .vertical
        shortcutRows.alignment = .leading
        shortcutRows.spacing = 6
        shortcutRows.frame = NSRect(x: 0, y: 0, width: 490, height: 420)
        scroll.documentView = shortcutRows
        view.addSubview(scroll)
        button("Restore defaults", action: #selector(resetShortcuts), y: 20, in: view)
        let footer = label("Click a combination to record it. Escape cancels.", y: 0, in: view)
        footer.frame.size.height = 18
        footer.textColor = .secondaryLabelColor
    }

    private func diagnosticsPage() {
        let view = page("Diagnostics")
        diagnosticsLabel.frame = NSRect(x: 20, y: 160, width: 520, height: 230)
        diagnosticsLabel.font = .systemFont(ofSize: 12)
        view.addSubview(diagnosticsLabel)
        button("Reveal logs", action: #selector(revealLogs), y: 98, in: view)
        button("Export events…", action: #selector(exportEvents), x: 250, y: 98, in: view)
        label(
            "Event logs record lifecycle and failures. They omit window titles, profile names, URLs, and captured images.",
            y: 32, in: view
        ).textColor = .secondaryLabelColor
    }

    func refresh() {
        let value = features.preferences.value
        pinnedSide.selectItem(at: value.pinnedSide == .right ? 0 : 1)
        barEdge.selectItem(at: BarPreferences.BarEdge.allCases.firstIndex(of: value.barEdge) ?? 0)
        barTint.selectItem(at: BarPreferences.BarTint.allCases.firstIndex(of: value.barTint) ?? 0)
        edgeLineWidth.selectItem(at: BarPreferences.edgeLineWidths.firstIndex(of: value.edgeLineWidth) ?? 1)
        edgeAlertToggle.state = value.edgeLineAlertsUnread ? .on : .off
        edgeAlertToggle.isEnabled = value.notificationMode != .off
        peekToggle.state = value.hoverPeekEnabled ? .on : .off
        notificationMode.selectItem(
            at: BarPreferences.NotificationMode.allCases.firstIndex(of: value.notificationMode) ?? 0)
        scope.selectItem(at: value.windowScope == .allDisplays ? 0 : 1)
        preview.selectItem(at: value.previewMode == .titles ? 0 : 1)
        shortcutsToggle.state = value.shortcutsEnabled ? .on : .off
        searchToggle.state = value.searchEnabled ? .on : .off
        minimizedToggle.state = value.searchIncludesMinimized ? .on : .off
        minimizedToggle.isEnabled = value.searchEnabled
        grouping.selectItem(at: BarPreferences.GroupingMode.allCases.firstIndex(of: value.groupingMode) ?? 0)
        hoverActionsToggle.state = value.hoverActionsEnabled ? .on : .off
        autoHideToggle.state = value.autoHideEnabled ? .on : .off
        hideDelay.doubleValue = value.autoHideDelay
        hideDelay.isEnabled = value.autoHideEnabled
        hideDelayLabel.stringValue = String(format: "%.1f seconds", value.autoHideDelay)
        startupToggle.isEnabled = startup.status != .needsInstallation && startup.status != .unavailable
        startupToggle.state =
            startup.status == .enabled ? .on : (startup.status == .requiresApproval ? .mixed : .off)
        switch startup.status {
        case .enabled: startupStatus.stringValue = "WindowBar will open when you sign in."
        case .disabled: startupStatus.stringValue = "WindowBar will open only when you launch it."
        case .requiresApproval:
            startupStatus.stringValue = "Allow WindowBar in System Settings → Login Items."
        case .needsInstallation:
            startupStatus.stringValue =
                "Install in Applications and open the installed copy to enable login startup."
        case .unavailable:
            startupStatus.stringValue = "Login startup is unavailable. Try opening the installed copy again."
        }
        loginSettings.isEnabled = startup.status == .requiresApproval || startup.status == .enabled
        permissionLabel.stringValue =
            CGPreflightScreenCaptureAccess()
            ? "Thumbnail and full-window peek access is available. Minimized or unavailable windows use title previews."
            : "Thumbnails and full-window peeks need Screen Recording access. Title previews work without it. Access is requested only with the button below."
        diagnosticsLabel.stringValue =
            "WindowBar \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development")\n\nAccessibility: \(AXIsProcessTrusted() ? "Available" : "Not granted")\nThumbnail access: \(CGPreflightScreenCaptureAccess() ? "Available" : "Not granted")\n\nLog folder:\n\(logDirectory.path)\n\nAn unexpected exit is recorded on the next launch. Logs rotate automatically."
        pinnedTable.reloadData()
        for view in shortcutRows.arrangedSubviews {
            shortcutRows.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        var bindings = value.shortcuts
        if !bindings.contains(where: { $0.action == .searchWindows }),
            let searchBinding = ShortcutBinding.defaults.first(where: { $0.action == .searchWindows })
        {
            bindings.append(searchBinding)
        }
        for binding in bindings {
            let title =
                binding.action == .nextWindow
                ? "Next window"
                : binding.action == .previousWindow
                    ? "Previous window"
                    : binding.action == .searchWindows
                        ? "Search windows" : "Pinned app \((binding.action.pinnedIndex ?? 0) + 1)"
            let field = NSTextField(labelWithString: title)
            field.frame = NSRect(x: 0, y: 0, width: 220, height: 24)
            let recorder = ShortcutRecorderButton(binding: binding)
            if !value.shortcuts.contains(where: { $0.action == binding.action }) {
                recorder.title = "Set shortcut…"
                recorder.toolTip = "Choose a combination; the default conflicts with an existing shortcut."
            }
            recorder.frame = NSRect(x: 0, y: 0, width: 180, height: 28)
            recorder.onRecord = { [weak self] updated in
                guard let self else { return }
                var value = self.features.preferences.value
                if let index = value.shortcuts.firstIndex(where: { $0.action == updated.action }) {
                    value.shortcuts[index] = updated
                } else {
                    value.shortcuts.append(updated)
                }
                try self.save(value)
            }
            recorder.onError = { [weak self] in self?.failed($0) }
            let row = NSStackView(views: [field, recorder])
            row.orientation = .horizontal
            row.spacing = 45
            row.heightAnchor.constraint(equalToConstant: 30).isActive = true
            shortcutRows.addArrangedSubview(row)
        }
    }

    private func save(_ updated: BarPreferences) throws {
        if let onPreferencesChanged {
            try onPreferencesChanged(updated)
        } else {
            try features.preferences.save(updated)
        }
        errorLabel.stringValue = ""
    }
    private func failed(_ error: Error) {
        errorLabel.stringValue =
            (error as? LocalizedError)?.errorDescription
            ?? "This change could not be saved. Try another setting or shortcut."
        onError?(error)
        refresh()
    }

    @objc func changeBehavior() {
        var value = features.preferences.value
        value.hoverPeekEnabled = peekToggle.state == .on
        value.notificationMode =
            BarPreferences.NotificationMode.allCases[max(0, notificationMode.indexOfSelectedItem)]
        value.searchEnabled = searchToggle.state == .on
        value.searchIncludesMinimized = minimizedToggle.state == .on
        value.groupingMode = BarPreferences.GroupingMode.allCases[max(0, grouping.indexOfSelectedItem)]
        value.hoverActionsEnabled = hoverActionsToggle.state == .on
        value.autoHideEnabled = autoHideToggle.state == .on
        value.autoHideDelay = hideDelay.doubleValue
        do {
            try save(value)
            refresh()
        } catch { failed(error) }
    }

    @objc func changePinnedSide() {
        var value = features.preferences.value
        value.pinnedSide = pinnedSide.indexOfSelectedItem == 1 ? .left : .right
        do { try save(value) } catch { failed(error) }
    }
    @objc func changeAppearance() {
        var value = features.preferences.value
        value.barTint = BarPreferences.BarTint.allCases[max(0, barTint.indexOfSelectedItem)]
        value.edgeLineWidth = BarPreferences.edgeLineWidths[max(0, edgeLineWidth.indexOfSelectedItem)]
        value.edgeLineAlertsUnread = edgeAlertToggle.state == .on
        do { try save(value) } catch { failed(error) }
    }
    @objc func changeBarEdge() {
        var value = features.preferences.value
        value.barEdge = BarPreferences.BarEdge.allCases[max(0, barEdge.indexOfSelectedItem)]
        do { try save(value) } catch { failed(error) }
    }
    @objc func changeScope() {
        var value = features.preferences.value
        value.windowScope = scope.indexOfSelectedItem == 0 ? .allDisplays : .currentDisplay
        do { try save(value) } catch { failed(error) }
    }
    @objc func changePreview() {
        var value = features.preferences.value
        value.previewMode = preview.indexOfSelectedItem == 0 ? .titles : .thumbnails
        do { try save(value) } catch { failed(error) }
    }
    @objc func toggleShortcuts() {
        var value = features.preferences.value
        value.shortcutsEnabled = shortcutsToggle.state == .on
        do { try save(value) } catch { failed(error) }
    }
    @objc func toggleStartup() {
        do {
            try startup.setEnabled(startupToggle.state == .on)
            refresh()
        } catch { failed(error) }
    }
    @objc private func install() {
        do {
            try installer.install(from: Bundle.main.bundleURL)
            Diagnostics.shared.record(.installSucceeded)
            startupStatus.stringValue =
                "Installed in \(installer.destination.deletingLastPathComponent().path). Open that copy when convenient."
        } catch {
            Diagnostics.shared.record(.installFailed)
            failed(error)
        }
    }
    @objc private func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }
    @objc private func requestCapture() {
        _ = CGRequestScreenCaptureAccess()
        refresh()
    }
    @objc private func addApp() {
        let picker = NSOpenPanel()
        picker.canChooseFiles = true
        picker.canChooseDirectories = false
        picker.directoryURL = URL(fileURLWithPath: "/Applications")
        picker.allowedContentTypes = [.applicationBundle]
        guard picker.runModal() == .OK, let url = picker.url else { return }
        do {
            try features.pin(url)
            try save(features.preferences.value)
            refresh()
        } catch { failed(error) }
    }
    @objc private func removeApp() {
        let rows = features.preferences.value.pinnedPaths ?? []
        guard rows.indices.contains(pinnedTable.selectedRow) else { return }
        do {
            try features.unpin(URL(fileURLWithPath: rows[pinnedTable.selectedRow]))
            try save(features.preferences.value)
            refresh()
        } catch { failed(error) }
    }
    @objc private func movePinUp() { movePin(by: -1) }
    @objc private func movePinDown() { movePin(by: 1) }
    private func movePin(by offset: Int) {
        let rows = features.preferences.value.pinnedPaths ?? []
        let source = pinnedTable.selectedRow
        let target = source + offset
        guard rows.indices.contains(source), rows.indices.contains(target) else { return }
        do {
            try features.moveLauncher(rows[source], relativeTo: rows[target], after: offset > 0)
            try save(features.preferences.value)
            refresh()
            pinnedTable.selectRowIndexes(IndexSet(integer: target), byExtendingSelection: false)
        } catch { failed(error) }
    }
    @objc private func resetShortcuts() {
        var value = features.preferences.value
        value.shortcuts = ShortcutBinding.defaults
        do {
            try save(value)
            refresh()
        } catch { failed(error) }
    }
    @objc private func revealLogs() { NSWorkspace.shared.open(logDirectory) }
    @objc private func exportEvents() {
        let picker = NSSavePanel()
        picker.nameFieldStringValue = "WindowBar-events.jsonl"
        guard picker.runModal() == .OK, let url = picker.url else { return }
        do {
            var data = Data()
            for file in ["events.previous.jsonl", "events.jsonl"] {
                if let content = try? Data(contentsOf: logDirectory.appendingPathComponent(file)) {
                    data.append(content)
                }
            }
            try data.write(to: url, options: .atomic)
        } catch { failed(error) }
    }
    func numberOfRows(in tableView: NSTableView) -> Int { features.preferences.value.pinnedPaths?.count ?? 0 }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let paths = features.preferences.value.pinnedPaths ?? []
        guard paths.indices.contains(row) else { return nil }
        let label = NSTextField(
            labelWithString: URL(fileURLWithPath: paths[row]).deletingPathExtension().lastPathComponent)
        label.toolTip = paths[row]
        label.lineBreakMode = .byTruncatingMiddle
        return label
    }
}
