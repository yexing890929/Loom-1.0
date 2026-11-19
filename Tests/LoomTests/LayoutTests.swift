import XCTest
@testable import Loom

final class LayoutTests: XCTestCase {
    let screen = CGRect(x: 0, y: 25, width: 1440, height: 875)
    func testHalvesAvoidReservedArea() {
        XCTAssertEqual(Layout.frame(.left, window: .zero, visible: screen), CGRect(x: 0, y: 25, width: 720, height: 875))
        XCTAssertEqual(Layout.frame(.bottom, window: .zero, visible: screen), CGRect(x: 0, y: 462.5, width: 1440, height: 437.5))
        XCTAssertEqual(Layout.frame(.maximize, window: .zero, visible: screen), screen)
    }
    func testCenterPreservesSize() {
        XCTAssertEqual(Layout.frame(.center, window: CGRect(x: 1, y: 1, width: 400, height: 300), visible: screen), CGRect(x: 520, y: 312.5, width: 400, height: 300))
    }
    func testLargestIntersectionWinsAcrossNegativeCoordinates() {
        let screens = [CGRect(x: -1920, y: -200, width: 1920, height: 1080), screen]
        XCTAssertEqual(Layout.screenIndex(for: CGRect(x: -100, y: 100, width: 600, height: 500), screens: screens), 1)
        XCTAssertNil(Layout.screenIndex(for: screen, screens: []))
    }
    func testTransferPreservesProportions() {
        let target = CGRect(x: -2560, y: -300, width: 2560, height: 1400)
        let source = CGRect(x: 0, y: 0, width: 1280, height: 700)
        XCTAssertEqual(Layout.transfer(CGRect(x: 640, y: 0, width: 640, height: 350), from: source, to: target), CGRect(x: -1280, y: -300, width: 1280, height: 700))
    }
    func testDisconnectedScreenAndOversizedWindowsStayReachable() {
        XCTAssertEqual(Layout.fit(CGRect(x: -2000, y: -100, width: 600, height: 400), in: screen).origin, CGPoint(x: 0, y: 25))
        let large = Layout.fit(CGRect(x: 800, y: 700, width: 2000, height: 1200), in: screen)
        XCTAssertEqual(large.origin, screen.origin)
        XCTAssertEqual(large.size, CGSize(width: 2000, height: 1200))
    }
}
