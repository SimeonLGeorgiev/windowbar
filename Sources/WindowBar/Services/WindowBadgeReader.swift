import WindowBarCore

/// Badges for individual windows whose app has no useful Dock badge. Access only on the scanner queue.
final class WindowBadgeReader {
    private let simulator = SimulatorBadgeReader()
    private let terminal = TerminalSessionReader()

    /// Adds window badges to a complete Dock snapshot; an incomplete snapshot stays nil.
    func read(_ windows: [WindowEntry], adding dock: [String: UnreadBadge]?) -> [String: UnreadBadge]? {
        guard let dock else { return nil }
        return dock.merging(simulator.read(windows)) { app, _ in app }
            .merging(terminal.read(windows)) { app, _ in app }
    }
}
