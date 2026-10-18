import CoreGraphics
import XCTest

@testable import WindowBarCore

final class ReservedWindowAreaTests: XCTestCase {
    let visible = CGRect(x: 0, y: 0, width: 2560, height: 1410)

    func testMaximizedWindowEndsAboveBarWithoutMovingItsTopOrSides() throws {
        let area = ReservedWindowArea(
            displayID: 1, visibleFrame: visible,
            barFrame: CGRect(x: 12, y: 8, width: 2536, height: 66))
        let frame = try XCTUnwrap(area.fittedFrame(for: visible))
        XCTAssertEqual(frame.minY, 82)
        XCTAssertEqual(frame.maxY, visible.maxY)
        XCTAssertEqual(frame.minX, visible.minX)
        XCTAssertEqual(frame.width, visible.width)
        XCTAssertEqual(frame.height, 1328)
    }

    func testOrdinaryAndAlreadyFittedWindowsStayUnchanged() {
        let area = ReservedWindowArea(
            displayID: 1, visibleFrame: visible,
            barFrame: CGRect(x: 12, y: 8, width: 2536, height: 66))
        for frame in [
            CGRect(x: 100, y: 150, width: 1000, height: 700),
            CGRect(x: 0, y: 82, width: 2560, height: 1328),
        ] {
            XCTAssertNil(area.fittedFrame(for: frame))
        }
    }

    func testHeightOnlyAndGridSnappedMaximizeReserveSpace() throws {
        let area = ReservedWindowArea(
            displayID: 1, visibleFrame: visible,
            barFrame: CGRect(x: 12, y: 8, width: 2536, height: 66))
        let terminal = CGRect(x: 0, y: 11, width: 2560, height: 1399)
        XCTAssertEqual(try XCTUnwrap(area.fittedFrame(for: terminal)).minY, 82)
        let vertical = CGRect(x: 200, y: 11, width: 1000, height: 1399)
        let target = try XCTUnwrap(area.fittedFrame(for: vertical))
        XCTAssertEqual(target.minX, 200)
        XCTAssertEqual(target.width, 1000)
        let snapped = CGRect(x: 200, y: 89, width: 1000, height: 1321)
        XCTAssertTrue(ReservedWindowArea.fits(snapped, within: target))
        XCTAssertFalse(
            ReservedWindowArea.fits(CGRect(x: 200, y: 70, width: 1000, height: 1340), within: target))
        XCTAssertFalse(ReservedWindowArea.fits(snapped.offsetBy(dx: 20, dy: 0), within: target))
    }

    func testNegativeDisplayCoordinatesAndExistingDockSpace() throws {
        let screen = CGRect(x: -1920, y: -900, width: 1920, height: 950)
        let area = ReservedWindowArea(
            displayID: 2, visibleFrame: screen,
            barFrame: CGRect(x: -1908, y: -892, width: 1896, height: 66))
        let frame = try XCTUnwrap(area.fittedFrame(for: screen))
        XCTAssertEqual(frame.minY, -818)
        XCTAssertEqual(frame.maxY, 50)
        XCTAssertEqual(frame.minX, -1920)
        let dockArea = ReservedWindowArea(
            displayID: 1, visibleFrame: CGRect(x: 0, y: 80, width: 1440, height: 790),
            barFrame: CGRect(x: 12, y: 88, width: 1416, height: 66))
        XCTAssertEqual(dockArea.fittedFrame(for: dockArea.visibleFrame)?.minY, 162)
    }

    func testInvalidFramesAndInsufficientRoomDoNotResize() {
        let area = ReservedWindowArea(
            displayID: 1, visibleFrame: CGRect(x: 0, y: 0, width: 500, height: 200),
            barFrame: CGRect(x: 12, y: 8, width: 476, height: 66))
        XCTAssertNil(area.fittedFrame(for: area.visibleFrame))
        XCTAssertNil(area.fittedFrame(for: .null))
        XCTAssertNil(area.fittedFrame(for: .infinite))
        XCTAssertNil(area.fittedFrame(for: .zero))
        XCTAssertFalse(ReservedWindowArea.matches(.zero, .zero))
    }

    func testScreenWithoutTaskbarAndUnrelatedDisplayHaveNoReservation() {
        let area = ReservedWindowArea(displayID: 1, visibleFrame: visible, barFrame: .zero)
        XCTAssertNil(area.fittedFrame(for: visible))
        let other = ReservedWindowArea(
            displayID: 2, visibleFrame: CGRect(x: 2560, y: 0, width: 1728, height: 1085),
            barFrame: CGRect(x: 2572, y: 8, width: 1704, height: 66))
        XCTAssertNil(other.fittedFrame(for: visible))
    }

    func testSideBarsNarrowMaximizedWindowsInsteadOfShorteningThem() throws {
        let left = ReservedWindowArea(
            displayID: 1, visibleFrame: visible, barFrame: CGRect(x: 8, y: 8, width: 240, height: 1394),
            edge: .left)
        let leftFrame = try XCTUnwrap(left.fittedFrame(for: visible))
        XCTAssertEqual(leftFrame, CGRect(x: 256, y: 0, width: 2304, height: 1410))
        XCTAssertNil(left.fittedFrame(for: leftFrame))
        let right = ReservedWindowArea(
            displayID: 1, visibleFrame: visible, barFrame: CGRect(x: 2312, y: 8, width: 240, height: 1394),
            edge: .right)
        let rightFrame = try XCTUnwrap(right.fittedFrame(for: visible))
        XCTAssertEqual(rightFrame, CGRect(x: 0, y: 0, width: 2304, height: 1410))
        XCTAssertNil(right.fittedFrame(for: rightFrame))
        XCTAssertNil(right.fittedFrame(for: CGRect(x: 0, y: 0, width: 1280, height: 1410)))
        let gridSnapped = CGRect(x: 0, y: 0, width: 2290, height: 1410)
        XCTAssertTrue(ReservedWindowArea.fits(gridSnapped, within: rightFrame))
        XCTAssertFalse(
            ReservedWindowArea.fits(CGRect(x: 0, y: 0, width: 2310, height: 1410), within: rightFrame))
    }
}
