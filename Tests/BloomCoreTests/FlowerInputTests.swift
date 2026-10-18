import BloomCore
import XCTest

final class PetalLayoutTests: XCTestCase {
    private func petal(_ x: CGFloat, _ y: CGFloat, count: Int = 4) -> Int? {
        PetalLayout.index(at: CGPoint(x: x, y: y), count: count, innerRadius: 50, outerRadius: 150)
    }

    func testFirstPetalIsAtTwelveOClockAndTheRestGoClockwise() {
        XCTAssertEqual(petal(0, 100), 0)
        XCTAssertEqual(petal(100, 0), 1)
        XCTAssertEqual(petal(0, -100), 2)
        XCTAssertEqual(petal(-100, 0), 3)
    }

    func testJustLeftOfTwelveOClockStillPicksTheFirstPetal() {
        XCTAssertEqual(petal(-10, 100), 0)
    }

    func testCenterAndOutsideTheFlowerPickNothing() {
        XCTAssertNil(petal(0, 20))
        XCTAssertNil(petal(0, 200))
        XCTAssertNil(petal(0, 100, count: 0))
    }
}

final class KeyTapsTests: XCTestCase {
    func testShiftHeldWhenTheDragStartsOpensConvert() {
        var taps = KeyTaps(heldAtDragStart: [.shift])
        XCTAssertEqual(taps.update(held: [.shift]), .convert)
    }

    func testCommandHeldWhenTheDragStartsMustBePressedAgain() {
        var taps = KeyTaps(heldAtDragStart: [.command])
        XCTAssertNil(taps.update(held: [.command]))
        XCTAssertNil(taps.update(held: []))
        XCTAssertEqual(taps.update(held: [.command]), .tools)
    }

    func testReleasingTheKeyKeepsTheFlowerOpen() {
        var taps = KeyTaps(heldAtDragStart: [])
        XCTAssertEqual(taps.update(held: [.shift]), .convert)
        XCTAssertNil(taps.update(held: []))
        XCTAssertTrue(taps.isOpen)
    }

    func testTappingAnotherKeySwitchesFlowers() {
        var taps = KeyTaps(heldAtDragStart: [])
        XCTAssertEqual(taps.update(held: [.shift]), .convert)
        XCTAssertEqual(taps.update(held: [.shift, .control]), .actions)
        XCTAssertEqual(taps.update(held: [.command]), .tools)
    }

    func testNoKeyNoFlower() {
        var taps = KeyTaps(heldAtDragStart: [])
        XCTAssertNil(taps.update(held: []))
        XCTAssertFalse(taps.isOpen)
    }
}
