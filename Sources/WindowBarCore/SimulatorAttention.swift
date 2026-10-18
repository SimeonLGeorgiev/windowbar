import CoreGraphics
import Foundation

/// Pure rules for iOS Simulator window badges. Only roles, frames and badge numbers are used, never on-screen text.
public enum SimulatorAttention {
    public struct Element: Equatable {
        public let role: String
        public let frame: CGRect
        public init(role: String, frame: CGRect) {
            self.role = role
            self.frame = frame
        }
    }

    public struct Device: Equatable {
        public let udid: String
        public let name: String
        /// For example "iOS 26.3", as Simulator shows it in the window title.
        public let runtime: String
        public init(udid: String, name: String, runtime: String) {
            self.udid = udid
            self.name = name
            self.runtime = runtime
        }
    }

    /// While a system alert is up, Simulator exposes only that alert: a few texts and buttons
    /// in a centered card narrower than the screen. Full-width app screens never match.
    public static func isAlert(_ elements: [Element], content: CGRect) -> Bool {
        guard !elements.isEmpty, elements.count <= 10, content.width > 0,
            elements.allSatisfy({ $0.role == "AXStaticText" || $0.role == "AXButton" }),
            elements.contains(where: { $0.role == "AXButton" }),
            elements.contains(where: { $0.role == "AXStaticText" })
        else { return false }
        let union = elements.reduce(CGRect.null) { $0.union($1.frame) }
        return union.width <= content.width * 0.8
            && abs(union.midX - content.midX) <= content.width * 0.05
    }

    /// "iPhone 17 Pro – iOS 26.3" names the device and its runtime.
    public static func device(forWindowTitle title: String, in devices: [Device]) -> Device? {
        let named = devices.filter { title == $0.name || title.hasPrefix($0.name + " – ") }
        guard named.count > 1 else { return named.first }
        return named.first { title == "\($0.name) – \($0.runtime)" }
    }

    /// "com.apple.CoreSimulator.SimRuntime.iOS-26-3" → "iOS 26.3".
    public static func runtimeLabel(_ identifier: String) -> String {
        guard let last = identifier.split(separator: ".").last else { return identifier }
        let parts = last.split(separator: "-")
        guard let platform = parts.first, parts.count > 1 else { return String(last) }
        return "\(platform) " + parts.dropFirst().joined(separator: ".")
    }

    /// An alert outranks counts: it blocks the device until someone answers it.
    public static func badge(alert: Bool, appBadges: [UnreadBadge]) -> UnreadBadge? {
        if alert { return .alert }
        let total = appBadges.reduce(0) { sum, badge in
            if case .count(let count) = badge { return sum + count }
            return sum
        }
        if total > 0 { return .count(min(total, 999)) }
        return appBadges.isEmpty ? nil : .dot
    }
}
