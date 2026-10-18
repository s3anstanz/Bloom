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

final class FlowerTabsTests: XCTestCase {
    private func tab(_ x: CGFloat, _ y: CGFloat) -> Mode? {
        FlowerTabs.mode(at: CGPoint(x: x, y: y), tabWidth: 96, height: 30)
    }

    func testTabsRunConvertToolsActionsFromLeftToRight() {
        XCTAssertEqual(tab(-96, 0), .convert)
        XCTAssertEqual(tab(0, 0), .tools)
        XCTAssertEqual(tab(96, 0), .actions)
    }

    func testEachTabCoversItsWholeWidth() {
        XCTAssertEqual(tab(-143, 14), .convert)
        XCTAssertEqual(tab(-47, -14), .tools)
        XCTAssertEqual(tab(47, 14), .tools)
        XCTAssertEqual(tab(143, -14), .actions)
    }

    func testOffTheRowPicksNoTab() {
        XCTAssertNil(tab(0, 16))
        XCTAssertNil(tab(0, -16))
        XCTAssertNil(tab(-145, 0))
        XCTAssertNil(tab(145, 0))
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

    func testTappingTheOpenFlowersKeyAgainReportsItAgain() {
        var taps = KeyTaps(heldAtDragStart: [])
        XCTAssertEqual(taps.update(held: [.shift]), .convert)
        XCTAssertNil(taps.update(held: []))
        XCTAssertEqual(taps.update(held: [.shift]), .convert)
    }

    func testNoKeyNoFlower() {
        var taps = KeyTaps(heldAtDragStart: [])
        XCTAssertNil(taps.update(held: []))
        XCTAssertFalse(taps.isOpen)
    }
}
