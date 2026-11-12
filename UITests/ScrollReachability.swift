import XCTest

@MainActor
extension XCTestCase {
    /// Scroll the actual List, never the drawer backdrop or the disabled chat beneath it.
    @discardableResult
    func reveal(_ target: XCUIElement, in list: XCUIElement, towardEnd: Bool = true,
                maximumSwipes: Int = 12, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        XCTAssertTrue(list.waitForExistence(timeout: 5), "Expected scroll container is absent.", file: file, line: line)
        for _ in 0..<maximumSwipes {
            if target.exists && target.isHittable { return target }
            var scrollTowardEnd = towardEnd
            if target.exists && !target.frame.isEmpty {
                if target.frame.maxY <= list.frame.minY + 12 { scrollTowardEnd = false }
                else if target.frame.minY >= list.frame.maxY - 12 { scrollTowardEnd = true }
            }
            if scrollTowardEnd { list.swipeUp() } else { list.swipeDown() }
        }
        XCTAssertTrue(target.exists && target.isHittable, "Target must exist and be visible after bounded scrolling.", file: file, line: line)
        return target
    }
}
