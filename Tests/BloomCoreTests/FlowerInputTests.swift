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

    func testOutlineReachesFromItsBaseToItsTipInItsDirection() {
        let center = CGPoint(x: 12, y: 12)
        let up = PetalLayout.outline(center: center, angle: 0, width: 6, inner: 4, outer: 11)
        XCTAssertTrue(up.contains(CGPoint(x: 12, y: 4.5)))
        XCTAssertTrue(up.contains(CGPoint(x: 12, y: 1.5)))
        XCTAssertFalse(up.contains(center))
        XCTAssertFalse(up.contains(CGPoint(x: 12, y: 20)))
        XCTAssertEqual(up.boundingBoxOfPath.midX, 12, accuracy: 0.001)

        let right = PetalLayout.outline(center: center, angle: .pi / 2, width: 6, inner: 4, outer: 11)
        XCTAssertTrue(right.contains(CGPoint(x: 19.5, y: 12)))
        XCTAssertFalse(right.contains(CGPoint(x: 12, y: 4.5)))
    }
}

final class ChoiceLayoutTests: XCTestCase {
    private func choice(at angle: Double, distance: CGFloat = 189, around petal: Double = 0) -> Int? {
        let offset = CGPoint(x: distance * CGFloat(sin(angle)), y: distance * CGFloat(cos(angle)))
        return ChoiceLayout.index(at: offset, count: 3, around: petal, glassRadius: 150)
    }

    func testThreeChoicesFanOutLeftToRightPastTheirPetal() {
        XCTAssertEqual(choice(at: -.pi / 6), 0)
        XCTAssertEqual(choice(at: 0), 1)
        XCTAssertEqual(choice(at: .pi / 6), 2)
        XCTAssertEqual(ChoiceLayout.angle(of: 0, count: 3, around: 0), -.pi / 6, accuracy: 0.0001)
        XCTAssertEqual(ChoiceLayout.angle(of: 2, count: 3, around: 0), .pi / 6, accuracy: 0.0001)
    }

    func testChoicesAnswerFromTheGlassEdgeOutToTheirTips() {
        XCTAssertNil(choice(at: 0, distance: 140))
        XCTAssertEqual(choice(at: 0, distance: 152), 1)
        XCTAssertEqual(choice(at: 0, distance: 226), 1)
        XCTAssertNil(choice(at: 0, distance: 260))
    }

    func testNothingAnswersBesideTheFanOrAroundAnotherPetal() {
        XCTAssertNil(choice(at: .pi / 2))
        XCTAssertNil(choice(at: -.pi / 2))
        XCTAssertEqual(choice(at: .pi, around: .pi), 1)
        XCTAssertNil(choice(at: 0, around: .pi))
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

final class DragStartTests: XCTestCase {
    func testADragThatBeginsAfterThePressIsNew() {
        var start = DragStart(changeCount: 5)
        start.pressed(changeCount: 5, late: 0.01)
        XCTAssertTrue(start.began(changeCount: 6))
    }

    func testAPressHandledAfterItsDragBeganStillSeesThatDrag() {
        var start = DragStart(changeCount: 5)
        start.pressed(changeCount: 6, late: 0.4)
        XCTAssertTrue(start.began(changeCount: 6))
    }

    func testAPressHandledOnTimeLeavesOutADragFromBeforeIt() {
        var start = DragStart(changeCount: 5)
        start.pressed(changeCount: 7, late: 0.01)
        XCTAssertFalse(start.began(changeCount: 7))
    }

    func testEachDragBeginsOnce() {
        var start = DragStart(changeCount: 5)
        XCTAssertTrue(start.began(changeCount: 6))
        XCTAssertFalse(start.began(changeCount: 6))
    }
}
