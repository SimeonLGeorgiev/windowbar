import CoreGraphics

/// Geometry for a bar docked to the left or right screen edge, in AppKit coordinates (origin bottom-left).
public struct ColumnLayout {
    public static let width: Double = 240
    public static let collapsedWidth: Double = 64
    public static let headerHeight: Double = 44
    /// Collapsed, the toggle, search and menu buttons stack instead of sharing one row.
    public static let collapsedHeaderHeight: Double = 112
    public static let launcherPitch: Double = 38
    public static let groupRowHeight: Double = 30
    public static let rowGap: Double = 4

    public let launcherColumns: Int
    public let launchers: CGRect
    public let windows: CGRect
    public let dividerY: Double

    public init(
        width: Double, height: Double, pinnedCount: Int, side: BarPreferences.PinnedSide, collapsed: Bool = false
    ) {
        let inset: Double = 12
        let innerWidth = max(0, width - inset * 2)
        let top = max(0, height - (collapsed ? Self.collapsedHeaderHeight : Self.headerHeight))
        let bottom: Double = 8
        launcherColumns = max(1, Int((innerWidth + 6) / Self.launcherPitch))
        let rows = (max(0, pinnedCount) + launcherColumns - 1) / launcherColumns
        // Pins never take more than a third of the column; the rest scrolls.
        let launcherHeight = min(Double(rows) * Self.launcherPitch, max(0, top - bottom) / 3)
        let gap: Double = pinnedCount > 0 ? 12 : 0
        let windowHeight = max(0, top - bottom - launcherHeight - gap)
        switch side {
        case .left:
            launchers = CGRect(x: inset, y: top - launcherHeight, width: innerWidth, height: launcherHeight)
            windows = CGRect(x: 8, y: bottom, width: max(0, width - 16), height: windowHeight)
            dividerY = top - launcherHeight - gap / 2
        case .right:
            launchers = CGRect(x: inset, y: bottom, width: innerWidth, height: launcherHeight)
            windows = CGRect(
                x: 8, y: bottom + launcherHeight + gap, width: max(0, width - 16), height: windowHeight)
            dividerY = bottom + launcherHeight + gap / 2
        }
    }

    /// Offsets from the top of a flipped document, followed by the document height.
    public static func rows(heights: [Double], available: Double) -> (offsets: [Double], documentHeight: Double) {
        var next: Double = 0
        let offsets = heights.map { height -> Double in
            defer { next += height + rowGap }
            return next
        }
        return (offsets, max(available, heights.isEmpty ? 0 : next - rowGap))
    }
}
