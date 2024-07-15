import XCTest
import _StringProcessing
@testable import RegexBuilder

func goodFunction<T>(_ r: some RegexComponent<T>) {
  _ = try? r.regex.firstMatch(in: "...")
}

fileprivate func badFunction<T>(_ r: Regex<T>) {
  _ = try? r.firstMatch(in: "...")
}

class GoodBadFunctionTests: XCTestCase {
  func testGoodBadFunctions() {
    goodFunction(Regex { "asdf" })
    badFunction(Regex { "asdf" })
  }
}
