import Foundation

/// Claude Code titles its terminal with a spinner glyph while it works and "✳" while it waits.
/// A session that stops working while nobody is looking at it needs attention until it is viewed.
public struct SessionAttention {
    public enum State: Equatable { case working, waiting, unknown }

    public struct Session: Equatable {
        /// Stable per window, plus the tab position for multi-tab windows.
        public let key: String
        public let windowID: String
        public let title: String
        public let viewed: Bool
        public init(key: String, windowID: String, title: String, viewed: Bool) {
            self.key = key
            self.windowID = windowID
            self.title = title
            self.viewed = viewed
        }
    }

    private static let spinners: Set<Character> = ["◐", "◓", "◑", "◒", "·", "✢", "✶", "✻", "✽"]
    private var states: [String: State] = [:]
    private var pending = Set<String>()
    public init() {}

    /// Terminal titles join parts with " — "; the session name is the part with the glyph.
    public static func state(of title: String) -> State {
        for part in title.components(separatedBy: " — ") {
            guard let first = part.trimmingCharacters(in: .whitespaces).first else { continue }
            if first == "✳" { return .waiting }
            if spinners.contains(first) || ("\u{2800}"..."\u{28FF}").contains(first) { return .working }
        }
        return .unknown
    }

    /// Returns the number of sessions waiting for attention in each window.
    public mutating func update(_ sessions: [Session]) -> [String: Int] {
        var seen: [String: State] = [:]
        for session in sessions {
            let state = Self.state(of: session.title)
            seen[session.key] = state
            if session.viewed || state == .working || state == .unknown {
                pending.remove(session.key)
            } else if states[session.key] == .working {
                pending.insert(session.key)
            }
        }
        states = seen
        pending.formIntersection(seen.keys)
        var counts: [String: Int] = [:]
        for session in sessions where pending.contains(session.key) {
            counts[session.windowID, default: 0] += 1
        }
        return counts
    }
}
