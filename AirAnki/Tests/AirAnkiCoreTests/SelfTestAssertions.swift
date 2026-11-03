#if AIRANKI_SELF_TEST
import Foundation

/// Minimal assertion runner for CLT-only Macs. The test bodies also run in XCTest.
class XCTestCase {}

enum SelfTestResults {
    private static let lock = NSLock()
    private static var failures = 0
    static var count: Int {
        lock.lock(); defer { lock.unlock() }
        return failures
    }
    static func fail(_ message: String, file: StaticString, line: UInt) {
        lock.lock(); defer { lock.unlock() }
        failures += 1
        print("FAIL \(file):\(line): \(message)")
    }
}

func XCTFail(_ message: String = "Failure", file: StaticString = #filePath, line: UInt = #line) {
    SelfTestResults.fail(message, file: file, line: line)
}

func XCTAssertTrue(_ expression: @autoclosure () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
    if !expression() { XCTFail("Expected true", file: file, line: line) }
}

func XCTAssertFalse(_ expression: @autoclosure () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
    if expression() { XCTFail("Expected false", file: file, line: line) }
}

func XCTAssertNil<T>(_ expression: @autoclosure () -> T?, file: StaticString = #filePath, line: UInt = #line) {
    if expression() != nil { XCTFail("Expected nil", file: file, line: line) }
}

func XCTAssertEqual<T: Equatable>(_ left: @autoclosure () -> T, _ right: @autoclosure () -> T,
                                  file: StaticString = #filePath, line: UInt = #line) {
    let actual = left(), expected = right()
    if actual != expected { XCTFail("\(actual) != \(expected)", file: file, line: line) }
}
#endif
