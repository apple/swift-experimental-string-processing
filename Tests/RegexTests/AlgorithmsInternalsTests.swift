//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2021-2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

@testable import _StringProcessing
import XCTest

// TODO: Protocol-powered testing
extension AlgorithmTests {
  func testAdHoc() {
    let r = try! Regex("a|b+")

    XCTAssert("palindrome".contains(pattern: r))
    XCTAssert("botany".contains(pattern: r))
    XCTAssert("antiquing".contains(pattern: r))
    XCTAssertFalse("cdef".contains(pattern: r))

    let str = "a string with the letter b in it"
    let first = str.firstRange(of: r)
    let last = str.lastRange(of: r)
    let (expectFirst, expectLast) = (
      str.index(atOffset: 0)..<str.index(atOffset: 1),
      str.index(atOffset: 25)..<str.index(atOffset: 26))
    output(str.split(around: first!))
    output(str.split(around: last!))

    XCTAssertEqual(expectFirst, first)
    XCTAssertEqual(expectLast, last)

    XCTAssertEqual(
      [expectFirst, expectLast], Array(str.ranges(of: r)))

    XCTAssertTrue(str.starts(with: r))
    XCTAssertFalse(str.ends(with: r))

    XCTAssertEqual(str.dropFirst(), str.trimmingPrefix(r))
    XCTAssertEqual("x", "axb".trimming(r))
    XCTAssertEqual("x", "axbb".trimming(r))
  }
}
