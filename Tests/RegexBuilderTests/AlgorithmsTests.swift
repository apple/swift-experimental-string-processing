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
import _StringProcessing
import RegexBuilder

@available(SwiftStdlib 5.7, *)
class RegexConsumerTests: XCTestCase {
  func testMatches() {
    let regex = Capture<(Substring, Int)>(OneOrMore(.digit)) { 2 * Int($0)! }
    let str = "foo 160 bar 99 baz"
    XCTAssertEqual(str.matches(of: regex).map(\.output.1), [320, 198])
  }
  
  func testMatchReplace() {
    func replaceTest<R: RegexComponent>(
      _ regex: R,
      input: String,
      result: String,
      _ replace: (Regex<R.RegexOutput>.Match) -> String,
      file: StaticString = #file,
      line: UInt = #line
    ) {
      XCTAssertEqual(input.replacing(regex, with: replace), result)
    }
    
    let int = Capture(OneOrMore(.digit)) { Int($0)! }
    
    replaceTest(
      int,
      input: "foo 160 bar 99 baz",
      result: "foo 240 bar 143 baz",
      { match in String(match.output.1, radix: 8) })
    
    replaceTest(
      Regex { int; "+"; int },
      input: "9+16, 0+3, 5+5, 99+1",
      result: "25, 3, 10, 100",
      { match in "\(match.output.1 + match.output.2)" })

    // TODO: Need to support capture history
    // replaceTest(
    //   OneOrMore { int; "," },
    //   input: "3,5,8,0, 1,0,2,-5,x8,8,",
    //   result: "16 3-5x16",
    //   { match in "\(match.result.1.reduce(0, +))" })
    
    replaceTest(
      Regex { int; "x"; int; Optionally { "x"; int } },
      input: "2x3 5x4x3 6x0 1x2x3x4",
      result: "6 60 0 6x4",
      { match in "\(match.output.1 * match.output.2 * (match.output.3 ?? 1))" })
  }

  func testMatchReplaceSubrange() {
    func replaceTest<R: RegexComponent>(
      _ regex: R,
      input: String,
      _ replace: (Regex<R.RegexOutput>.Match) -> String,
      _ tests: (subrange: Range<String.Index>, maxReplacement: Int, result: String)...,
      file: StaticString = #file,
      line: UInt = #line
    ) {
      for (subrange, maxReplacement, result) in tests {
        XCTAssertEqual(input.replacing(regex, subrange: subrange, maxReplacements: maxReplacement, with: replace), result, file: file, line: line)
      }
    }

    let int = Capture(OneOrMore(.digit)) { Int($0)! }

    let addition = "9+16, 0+3, 5+5, 99+1"

    replaceTest(
      Regex { int; "+"; int },
      input: "9+16, 0+3, 5+5, 99+1",
      { match in "\(match.output.1 + match.output.2)" },

      (subrange: addition.startIndex..<addition.endIndex,
       maxReplacement: 0,
       result: "9+16, 0+3, 5+5, 99+1"),
      (subrange: addition.startIndex..<addition.endIndex,
       maxReplacement: .max,
       result: "25, 3, 10, 100"),
      (subrange: addition.startIndex..<addition.endIndex,
       maxReplacement: 2,
       result: "25, 3, 5+5, 99+1"),
      (subrange: addition.index(addition.startIndex, offsetBy: 5) ..< addition.endIndex,
       maxReplacement: .max,
       result: "9+16, 3, 10, 100"),
      (subrange: addition.startIndex ..< addition.index(addition.startIndex, offsetBy: 5),
       maxReplacement: .max,
       result: "25, 0+3, 5+5, 99+1"),
      (subrange: addition.index(addition.startIndex, offsetBy: 5) ..< addition.endIndex,
       maxReplacement: 2,
       result: "9+16, 3, 10, 99+1")
    )
  }
}

@available(SwiftStdlib 5.7, *)
class AlgorithmsResultBuilderTests: XCTestCase {
  enum MatchAlgo {
    case whole
    case first
    case prefix
  }

  enum EquatableAlgo {
    case starts
    case contains
    case trimmingPrefix
  }

  func expectMatch<MatchType, RegexOutputType>(
    _ algo: MatchAlgo,
    _ tests: (input: String, expectedCaptures: MatchType?)...,
    matchType: MatchType.Type,
    equivalence: (MatchType, MatchType) -> Bool,
    file: StaticString = #file,
    line: UInt = #line,
    @RegexComponentBuilder _ content: () -> some RegexComponent<RegexOutputType>
  ) throws {
    for (input, expectedCaptures) in tests {
      var actual: Regex<RegexOutputType>.Match?
      switch algo {
      case .whole:
        actual = input.wholeMatch(of: content)
      case .first:
        actual = input.firstMatch(of: content)
      case .prefix:
        actual = input.prefixMatch(of: content)
      }
      if let expectedCaptures = expectedCaptures {
        let match = try XCTUnwrap(actual, file: file, line: line)
        let captures = try XCTUnwrap(match.output as? MatchType, file: file, line: line)
        XCTAssertTrue(equivalence(captures, expectedCaptures), file: file, line: line)
      } else {
        XCTAssertNil(actual, file: file, line: line)
      }
    }
  }

  func expectEqual<Expected: Equatable>(
    _ algo: EquatableAlgo,
    _ tests: (input: String, expected: Expected)...,
    file: StaticString = #file,
    line: UInt = #line,
    @RegexComponentBuilder _ content: () -> some RegexComponent
  ) throws {
    for (input, expected) in tests {
      var actual: Expected
      switch algo {
      case .contains:
        actual = input.contains(content) as! Expected
      case .starts:
        actual = input.starts(with: content) as! Expected
      case .trimmingPrefix:
        actual = input.trimmingPrefix(content) as! Expected
      }
      XCTAssertEqual(actual, expected)
    }
  }

  func testMatches() throws {
    do {
      let regex = Regex { OneOrMore(.any) }
      XCTAssertEqual("abc".wholeMatch(of: regex)!.0, "abc")
      XCTAssertEqual("abc".prefixMatch(of: regex)!.0, "abc")
      XCTAssertEqual("abc".firstMatch(of: regex)!.0, "abc")
      XCTAssertEqual("abc".suffix(1).wholeMatch(of: regex)!.0, "c")
      XCTAssertEqual("abc".suffix(1).prefixMatch(of: regex)!.0, "c")
      XCTAssertEqual("abc".suffix(1).firstMatch(of: regex)!.0, "c")
    }
    
    let int = Capture(OneOrMore(.digit)) { Int($0)! }

    // Test syntax
    let add = Regex {
      int
      "+"
      int
    }
    let content = { add }

    let m = "2020+16".wholeMatch {
      int
      "+"
      int
    }
    XCTAssertEqual(m?.output.0, "2020+16")
    XCTAssertEqual(m?.output.1, 2020)
    XCTAssertEqual(m?.output.2, 16)

    let m1 = "2020+16".wholeMatch(of: content)
    XCTAssertEqual(m1?.output.0, m?.output.0)
    XCTAssertEqual(m1?.output.1, m?.output.1)
    XCTAssertEqual(m1?.output.2, m?.output.2)

    let firstMatch = "2020+16 0+0".firstMatch(of: content)
    XCTAssertEqual(firstMatch?.output.0, "2020+16")
    XCTAssertEqual(firstMatch?.output.1, 2020)
    XCTAssertEqual(firstMatch?.output.2, 16)

    let prefix = "2020+16 0+0".prefixMatch(of: content)
    XCTAssertEqual(prefix?.output.0, "2020+16")
    XCTAssertEqual(prefix?.output.1, 2020)
    XCTAssertEqual(prefix?.output.2, 16)

    try expectMatch(
      .whole,
      ("0+0", ("0+0", 0, 0)),
      ("2020+16", ("2020+16", 2020, 16)),
      ("-2020+16", nil),
      ("2020+16+0+0", nil),
      matchType: (Substring, Int, Int).self,
      equivalence: ==
    ) {
      int
      "+"
      int
    }

    try expectMatch(
      .prefix,
      ("0+0", ("0+0", 0, 0)),
      ("2020+16", ("2020+16", 2020, 16)),
      ("-2020+16", nil),
      ("2020+16+0+0", ("2020+16", 2020, 16)),
      matchType: (Substring, Int, Int).self,
      equivalence: ==
    ) {
      int
      "+"
      int
    }

    try expectMatch(
      .first,
      ("0+0", ("0+0", 0, 0)),
      ("2020+16", ("2020+16", 2020, 16)),
      ("-2020+16", ("2020+16", 2020, 16)),
      ("2020+16+0+0", ("2020+16", 2020, 16)),
      matchType: (Substring, Int, Int).self,
      equivalence: ==
    ) {
      int
      "+"
      int
    }
  }

  func testStartsAndContains() throws {
    let fam = "👨‍👩‍👧‍👦👨‍👨‍👧‍👧  we Ⓡ family"
    let startsWithGrapheme = fam.starts {
      OneOrMore(.anyGraphemeCluster)
      OneOrMore(.whitespace)
    }
    XCTAssertEqual(startsWithGrapheme, true)

    let containsDads = fam.contains {
      "👨‍👨‍👧‍👧"
    }
    XCTAssertEqual(containsDads, true)

    let content = {
      Regex {
        OneOrMore(.anyGraphemeCluster)
        OneOrMore(.whitespace)
      }
    }
    XCTAssertEqual(fam.starts(with: content), true)
    XCTAssertEqual(fam.contains(content), true)

    let int = Capture(OneOrMore(.digit)) { Int($0)! }

    try expectEqual(
      .starts,
      ("9+16, 0+3, 5+5, 99+1", true),
      ("-9+16, 0+3, 5+5, 99+1", false),
      (" 9+16", false),
      ("a+b, c+d", false),
      ("", false)
    ) {
      int
      "+"
      int
    }

    try expectEqual(
      .contains,
      ("9+16, 0+3, 5+5, 99+1", true),
      ("-9+16, 0+3, 5+5, 99+1", true),
      (" 9+16", true),
      ("a+b, c+d", false),
      ("", false)
    ) {
      int
      "+"
      int
    }
  }

  func testTrim() throws {
    let int = Capture(OneOrMore(.digit)) { Int($0)! }

    // Test syntax
    let code = "(408)888-8888".trimmingPrefix {
      "("
      OneOrMore(.digit)
      ")"
    }
    XCTAssertEqual(code, Substring("888-8888"))

    var mutable = "👨‍👩‍👧‍👦  we Ⓡ family"
    mutable.trimPrefix {
      .anyGraphemeCluster
      ZeroOrMore(.whitespace)
    }
    XCTAssertEqual(mutable, "we Ⓡ family")

    try expectEqual(
      .trimmingPrefix,
      ("9+16 0+3 5+5 99+1", Substring(" 0+3 5+5 99+1")),
      ("a+b 0+3 5+5 99+1", Substring("a+b 0+3 5+5 99+1")),
      ("0+3+5+5+99+1", Substring("+5+5+99+1")),
      ("", "")
    ) {
      int
      "+"
      int
    }
  }

  func testReplace() {
    // Test no ambiguitiy using the trailing closure
    var replaced: String
    let str = "9+16, 0+3, 5+5, 99+1"
    replaced = str.replacing(with: "🔢") {
      OneOrMore(.digit)
      "+"
      OneOrMore(.digit)
    }
    XCTAssertEqual(replaced, "🔢, 🔢, 🔢, 🔢")

    replaced = str.replacing(
      with: "🔢",
      subrange: str.startIndex..<str.index(str.startIndex, offsetBy: 10)) {
        OneOrMore(.digit)
        "+"
        OneOrMore(.digit)
      }
    XCTAssertEqual(replaced, "🔢, 🔢, 5+5, 99+1")

    replaced = str.replacing(
      with: "🔢",
      subrange: str.startIndex..<str.index(str.startIndex, offsetBy: 10),
      maxReplacements: 1) {
        OneOrMore(.digit)
        "+"
        OneOrMore(.digit)
    }
    XCTAssertEqual(replaced, "🔢, 0+3, 5+5, 99+1")

    replaced = str.replacing(
      with: "🔢",
      maxReplacements: 3) {
        OneOrMore(.digit)
        "+"
        OneOrMore(.digit)
      }
    XCTAssertEqual(replaced, "🔢, 🔢, 🔢, 99+1")

    replaced = str
    replaced.replace(
      with: "🔢",
      maxReplacements: 2) {
        OneOrMore(.digit)
        "+"
        OneOrMore(.digit)
      }
    XCTAssertEqual(replaced, "🔢, 🔢, 5+5, 99+1")

    // Test two closures

    let int = Capture(OneOrMore(.digit)) { Int($0)! }

    replaced = str.replacing(
      maxReplacements: 2) {
        int
        "+"
        int
      } with: { match in
        "\(match.output.1 + match.output.2)"
      }
    XCTAssertEqual(replaced, "25, 3, 5+5, 99+1")

    replaced = str.replacing(
      subrange: str.index(str.startIndex, offsetBy: 5)..<str.endIndex,
      maxReplacements: 2) {
        int
        "+"
        int
      } with: { match in
        "\(match.output.1 + match.output.2)"
      }
    XCTAssertEqual(replaced, "9+16, 3, 10, 99+1")
  }

  func testSplit() {
    let str = "aaa12+22aaaa33+44aa55+55"
    var splits: [Substring]
    splits = str.split {
      OneOrMore(.digit)
      "+"
      OneOrMore(.digit)
    }
    XCTAssertEqual(splits, ["aaa", "aaaa", "aa"])

    splits = str.split(omittingEmptySubsequences: true) {
      OneOrMore(.digit)
      "+"
      OneOrMore(.digit)
    }
    XCTAssertEqual(splits, ["aaa", "aaaa", "aa"])

    splits = str.split(
      maxSplits: 2,
      omittingEmptySubsequences: true) {
      OneOrMore(.digit)
      "+"
      OneOrMore(.digit)
    }
    XCTAssertEqual(splits, ["aaa", "aaaa", "aa55+55"])

    let separator = {
      Regex {
        OneOrMore(.digit)
        "+"
        OneOrMore(.digit)
      }
    }
    splits = str.split(separator: separator)
    XCTAssertEqual(splits, ["aaa", "aaaa", "aa"])
  }
}
