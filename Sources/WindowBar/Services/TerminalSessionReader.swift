import AppKit
import ApplicationServices
import WindowBarCore

/// Per-window badges for Terminal sessions that finished while unattended. Terminal's Dock badge
/// counts bells for the whole app, so window and tab titles locate the session instead.
/// Access only on the scanner queue.
final class TerminalSessionReader {
    static let bundleIdentifier = "com.apple.Terminal"
    private var attention = SessionAttention()

    func read(_ windows: [WindowEntry]) -> [String: UnreadBadge] {
        var sessions: [SessionAttention.Session] = []
        for window in windows where window.appIdentity == Self.bundleIdentifier {
            let tabs = window.minimized ? [] : self.tabs(of: window)
            if tabs.isEmpty {
                sessions.append(
                    .init(key: window.id, windowID: window.id, title: window.title, viewed: window.focused))
            } else {
                for (index, tab) in tabs.enumerated() {
                    sessions.append(
                        .init(
                            key: "\(window.id)#\(index)", windowID: window.id, title: tab.title,
                            viewed: window.focused && tab.selected))
                }
            }
        }
        return attention.update(sessions).reduce(into: [:]) { result, item in
            result["window:" + item.key] = .count(item.value)
        }
    }

    private func tabs(of window: WindowEntry) -> [(title: String, selected: Bool)] {
        guard let element = window.element else { return [] }
        AXUIElementSetMessagingTimeout(element, 0.05)
        guard
            let group = (attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []).first(where: {
                attribute($0, kAXRoleAttribute) as? String == kAXTabGroupRole
            })
        else { return [] }
        return (attribute(group, kAXChildrenAttribute) as? [AXUIElement] ?? []).prefix(64).compactMap { tab in
            guard attribute(tab, kAXSubroleAttribute) as? String == "AXTabButton",
                let title = attribute(tab, kAXTitleAttribute) as? String
            else { return nil }
            return (title, (attribute(tab, kAXValueAttribute) as? NSNumber)?.boolValue == true)
        }
    }
}
