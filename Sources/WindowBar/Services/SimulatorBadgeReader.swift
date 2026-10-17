import AppKit
import ApplicationServices
import SQLite3
import WindowBarCore

/// Per-window badges for iOS Simulator, which never badges its own Dock icon.
/// Reads app badge numbers from each booted device's FrontBoard state and alert presence from
/// Simulator's accessibility bridge. Notification content and on-screen text are never read.
/// Access only on the scanner queue.
final class SimulatorBadgeReader {
    static let bundleIdentifier = "com.apple.iphonesimulator"
    private let devicesDirectory: URL
    private var devices: [SimulatorAttention.Device] = []
    private var devicesReadAt: Date = .distantPast

    init(
        devicesDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Developer/CoreSimulator/Devices")
    ) {
        self.devicesDirectory = devicesDirectory
    }

    func read(_ windows: [WindowEntry]) -> [String: UnreadBadge] {
        let simulatorWindows = windows.filter {
            $0.element != nil && $0.appIdentity == Self.bundleIdentifier
        }
        guard !simulatorWindows.isEmpty else { return [:] }
        refreshDevices()
        var result: [String: UnreadBadge] = [:]
        for window in simulatorWindows {
            let device = SimulatorAttention.device(forWindowTitle: window.title, in: devices)
            if device == nil { devicesReadAt = min(devicesReadAt, Date().addingTimeInterval(-25)) }
            let alert = window.minimized ? false : alertShown(in: window)
            let badges = device.map { appBadges(udid: $0.udid) } ?? []
            if let badge = SimulatorAttention.badge(alert: alert, appBadges: badges) {
                result["window:" + window.id] = badge
            }
        }
        return result
    }

    private func refreshDevices() {
        // Devices boot and shut down rarely; an unmatched title forces an early re-read.
        guard Date().timeIntervalSince(devicesReadAt) > 30 else { return }
        devicesReadAt = Date()
        let folders =
            (try? FileManager.default.contentsOfDirectory(
                at: devicesDirectory, includingPropertiesForKeys: nil)) ?? []
        devices = folders.prefix(256).compactMap { folder in
            guard
                let data = try? Data(contentsOf: folder.appending(path: "device.plist")),
                let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
                    as? [String: Any],
                plist["state"] as? Int == 3,
                let udid = plist["UDID"] as? String, let name = plist["name"] as? String,
                let runtime = plist["runtime"] as? String
            else { return nil }
            return SimulatorAttention.Device(
                udid: udid, name: name, runtime: SimulatorAttention.runtimeLabel(runtime))
        }
    }

    private func alertShown(in window: WindowEntry) -> Bool {
        guard let element = window.element else { return false }
        AXUIElementSetMessagingTimeout(element, 0.05)
        guard
            let content = (attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []).first(where: {
                attribute($0, kAXSubroleAttribute) as? String == "iOSContentGroup"
            }),
            let contentFrame = frame(of: content)
        else { return false }
        let children = attribute(content, kAXChildrenAttribute) as? [AXUIElement] ?? []
        guard children.count <= 10 else { return false }
        let elements = children.compactMap { child -> SimulatorAttention.Element? in
            guard let role = attribute(child, kAXRoleAttribute) as? String, let frame = frame(of: child)
            else { return nil }
            return SimulatorAttention.Element(role: role, frame: frame)
        }
        return elements.count == children.count
            && SimulatorAttention.isAlert(elements, content: contentFrame)
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        guard let value = attribute(element, "AXFrame"), CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var rect = CGRect.zero
        return AXValueGetValue(unsafeBitCast(value, to: AXValue.self), .cgRect, &rect) ? rect : nil
    }

    private func appBadges(udid: String) -> [UnreadBadge] {
        let path = devicesDirectory.appending(path: "\(udid)/data/Library/FrontBoard/applicationState.db").path
        var database: OpaquePointer?
        defer { sqlite3_close(database) }
        guard sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return [] }
        sqlite3_busy_timeout(database, 50)
        let query = """
            SELECT kvs.value FROM kvs JOIN key_tab ON key_tab.id = kvs.key
            WHERE key_tab.key = 'SBApplicationBadgeKey' LIMIT 256
            """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else { return [] }
        var badges: [UnreadBadge] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let bytes = sqlite3_column_blob(statement, 0) else { continue }
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
            let value = try? PropertyListSerialization.propertyList(from: data, format: nil)
            let label = (value as? String) ?? (value as? NSNumber)?.stringValue
            if let badge = UnreadBadge.parse(label) { badges.append(badge) }
        }
        return badges
    }
}
