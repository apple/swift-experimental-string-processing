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


@testable import _MatchingEngine
@testable import _StringProcessing

import XCTest

extension RegexTests {

  private func testCompilationEquivalence(
    _ equivs: [String],
    file: StaticString = #file,
    line: UInt = #line
  ) throws {
    assert(!equivs.isEmpty)
    let progs = try equivs.map {
      try _compileRegex($0).engine.program
    }
    let ref = progs.first!
    for prog in progs.dropFirst() {
      guard ref.instructions.elementsEqual(
        prog.instructions) else {
          XCTFail("""
          Reference:
          \(ref)
          Current:
          \(prog)
          """,
          file: file, line: line)
          continue
        }
    }
  }

  func testCompileQuantification() throws {

    // NOTE: While we might change how we compile
    // quantifications, they should be compiled equivalently
    // for different syntactic expressions.
    let equivalents: Array<[String]> = [
      ["a*", "a{0,}"],
      ["a+", "a{1,}"],
      ["a?", "a{0,1}", "a{,1}"],

      ["a*?", "a{0,}?"],
      ["a+?", "a{1,}?"],
      ["a??", "a{0,1}?", "a{,1}?"],

      ["a*+", "a{0,}+"],
      ["a++", "a{1,}+"],
      ["a?+", "a{0,1}+", "a{,1}+"],
    ]

    for row in equivalents {
      try testCompilationEquivalence(row)
    }
  }

  func testCompileGroups() throws {
    let equivalents: Array<[String]> = [
      ["(?= assert)",
       "(*pla: assert)",
       "(*positive_lookahead: assert)"],
      ["(?! assert)",
       "(*nla: assert)",
       "(*negative_lookahead: assert)"],
      
      ["(?i) case-insensitive",
       "(?i: case-insensitive)"],
      ["(?i) case-insensitive(?-i) post",
       "(?i: case-insensitive) post"],
    ]

    for row in equivalents {
      try testCompilationEquivalence(row)
    }
  }
}
