import CoreGraphics
import XCTest

@testable import WindowBarCore

final class SimulatorAttentionTests: XCTestCase {
    let screen = CGRect(x: 718, y: 157, width: 402, height: 874)

    func testCenteredTextAndButtonsAreAnAlert() {
        // Captured from a real iOS 26.3 location permission alert.
        let alert = [
            SimulatorAttention.Element(role: "AXStaticText", frame: CGRect(x: 794, y: 428, width: 260, height: 42)),
            .init(role: "AXStaticText", frame: CGRect(x: 794, y: 478, width: 260, height: 78)),
            .init(role: "AXButton", frame: CGRect(x: 780, y: 576, width: 288, height: 48)),
            .init(role: "AXButton", frame: CGRect(x: 780, y: 630, width: 288, height: 48)),
            .init(role: "AXButton", frame: CGRect(x: 780, y: 684, width: 288, height: 48)),
        ]
        XCTAssertTrue(SimulatorAttention.isAlert(alert, content: screen))
    }

    func testHomeScreensAndFullWidthAppScreensAreNotAlerts() {
        let homeIcons = (0..<12).map {
            SimulatorAttention.Element(
                role: "AXButton", frame: CGRect(x: 740 + Double($0 % 4) * 90, y: 200, width: 64, height: 64))
        }
        XCTAssertFalse(SimulatorAttention.isAlert(homeIcons, content: screen))
        let onboarding = [
            SimulatorAttention.Element(role: "AXStaticText", frame: CGRect(x: 734, y: 300, width: 370, height: 40)),
            .init(role: "AXButton", frame: CGRect(x: 734, y: 900, width: 370, height: 50)),
        ]
        XCTAssertFalse(SimulatorAttention.isAlert(onboarding, content: screen))
        let buttonsOnly = [
            SimulatorAttention.Element(role: "AXButton", frame: CGRect(x: 830, y: 500, width: 180, height: 44))
        ]
        XCTAssertFalse(SimulatorAttention.isAlert(buttonsOnly, content: screen))
        let offCenter = [
            SimulatorAttention.Element(role: "AXStaticText", frame: CGRect(x: 730, y: 300, width: 200, height: 40)),
            .init(role: "AXButton", frame: CGRect(x: 730, y: 360, width: 200, height: 44)),
        ]
        XCTAssertFalse(SimulatorAttention.isAlert(offCenter, content: screen))
        XCTAssertFalse(SimulatorAttention.isAlert([], content: screen))
    }

    func testWindowTitleMatchesDeviceAndRuntime() {
        let devices = [
            SimulatorAttention.Device(udid: "A", name: "iPhone 17 Pro", runtime: "iOS 26.3"),
            .init(udid: "B", name: "iPhone 17 Pro", runtime: "iOS 26.5"),
            .init(udid: "C", name: "wsj-validator", runtime: "iOS 26.5"),
        ]
        XCTAssertEqual(SimulatorAttention.device(forWindowTitle: "wsj-validator – iOS 26.5", in: devices)?.udid, "C")
        XCTAssertEqual(SimulatorAttention.device(forWindowTitle: "iPhone 17 Pro – iOS 26.5", in: devices)?.udid, "B")
        XCTAssertNil(SimulatorAttention.device(forWindowTitle: "iPhone 17 Pro Max – iOS 26.3", in: devices))
        XCTAssertNil(SimulatorAttention.device(forWindowTitle: "Simulator", in: devices))
        XCTAssertEqual(SimulatorAttention.runtimeLabel("com.apple.CoreSimulator.SimRuntime.iOS-26-3"), "iOS 26.3")
    }

    func testBadgeTotalsCountsAndAlertTakesPriority() {
        XCTAssertNil(SimulatorAttention.badge(alert: false, appBadges: []))
        XCTAssertEqual(SimulatorAttention.badge(alert: false, appBadges: [.count(3), .count(2)]), .count(5))
        XCTAssertEqual(SimulatorAttention.badge(alert: false, appBadges: [.dot]), .dot)
        XCTAssertEqual(SimulatorAttention.badge(alert: true, appBadges: [.count(3)]), .alert)
        XCTAssertEqual(UnreadBadge.alert.label, "!")
    }
}

final class SessionAttentionTests: XCTestCase {
    func testTitleGlyphsGiveSessionState() {
        XCTAssertEqual(SessionAttention.state(of: "✳ release-fixes — python3 ◂ claude"), .waiting)
        XCTAssertEqual(SessionAttention.state(of: "◑ Window bar — caffeinate ◂ claude"), .working)
        XCTAssertEqual(SessionAttention.state(of: "~/WorkProjects — ✳ snowplow-micro — sourcekit-lsp"), .waiting)
        XCTAssertEqual(SessionAttention.state(of: "~/WorkProjects — ◐ sayso — node"), .working)
        XCTAssertEqual(SessionAttention.state(of: "Check current git remote | app — codex"), .unknown)
    }

    func testOnlyUnviewedWorkToWaitTransitionsPingUntilViewed() {
        var attention = SessionAttention()
        func session(
            _ key: String, _ title: String, viewed: Bool = false, window: String = "w1"
        ) -> SessionAttention.Session {
            .init(key: key, windowID: window, title: title, viewed: viewed)
        }
        XCTAssertEqual(attention.update([session("a", "✳ idle"), session("b", "◐ busy")]), [:])
        XCTAssertEqual(attention.update([session("a", "✳ idle"), session("b", "✳ busy")]), ["w1": 1])
        XCTAssertEqual(attention.update([session("a", "✳ idle"), session("b", "✳ busy")]), ["w1": 1])
        XCTAssertEqual(attention.update([session("a", "✳ idle"), session("b", "✳ busy", viewed: true)]), [:])
        XCTAssertEqual(attention.update([session("b", "◒ busy", viewed: true)]), [:])
        XCTAssertEqual(attention.update([session("b", "✳ busy", viewed: true)]), [:])
        _ = attention.update([session("c", "◐ x", window: "w2"), session("d", "◑ y", window: "w2")])
        let finished = [session("c", "✳ x", window: "w2"), session("d", "✳ y", window: "w2")]
        XCTAssertEqual(attention.update(finished), ["w2": 2])
        XCTAssertEqual(attention.update([]), [:])
    }
}
