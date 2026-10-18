import CoreGraphics

/// A maximized desktop window ends beside a visible taskbar, with a small gap.
public struct ReservedWindowArea {
    public let displayID: UInt32
    public let visibleFrame: CGRect
    public let barFrame: CGRect
    public let edge: BarPreferences.BarEdge

    public init(
        displayID: UInt32, visibleFrame: CGRect, barFrame: CGRect, edge: BarPreferences.BarEdge = .bottom
    ) {
        self.displayID = displayID
        self.visibleFrame = visibleFrame
        self.barFrame = barFrame
        self.edge = edge
    }

    public func fittedFrame(for window: CGRect) -> CGRect? {
        // Terminal and other apps size in rows/cells, leaving a small screen-edge gap.
        // Height-only zoom and side-by-side maximized windows need the same clearance.
        guard !window.isEmpty, !window.isInfinite, !window.isNull,
            abs(window.maxY - visibleFrame.maxY) <= 32,
            abs(window.minY - visibleFrame.minY) <= 32,
            window.minX >= visibleFrame.minX - 8, window.maxX <= visibleFrame.maxX + 8,
            !barFrame.isEmpty,
            visibleFrame.intersects(barFrame)
        else { return nil }
        switch edge {
        case .bottom:
            let bottom = barFrame.maxY + 8
            guard bottom > window.minY, window.maxY - bottom >= 200 else { return nil }
            return CGRect(x: window.minX, y: bottom, width: window.width, height: window.maxY - bottom)
        case .left:
            let leading = barFrame.maxX + 8
            guard leading > window.minX, window.maxX - leading >= 200 else { return nil }
            return CGRect(x: leading, y: window.minY, width: window.maxX - leading, height: window.height)
        case .right:
            let trailing = barFrame.minX - 8
            guard trailing < window.maxX, trailing - window.minX >= 200 else { return nil }
            return CGRect(x: window.minX, y: window.minY, width: trailing - window.minX, height: window.height)
        }
    }

    /// Accept a smaller grid-snapped size while keeping the requested top-left corner.
    public static func fits(_ actual: CGRect, within target: CGRect) -> Bool {
        !actual.isEmpty && !actual.isInfinite && !actual.isNull && actual.height >= 200
            && abs(actual.minX - target.minX) <= 2 && abs(actual.maxY - target.maxY) <= 2
            && actual.maxX <= target.maxX + 2 && actual.maxX >= target.maxX - 64
            && actual.minY >= target.minY - 1 && actual.minY <= target.minY + 64
    }

    public static func matches(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = 2) -> Bool {
        guard !lhs.isEmpty, !rhs.isEmpty, !lhs.isInfinite, !rhs.isInfinite,
            !lhs.isNull, !rhs.isNull
        else { return false }
        return abs(lhs.minX - rhs.minX) <= tolerance && abs(lhs.maxX - rhs.maxX) <= tolerance
            && abs(lhs.minY - rhs.minY) <= tolerance && abs(lhs.maxY - rhs.maxY) <= tolerance
    }

    /// Used only for an explicit restore when WindowBar first saw an already-maximized window.
    public static func defaultRestoredFrame(in frame: CGRect) -> CGRect {
        frame.insetBy(dx: frame.width * 0.12, dy: frame.height * 0.12)
    }
}
