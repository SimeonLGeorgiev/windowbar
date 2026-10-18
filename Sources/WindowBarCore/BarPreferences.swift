import Foundation

public struct BarPreferences: Equatable, Codable {
    public enum WindowScope: String, CaseIterable, Codable { case allDisplays, currentDisplay }
    public enum PreviewMode: String, CaseIterable, Codable { case titles, thumbnails }
    public enum GroupingMode: String, CaseIterable, Codable { case none, app, appAndProfile }
    public enum PinnedSide: String, CaseIterable, Codable { case right, left }
    public enum BarEdge: String, CaseIterable, Codable { case bottom, left, right }
    public enum BarTint: String, CaseIterable, Codable { case off, light, strong }
    public enum NotificationMode: String, CaseIterable, Codable { case badgesAndPulse, badgesOnly, off }

    public var windowScope: WindowScope = .allDisplays
    public var previewMode: PreviewMode = .titles
    public var searchEnabled = true
    public var searchIncludesMinimized = true
    public var groupingMode: GroupingMode = .none
    public var hoverActionsEnabled = true
    public var pinnedSide: PinnedSide = .left
    public var barEdge: BarEdge = .bottom
    public var sideCollapsed = false
    public var barTint: BarTint = .off
    public static let edgeLineWidths: [Double] = [4, 6, 8]
    public var edgeLineWidth: Double = 6
    public var edgeLineAlertsUnread = true
    public var hoverPeekEnabled = true
    public var notificationMode: NotificationMode = .badgesAndPulse
    public var autoHideEnabled = false
    public var autoHideDelay: Double = 0.8
    public var shortcutsEnabled = false
    public var shortcuts = ShortcutBinding.defaults
    /// nil imports the existing Dock once; [] intentionally shows no pinned apps.
    public var pinnedPaths: [String]?

    public init() {}

    public var activeShortcuts: [ShortcutBinding] {
        shortcutsEnabled ? shortcuts.filter { searchEnabled || $0.action != .searchWindows } : []
    }

    public enum ValidationError: Error { case invalidHideDelay, invalidEdgeLineWidth }
    public func validate() throws {
        try ShortcutBinding.validate(shortcuts)
        guard autoHideDelay.isFinite, (0.2...3).contains(autoHideDelay) else {
            throw ValidationError.invalidHideDelay
        }
        guard Self.edgeLineWidths.contains(edgeLineWidth) else { throw ValidationError.invalidEdgeLineWidth }
    }

    private enum CodingKeys: String, CodingKey {
        case windowScope, previewMode, shortcutsEnabled, shortcuts, pinnedPaths
        case searchEnabled, searchIncludesMinimized, groupingMode, hoverActionsEnabled, autoHideEnabled,
            autoHideDelay
        case pinnedSide, barEdge, sideCollapsed, hoverPeekEnabled, notificationMode
        case barTint, edgeLineWidth, edgeLineAlertsUnread
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        windowScope = try values.decodeIfPresent(WindowScope.self, forKey: .windowScope) ?? .allDisplays
        previewMode = try values.decodeIfPresent(PreviewMode.self, forKey: .previewMode) ?? .titles
        shortcutsEnabled = try values.decodeIfPresent(Bool.self, forKey: .shortcutsEnabled) ?? false
        shortcuts =
            try values.decodeIfPresent([ShortcutBinding].self, forKey: .shortcuts) ?? ShortcutBinding.defaults
        pinnedPaths = try values.decodeIfPresent([String].self, forKey: .pinnedPaths)
        searchEnabled = try values.decodeIfPresent(Bool.self, forKey: .searchEnabled) ?? true
        searchIncludesMinimized =
            try values.decodeIfPresent(Bool.self, forKey: .searchIncludesMinimized) ?? true
        groupingMode = try values.decodeIfPresent(GroupingMode.self, forKey: .groupingMode) ?? .none
        hoverActionsEnabled = try values.decodeIfPresent(Bool.self, forKey: .hoverActionsEnabled) ?? true
        pinnedSide = try values.decodeIfPresent(PinnedSide.self, forKey: .pinnedSide) ?? .left
        barEdge = try values.decodeIfPresent(BarEdge.self, forKey: .barEdge) ?? .bottom
        sideCollapsed = try values.decodeIfPresent(Bool.self, forKey: .sideCollapsed) ?? false
        barTint = try values.decodeIfPresent(BarTint.self, forKey: .barTint) ?? .off
        let lineWidth = try values.decodeIfPresent(Double.self, forKey: .edgeLineWidth) ?? 6
        edgeLineWidth = Self.edgeLineWidths.contains(lineWidth) ? lineWidth : 6
        edgeLineAlertsUnread = try values.decodeIfPresent(Bool.self, forKey: .edgeLineAlertsUnread) ?? true
        hoverPeekEnabled = try values.decodeIfPresent(Bool.self, forKey: .hoverPeekEnabled) ?? true
        notificationMode =
            try values.decodeIfPresent(NotificationMode.self, forKey: .notificationMode) ?? .badgesAndPulse
        autoHideEnabled = try values.decodeIfPresent(Bool.self, forKey: .autoHideEnabled) ?? false
        let delay = try values.decodeIfPresent(Double.self, forKey: .autoHideDelay) ?? 0.8
        autoHideDelay = delay.isFinite ? min(3, max(0.2, delay)) : 0.8
        // Add the new action without taking a previously customized combination.
        if !shortcuts.contains(where: { $0.action == .searchWindows }),
            let search = ShortcutBinding.defaults.first(where: { $0.action == .searchWindows }),
            !shortcuts.contains(where: { $0.keyCode == search.keyCode && $0.modifiers == search.modifiers })
        {
            shortcuts.append(search)
        }
    }
}
