import XCTest

@testable import BloomCore

final class BloomCoreTests: XCTestCase {
    func testVersionIsSemanticVersion() {
        let parts = BloomCore.version.split(separator: ".")
        XCTAssertEqual(parts.count, 3)
        XCTAssertTrue(parts.allSatisfy { Int($0) != nil })
    }
}
