import AppKit
import ApplicationServices
import WindowBarCore

struct DesktopWindowState {
    var frame: CGRect
    var fullScreen = false
    var minimized = false
}

protocol DesktopWindowResizing {
    func state(of entry: WindowEntry) -> DesktopWindowState?
    @discardableResult func setFrame(_ frame: CGRect, of entry: WindowEntry) -> Bool
}

struct AccessibilityWindowResizer: DesktopWindowResizing {
    func state(of entry: WindowEntry) -> DesktopWindowState? {
        guard let window = entry.element,
            let position = attribute(window, kAXPositionAttribute),
            let extent = attribute(window, kAXSizeAttribute),
            CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(extent) == AXValueGetTypeID()
        else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(position, to: AXValue.self), .cgPoint, &point),
            AXValueGetValue(unsafeBitCast(extent, to: AXValue.self), .cgSize, &size)
        else { return nil }
        return DesktopWindowState(
            frame: DisplayFilter.cocoaFrame(
                accessibilityFrame: CGRect(origin: point, size: size),
                primaryDisplayTop: CGDisplayBounds(CGMainDisplayID()).height),
            fullScreen: attribute(window, "AXFullScreen") as? Bool ?? false,
            minimized: attribute(window, kAXMinimizedAttribute) as? Bool ?? entry.minimized)
    }

    func setFrame(_ frame: CGRect, of entry: WindowEntry) -> Bool {
        guard let window = entry.element, let current = state(of: entry), !current.fullScreen else {
            return false
        }
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &settable) == .success,
            settable.boolValue
        else { return false }
        let top = CGDisplayBounds(CGMainDisplayID()).height
        var position = CGPoint(x: frame.minX, y: top - frame.maxY)
        var size = frame.size
        let moves = abs(frame.minX - current.frame.minX) > 1 || abs(frame.maxY - current.frame.maxY) > 1
        if moves {
            guard
                AXUIElementIsAttributeSettable(window, kAXPositionAttribute as CFString, &settable)
                    == .success, settable.boolValue
            else { return false }
        }
        guard let sizeValue = AXValueCreate(.cgSize, &size),
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue) == .success
        else { return false }
        if moves, let pointValue = AXValueCreate(.cgPoint, &position) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, pointValue)
        }
        let shrinksHeight =
            frame.height < current.frame.height
            && abs(frame.width - current.frame.width) <= 2 && !moves
        // Some apps round heights up to the next text row. Retry slightly smaller
        // rather than accepting a row that still covers the taskbar.
        if shrinksHeight, let actual = state(of: entry), actual.frame.minY < frame.minY - 1 {
            var smaller = frame.size
            smaller.height -= actual.frame.height - frame.height + 2
            if smaller.height >= 200, let value = AXValueCreate(.cgSize, &smaller) {
                AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
            }
        }
        guard let actual = state(of: entry),
            ReservedWindowArea.matches(actual.frame, frame)
                || ((frame.height < current.frame.height || frame.width < current.frame.width)
                    && ReservedWindowArea.fits(actual.frame, within: frame))
        else {
            // A size constraint or partial write must not leave an unintended move behind.
            var oldSize = current.frame.size
            var oldPoint = CGPoint(x: current.frame.minX, y: top - current.frame.maxY)
            if moves, let value = AXValueCreate(.cgPoint, &oldPoint) {
                AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
            }
            if let value = AXValueCreate(.cgSize, &oldSize) {
                AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
            }
            return false
        }
        return true
    }
}

/// Access only on the work-area queue. Re-read live frames before every write.
final class WindowWorkAreaController {
    private struct Managed {
        let entry: WindowEntry
        let original: CGRect
        var applied: CGRect
        let displayID: UInt32
        let restoreFrame: CGRect
        let appliedAt: TimeInterval
    }
    private let backend: DesktopWindowResizing
    private var managed: [String: Managed] = [:]
    private var normalFrames: [String: CGRect] = [:]
    private var restoreRequests: [String: TimeInterval] = [:]
    private var stopped = false

    init(backend: DesktopWindowResizing = AccessibilityWindowResizer()) { self.backend = backend }

    func requestRestore(id: String, pointer: CGPoint, now: TimeInterval) {
        guard !stopped, let record = managed[id],
            // A zoom may be fitted before its mouse-up reaches the global monitor.
            // Only a later double-click can request restoration.
            now - record.appliedAt >= 0.1,
            CGRect(
                x: record.applied.minX, y: record.applied.maxY - 44,
                width: record.applied.width, height: 44
            ).contains(pointer)
        else { return }
        restoreRequests[id] = now
    }

    func update(
        entries: [WindowEntry], areas: [ReservedWindowArea], mouseDown: Bool = false,
        now: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        guard !stopped, !mouseDown else { return }
        let available = Set(entries.map(\.id))
        managed = managed.filter { available.contains($0.key) }
        normalFrames = normalFrames.filter { available.contains($0.key) }
        restoreRequests = restoreRequests.filter { available.contains($0.key) && now - $0.value <= 3 }
        for entry in entries {
            // Avoid extra AX traffic for ordinary windows unless a managed frame needs restoring.
            let candidate = areas.first { $0.fittedFrame(for: entry.frame ?? .zero) != nil }
            guard managed[entry.id] != nil || candidate != nil else {
                if let frame = entry.frame, !entry.minimized, !areas.isEmpty {
                    normalFrames[entry.id] = frame
                }
                continue
            }
            guard let state = backend.state(of: entry), !state.minimized else { continue }
            guard !state.fullScreen else {
                managed.removeValue(forKey: entry.id)
                restoreRequests.removeValue(forKey: entry.id)
                continue
            }
            if let record = managed[entry.id] {
                // Terminal can keep a grid-snapped zoom frame after AX resizing.
                // An explicit second titlebar double-click still means restore.
                if restoreRequests[entry.id] != nil {
                    if backend.setFrame(record.restoreFrame, of: entry) {
                        managed.removeValue(forKey: entry.id)
                        restoreRequests.removeValue(forKey: entry.id)
                        normalFrames[entry.id] = record.restoreFrame
                    }
                    continue
                }
                if ReservedWindowArea.matches(state.frame, record.applied) {
                    let target = areas.first { $0.displayID == record.displayID }?
                        .fittedFrame(for: record.original)
                    if let target {
                        if !ReservedWindowArea.fits(state.frame, within: target),
                            backend.setFrame(target, of: entry)
                        {
                            managed[entry.id]?.applied = backend.state(of: entry)?.frame ?? target
                        }
                    } else if backend.setFrame(record.original, of: entry) {
                        managed.removeValue(forKey: entry.id)
                    }
                    continue
                }
                // A manual move/resize owns the frame from here on.
                managed.removeValue(forKey: entry.id)
            }
            guard let area = areas.first(where: { $0.fittedFrame(for: state.frame) != nil }),
                let target = area.fittedFrame(for: state.frame)
            else {
                normalFrames[entry.id] = state.frame
                continue
            }
            let knownNormal = normalFrames[entry.id].flatMap { frame in
                area.visibleFrame.contains(frame)
                    && area.fittedFrame(for: frame) == nil ? frame : nil
            }
            let restored = knownNormal ?? ReservedWindowArea.defaultRestoredFrame(in: target)
            if backend.setFrame(target, of: entry) {
                managed[entry.id] = Managed(
                    entry: entry, original: state.frame,
                    applied: backend.state(of: entry)?.frame ?? target, displayID: area.displayID,
                    restoreFrame: restored, appliedAt: now)
            }
        }
    }

    func restoreAll() {
        for (id, record) in managed {
            guard let state = backend.state(of: record.entry) else { continue }
            if state.fullScreen || !ReservedWindowArea.matches(state.frame, record.applied)
                || backend.setFrame(record.original, of: record.entry)
            {
                managed.removeValue(forKey: id)
            }
        }
        restoreRequests = [:]
    }

    func stop() {
        stopped = true
        restoreAll()
    }
}
