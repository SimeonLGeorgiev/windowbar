import CoreGraphics
import XCTest

@testable import WindowBarCore

final class PinsPeekAttentionTests: XCTestCase {
    func testPinnedSideDefaultsRightAndAllNewPreferencesPersist() throws {
        var preferences = try JSONDecoder().decode(BarPreferences.self, from: Data("{}".utf8))
        XCTAssertEqual(preferences.pinnedSide, .left)
        XCTAssertEqual(preferences.barEdge, .bottom)
        XCTAssertEqual(preferences.barTint, .off)
        XCTAssertEqual(preferences.edgeLineWidth, 6)
        XCTAssertTrue(preferences.edgeLineAlertsUnread)
        XCTAssertTrue(preferences.hoverPeekEnabled)
        XCTAssertEqual(preferences.notificationMode, .badgesAndPulse)
        preferences.pinnedSide = .right
        preferences.barEdge = .right
        preferences.sideCollapsed = true
        preferences.barTint = .strong
        preferences.edgeLineWidth = 8
        preferences.edgeLineAlertsUnread = false
        preferences.hoverPeekEnabled = false
        preferences.notificationMode = .off
        XCTAssertEqual(
            try JSONDecoder().decode(BarPreferences.self, from: JSONEncoder().encode(preferences)),
            preferences)
    }

    func testPinPlacementOnEitherSideWithoutOverlappingWindowRow() {
        for width in [200.0, 600, 1200] {
            for count in [0, 2, 30] {
                for search in [false, true] {
                    let right = ShelfLayout(
                        width: width, pinnedCount: count, searchEnabled: search, side: .right)
                    let left = ShelfLayout(
                        width: width, pinnedCount: count, searchEnabled: search, side: .left)
                    XCTAssertLessThanOrEqual(right.windowX + right.windowWidth, right.launcherX)
                    XCTAssertLessThanOrEqual(left.launcherX + left.launcherWidth, left.windowX)
                    XCTAssertEqual(right.windowWidth, left.windowWidth)
                    XCTAssertGreaterThanOrEqual(left.windowWidth, 0)
                    XCTAssertLessThanOrEqual(left.windowX + left.windowWidth, width - 54)
                }
            }
        }
    }

    func testSideColumnKeepsPinsAndWindowsApartBelowTheHeader() {
        for height in [300.0, 900] {
            for count in [0, 3, 40] {
                let top = ColumnLayout(width: 240, height: height, pinnedCount: count, side: .left)
                let bottom = ColumnLayout(width: 240, height: height, pinnedCount: count, side: .right)
                let header = height - ColumnLayout.headerHeight
                XCTAssertEqual(top.launcherColumns, 5)
                XCTAssertLessThanOrEqual(top.launchers.minY + top.launchers.height, header)
                XCTAssertLessThanOrEqual(top.windows.minY + top.windows.height, top.launchers.minY)
                XCTAssertLessThanOrEqual(bottom.launchers.minY + bottom.launchers.height, bottom.windows.minY)
                XCTAssertLessThanOrEqual(bottom.windows.minY + bottom.windows.height, header)
                XCTAssertEqual(top.windows.height, bottom.windows.height)
                XCTAssertLessThanOrEqual(top.launchers.height, (header - 8) / 3 + 0.001)
            }
        }
        let rows = ColumnLayout.rows(heights: [52, 30, 52], available: 100)
        XCTAssertEqual(rows.offsets, [0, 56, 90])
        XCTAssertEqual(rows.documentHeight, 142)
        XCTAssertEqual(ColumnLayout.rows(heights: [], available: 100).documentHeight, 100)
        let collapsed = ColumnLayout(
            width: ColumnLayout.collapsedWidth, height: 900, pinnedCount: 3, side: .left, collapsed: true)
        XCTAssertEqual(collapsed.launcherColumns, 1)
        XCTAssertLessThanOrEqual(
            collapsed.launchers.minY + collapsed.launchers.height, 900 - ColumnLayout.collapsedHeaderHeight)
    }

    func testRecentWindowSelectionUsesFocusAndDropsClosedWindows() {
        var recency = WindowRecency()
        recency.update(available: ["chrome1", "chrome2", "terminal"], focused: "chrome2")
        recency.update(available: ["chrome1", "chrome2", "terminal"], focused: "terminal")
        XCTAssertEqual(recency.mostRecent(in: ["chrome1", "chrome2"]), "chrome2")
        recency.update(available: ["chrome1", "terminal"], focused: nil)
        XCTAssertEqual(recency.mostRecent(in: ["chrome1"]), "chrome1")
        XCTAssertNil(recency.mostRecent(in: []))
        XCTAssertEqual(recency.identifiers, ["terminal"])
    }

    func testPeekFitsOversizedAndOtherDisplayWindowsWhileLeavingBarAccessible() throws {
        let screen = CGRect(x: -1000, y: -500, width: 1000, height: 800)
        let window = CGRect(x: 2000, y: 0, width: 1800, height: 1200)
        let frame = try XCTUnwrap(PeekLayout.frame(window: window, screen: screen))
        XCTAssertTrue(screen.contains(frame))
        XCTAssertGreaterThanOrEqual(frame.minY, screen.minY + 82)
        XCTAssertEqual(frame.width / frame.height, 1.5, accuracy: 0.001)
        XCTAssertNil(PeekLayout.frame(window: .zero, screen: screen))
        XCTAssertNil(PeekLayout.frame(window: window, screen: .zero))
    }

    func testPointerCanTravelToPeekWithoutMakingWholeDesktopSticky() {
        let source = CGRect(x: 100, y: 8, width: 100, height: 50)
        let preview = CGRect(x: 300, y: 400, width: 400, height: 300)
        XCTAssertTrue(PeekLayout.containsPointer(CGPoint(x: 150, y: 30), source: source, preview: preview))
        XCTAssertTrue(PeekLayout.containsPointer(CGPoint(x: 400, y: 500), source: source, preview: preview))
        XCTAssertFalse(PeekLayout.containsPointer(CGPoint(x: 650, y: 100), source: source, preview: preview))
    }

    func testBadgeParsingRejectsContentAndCapsCounts() {
        XCTAssertEqual(UnreadBadge.parse(" 12 "), .count(12))
        XCTAssertEqual(UnreadBadge.parse("99+"), .count(100))
        XCTAssertEqual(UnreadBadge.parse("100000"), .count(999))
        XCTAssertEqual(UnreadBadge.parse("•"), .dot)
        for value in [nil, "", "0", "-1", "message text", "999999999999999"] {
            XCTAssertNil(UnreadBadge.parse(value))
        }
        XCTAssertEqual(UnreadBadge.count(200).label, "99+")
    }

    func testNewUnreadSignalsPulseButStartupAndUnchangedBadgesDoNot() {
        var attention = AppAttention()
        attention.update(["slack": .count(1)], focusedApp: nil, now: 0)
        XCTAssertFalse(attention.isPulsing("slack", now: 0))
        attention.update(["slack": .count(2)], focusedApp: nil, now: 1)
        XCTAssertTrue(attention.isPulsing("slack", now: 1))
        attention.update(["slack": .count(2)], focusedApp: nil, now: 3)
        XCTAssertFalse(attention.isPulsing("slack", now: 4))
        attention.update(["slack": .dot], focusedApp: nil, now: 5)
        XCTAssertTrue(attention.isPulsing("slack", now: 5))
    }

    func testReadingClearingAndFocusingAppStopPulse() {
        var attention = AppAttention()
        attention.update([:], focusedApp: nil, now: 0)
        attention.update(["slack": .count(3)], focusedApp: nil, now: 1)
        attention.update(["slack": .count(2)], focusedApp: nil, now: 2)
        XCTAssertFalse(attention.isPulsing("slack", now: 2))
        attention.update(["slack": .count(4)], focusedApp: "slack", now: 3)
        XCTAssertFalse(attention.isPulsing("slack", now: 3))
        attention.update([:], focusedApp: nil, now: 4)
        XCTAssertNil(attention.badges["slack"])
    }

    func testEdgeLineWidthIsValidatedAndNewsComparesAgainstBaseline() throws {
        let odd = try JSONDecoder().decode(BarPreferences.self, from: Data(#"{"edgeLineWidth": 40}"#.utf8))
        XCTAssertEqual(odd.edgeLineWidth, 6)
        var invalid = BarPreferences()
        invalid.edgeLineWidth = 5
        XCTAssertThrowsError(try invalid.validate())
        let baseline: [String: UnreadBadge] = ["slack": .count(34)]
        XCTAssertFalse(AppAttention.hasNews(since: baseline, now: ["slack": .count(34)]))
        XCTAssertFalse(AppAttention.hasNews(since: baseline, now: ["slack": .count(30)]))
        XCTAssertTrue(AppAttention.hasNews(since: baseline, now: ["slack": .count(35)]))
        XCTAssertTrue(AppAttention.hasNews(since: baseline, now: ["slack": .count(34), "window:1": .alert]))
    }
}
