import Foundation

public enum UnreadBadge: Equatable {
    case count(Int)
    case dot
    /// A Simulator device is showing a system alert that waits for input.
    case alert

    public static func parse(_ label: String?) -> UnreadBadge? {
        guard let text = label?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        if ["•", "●", "!", "◦"].contains(text) { return .dot }
        let digits = text.hasSuffix("+") ? String(text.dropLast()) : text
        guard !digits.isEmpty, digits.count <= 9, digits.allSatisfy({ $0.isASCII && $0.isNumber }),
            let count = Int(digits), count > 0
        else { return nil }
        return .count(min(text.hasSuffix("+") ? max(100, count) : count, 999))
    }

    public var label: String {
        switch self {
        case .dot: return "•"
        case .alert: return "!"
        case .count(let count): return count > 99 ? "99+" : String(count)
        }
    }
}

public struct AppAttention {
    public private(set) var badges: [String: UnreadBadge] = [:]
    private var initialized = false
    private var pulseUntil: [String: TimeInterval] = [:]
    public init() {}

    public mutating func update(_ snapshot: [String: UnreadBadge], focusedApp: String?, now: TimeInterval) {
        pulseUntil = pulseUntil.filter { $0.value > now && snapshot[$0.key] != nil }
        for (app, badge) in snapshot {
            let old = badges[app]
            if app == focusedApp {
                pulseUntil.removeValue(forKey: app)
                continue
            }
            let increased: Bool
            switch (old, badge) {
            case (.none, _): increased = true
            case (.some(.count(let previous)), .count(let current)): increased = current > previous
            default: increased = old != badge
            }
            if initialized && increased {
                pulseUntil[app] = now + 3
            } else if old != badge {
                pulseUntil.removeValue(forKey: app)
            }
        }
        badges = snapshot
        initialized = true
    }

    public func isPulsing(_ app: String, now: TimeInterval) -> Bool { (pulseUntil[app] ?? 0) > now }
}
