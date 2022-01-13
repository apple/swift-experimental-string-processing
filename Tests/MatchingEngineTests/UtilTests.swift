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

import XCTest
@testable import _MatchingEngine

class UtilTests: XCTestCase {
  func testTupleTypeConstruction() {
    XCTAssertTrue(TypeConstruction.tupleType(
      of: []) == Void.self)
    XCTAssertTrue(TypeConstruction.tupleType(
      of: [Int.self, Any.self]) == (Int, Any).self)
    XCTAssertTrue(
      TypeConstruction.tupleType(
        of: [[Int].self, [Int: Int].self, Void.self, Any.self])
      == ([Int], [Int: Int], Void, Any).self)
  }

  func testTypeErasedTupleConstruction() throws {
    let tuple0Erased = TypeConstruction.tuple(of: [1, 2, 3])
    let tuple0 = try XCTUnwrap(tuple0Erased as? (Int, Int, Int))
    XCTAssertEqual(tuple0.0, 1)
    XCTAssertEqual(tuple0.1, 2)
    XCTAssertEqual(tuple0.2, 3)

    let tuple1Erased = TypeConstruction.tuple(
      of: [[1, 2], [true, false], [3.0, 4.0]])
    XCTAssertTrue(type(of: tuple1Erased) == ([Int], [Bool], [Double]).self)
    let tuple1 = try XCTUnwrap(tuple1Erased as? ([Int], [Bool], [Double]))
    XCTAssertEqual(tuple1.0, [1, 2])
    XCTAssertEqual(tuple1.1, [true, false])
    XCTAssertEqual(tuple1.2, [3.0, 4.0])
  }
}
