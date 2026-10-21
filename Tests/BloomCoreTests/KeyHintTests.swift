import BloomCore
import XCTest

final class KeyHintTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "BloomCoreTests.KeyHint"

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: suite)
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testShowsOnlyOnceADragHasGoneAMomentWithoutAKey() {
        var hint = KeyHint(defaults: defaults)
        XCTAssertFalse(hint.isShowing(at: 10))
        hint.dragStarted(at: 10)
        XCTAssertFalse(hint.isShowing(at: 10.5))
        XCTAssertTrue(hint.isShowing(at: 10 + KeyHint.delay))
        XCTAssertTrue(hint.isShowing(at: 14))
    }

    func testAQuickDragNeverShowsIt() {
        var hint = KeyHint(defaults: defaults)
        hint.dragStarted(at: 10)
        hint.dragEnded()
        XCTAssertFalse(hint.isShowing(at: 12))
    }

    func testEachDragWaitsAfresh() {
        var hint = KeyHint(defaults: defaults)
        hint.dragStarted(at: 10)
        hint.dragEnded()
        hint.dragStarted(at: 20)
        XCTAssertFalse(hint.isShowing(at: 20.5))
        XCTAssertTrue(hint.isShowing(at: 21.2))
    }

    func testOpeningAFlowerHidesItForGoodEvenAfterRelaunch() {
        var hint = KeyHint(defaults: defaults)
        hint.dragStarted(at: 10)
        XCTAssertTrue(hint.isShowing(at: 12))
        hint.flowerOpened()
        XCTAssertFalse(hint.isShowing(at: 12))
        XCTAssertTrue(hint.isRetired)

        hint.dragStarted(at: 20)
        XCTAssertFalse(hint.isShowing(at: 25))

        var relaunched = KeyHint(defaults: UserDefaults(suiteName: suite)!)
        relaunched.dragStarted(at: 30)
        XCTAssertFalse(relaunched.isShowing(at: 35))
    }

    func testANewMacShowsIt() {
        XCTAssertFalse(KeyHint(defaults: defaults).isRetired)
    }

    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let size = CGSize(width: 120, height: 110)

    private func frame(for pointer: CGPoint) -> CGRect {
        CGRect(origin: KeyHint.origin(for: pointer, size: size, in: screen), size: size)
    }

    /// What Finder drags along with the pointer, in AppKit coordinates: a 64-point icon centred on the pointer with a
    /// two-line name under it, or a list row's name running right from just left of the pointer.
    private func dragged(at pointer: CGPoint) -> [CGRect] {
        [
            CGRect(x: pointer.x - 32, y: pointer.y - 32, width: 64, height: 64),
            CGRect(x: pointer.x - 60, y: pointer.y - 70, width: 120, height: 36),
            CGRect(x: pointer.x - 20, y: pointer.y - 10, width: 400, height: 20),
        ]
    }

    func testSitsAboveAndRightOfThePointer() {
        let pointer = CGPoint(x: 700, y: 500)
        let hint = frame(for: pointer)
        XCTAssertGreaterThan(hint.minX, pointer.x)
        XCTAssertGreaterThan(hint.minY, pointer.y)
    }

    func testKeepsClearOfTheDraggedIconAndItsNameWhereverItFlips() {
        for pointer in [
            CGPoint(x: 700, y: 500), CGPoint(x: 1435, y: 500), CGPoint(x: 700, y: 895), CGPoint(x: 1435, y: 895), CGPoint(x: 5, y: 5),
        ] {
            let hint = frame(for: pointer)
            for part in dragged(at: pointer) {
                XCTAssertFalse(hint.intersects(part), "\(hint) covers \(part) for a pointer at \(pointer)")
            }
        }
    }

    func testStaysOnScreenAndOffThePointerAtTheEdges() {
        let corners = [
            CGPoint(x: 1435, y: 500), CGPoint(x: 700, y: 5), CGPoint(x: 1435, y: 5), CGPoint(x: 5, y: 895), CGPoint(x: 1435, y: 895),
        ]
        for pointer in corners {
            let hint = frame(for: pointer)
            XCTAssertTrue(screen.contains(hint), "\(hint) runs off screen for a pointer at \(pointer)")
            XCTAssertFalse(hint.insetBy(dx: -4, dy: -4).contains(pointer), "\(hint) covers the pointer at \(pointer)")
        }
    }

    /// A second display left of the main one, above a Dock along its bottom.
    func testStaysOnADisplayThatDoesntStartAtZero() {
        let display = CGRect(x: -1920, y: 70, width: 1920, height: 1010)
        for pointer in [CGPoint(x: -4, y: 600), CGPoint(x: -900, y: 74), CGPoint(x: -4, y: 74), CGPoint(x: -1915, y: 1075)] {
            let hint = CGRect(origin: KeyHint.origin(for: pointer, size: size, in: display), size: size)
            XCTAssertTrue(display.contains(hint), "\(hint) runs off the display for a pointer at \(pointer)")
            XCTAssertFalse(hint.insetBy(dx: -4, dy: -4).contains(pointer), "\(hint) covers the pointer at \(pointer)")
        }
    }
}
