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
@testable import _StringProcessing

func dynCap(
  _ s: String, optional: Bool = false
) -> StoredDynamicCapture {
  StoredDynamicCapture(s[...], optionalCount: optional ? 1 : 0)
}

class RegexDSLTests: XCTestCase {
  func _testDSLCaptures<Content: RegexComponent, CaptureType>(
    _ tests: (input: String, expectedCaptures: CaptureType?)...,
    matchType: CaptureType.Type,
    _ equivalence: (CaptureType, CaptureType) -> Bool,
    file: StaticString = #file,
    line: UInt = #line,
    @RegexComponentBuilder _ content: () -> Content
  ) throws {
    let regex = Regex(content())
    for (input, maybeExpectedCaptures) in tests {
      let maybeMatch = input.match(regex)
      if let expectedCaptures = maybeExpectedCaptures {
        let match = try XCTUnwrap(maybeMatch, file: file, line: line)
        let captures = try XCTUnwrap(match.match as? CaptureType, file: file, line: line)
        XCTAssertTrue(
          equivalence(captures, expectedCaptures),
          "'\(captures)' is not equal to the expected '\(expectedCaptures)'.",
          file: file, line: line)
      } else {
        XCTAssertNil(maybeMatch, file: file, line: line)
      }
    }
  }

  func testSimpleStrings() throws {
    let regex = Regex {
      "a"
      capture(Character("b")) // Character
      tryCapture("1") { Int($0) } // Int
    }
    // Assert the inferred capture type.
    let _: (Substring, Substring, Int).Type = type(of: regex).Match.self
    let maybeMatch = "ab1".match(regex)
    let match = try XCTUnwrap(maybeMatch)
    XCTAssertTrue(match.match == ("ab1", "b", 1))

    let substring = "ab1"[...]
    let substringMatch = try XCTUnwrap(substring.match(regex))
    XCTAssertTrue(match.match == substringMatch.match)
  }

  func testCharacterClasses() throws {
    try _testDSLCaptures(
      ("a c", ("a c", " ", "c")),
      matchType: (Substring, Substring, Substring).self, ==)
    {
      .any
      capture(.whitespace) // Substring
      capture("c") // Substring
    }
  }

  func testMatchResultDotZeroWithoutCapture() throws {
    let match = try XCTUnwrap("aaa".match { oneOrMore { "a" } })
    XCTAssertEqual(match.0, "aaa")
  }

  func testAlternation() throws {
    do {
      let regex = choiceOf {
        "aaa"
      }
      XCTAssertTrue("aaa".match(regex)?.match == "aaa")
      XCTAssertNil("aab".match(regex)?.match)
    }
    do {
      let regex = choiceOf {
        "aaa"
        "bbb"
        "ccc"
      }
      XCTAssertTrue("aaa".match(regex)?.match == "aaa")
      XCTAssertNil("aab".match(regex)?.match)
      XCTAssertTrue("bbb".match(regex)?.match == "bbb")
      XCTAssertTrue("ccc".match(regex)?.match == "ccc")
    }
    do {
      let regex = Regex {
        "ab"
        capture {
          choiceOf {
            "c"
            "def"
          }
        }.+
      }
      XCTAssertTrue(
        try XCTUnwrap("abc".match(regex)?.match) == ("abc", "c"))
    }
    do {
      let regex = choiceOf {
        "aaa"
        "bbb"
        "ccc"
      }
      XCTAssertTrue("aaa".match(regex)?.match == "aaa")
      XCTAssertNil("aab".match(regex)?.match)
      XCTAssertTrue("bbb".match(regex)?.match == "bbb")
      XCTAssertTrue("ccc".match(regex)?.match == "ccc")
    }
    do {
      let regex = choiceOf {
        capture("aaa")
      }
      XCTAssertTrue(
        try XCTUnwrap("aaa".match(regex)?.match) == ("aaa", "aaa"))
      XCTAssertNil("aab".match(regex)?.match)
    }
    do {
      let regex = choiceOf {
        capture("aaa")
        capture("bbb")
        capture("ccc")
      }
      XCTAssertTrue(
        try XCTUnwrap("aaa".match(regex)?.match) == ("aaa", "aaa", nil, nil))
      XCTAssertTrue(
        try XCTUnwrap("bbb".match(regex)?.match) == ("bbb", nil, "bbb", nil))
      XCTAssertTrue(
        try XCTUnwrap("ccc".match(regex)?.match) == ("ccc", nil, nil, "ccc"))
      XCTAssertNil("aab".match(regex)?.match)
    }
  }

  func testCombinators() throws {
    try _testDSLCaptures(
      ("aaaabccccdddkj", ("aaaabccccdddkj", "b", "cccc", "d", "k", nil, "j")),
      matchType: (Substring, Substring, Substring, Substring, Substring, Substring?, Substring?).self, ==)
    {
      "a".+
      capture(oneOrMore(Character("b"))) // Substring
      capture(zeroOrMore("c")) // Substring
      capture(.hexDigit).* // [Substring]
      "e".?
      capture("t" | "k") // Substring
      choiceOf { capture("k"); capture("j") } // (Substring?, Substring?)
    }
  }
  
  func testOptions() throws {
    try _testDSLCaptures(
      ("abc", "abc"),
      ("ABC", "ABC"),
      ("abcabc", "abcabc"),
      ("abcABCaBc", "abcABCaBc"),
      matchType: Substring.self, ==) {
        oneOrMore {
          "abc"
        }.caseSensitive(false)
      }
    
    // Multiple options on one component wrap successively, but do not
    // override - equivalent to each option attached to a wrapping `Regex`.
    try _testDSLCaptures(
      ("abc", "abc"),
      ("ABC", "ABC"),
      ("abcabc", "abcabc"),
      ("abcABCaBc", "abcABCaBc"),
      matchType: Substring.self, ==) {
        oneOrMore {
          "abc"
        }
        .caseSensitive(false)
        .caseSensitive(true)
      }

    // An option on an outer component doesn't override an option set on an
    // inner component.
    try _testDSLCaptures(
      ("abc", "abc"),
      ("ABC", "ABC"),
      ("ABCde", "ABCde"),
      ("ABCDE", nil),
      ("abcabc", "abcabc"),
      ("abcdeABCdeaBcde", "abcdeABCdeaBcde"),
      matchType: Substring.self, ==) {
        oneOrMore {
          "abc".caseSensitive(false)
          optionally("de")
        }
        .caseSensitive(true)
      }
  }
  
  func testQuantificationBehavior() throws {
    try _testDSLCaptures(
      ("abc1def2", ("abc1def2", "2")),
      matchType: (Substring, Substring).self, ==)
    {
      oneOrMore {
        oneOrMore(.word)
        capture(.digit)
      }
    }

    try _testDSLCaptures(
      ("abc1def2", ("abc1def2", "2")),
      matchType: (Substring, Substring).self, ==)
    {
      oneOrMore {
        oneOrMore(.word, .reluctantly)
        capture(.digit)
      }
    }

    try _testDSLCaptures(
      ("abc1def2", ("abc1def2", "2")),
      matchType: (Substring, Substring).self, ==)
    {
      oneOrMore {
        oneOrMore(.reluctantly) {
          .word
        }
        capture(.digit)
      }
    }
    
    try _testDSLCaptures(
      ("abc1def2", "abc1def2"),
      matchType: Substring.self, ==)
    {
      repeating(2...) {
        repeating(count: 3) {
          CharacterClass.word
        }
        CharacterClass.digit
      }
    }
    
    try _testDSLCaptures(
      ("aaabbbcccdddeeefff", "aaabbbcccdddeeefff"),
      ("aaaabbbcccdddeeefff", nil),
      ("aaacccdddeeefff", nil),
      ("aaabbbcccccccdddeeefff", nil),
      ("aaabbbcccddddddeeefff", nil),
      ("aaabbbcccdddefff", nil),
      ("aaabbbcccdddeee", "aaabbbcccdddeee"),
      matchType: Substring.self, ==)
    {
      repeating(count: 3) { "a" }
      repeating(1...) { "b" }
      repeating(2...5) { "c" }
      repeating(..<5) { "d" }
      repeating(2...) { "e" }
      repeating(0...) { "f" }
    }
  }
  
  func testAssertions() throws {
    try _testDSLCaptures(
      ("aaaaab", "aaaaab"),
      ("caaaaab", nil),
      ("aaaaabc", nil),
      matchType: Substring.self, ==)
    {
      Anchor.startOfLine
      "a".+
      "b"
      Anchor.endOfLine
    }
    
    try _testDSLCaptures(
      ("Cafe\u{301}", nil),
      ("Cafe", "Cafe"),
      matchType: Substring.self, ==)
    {
      oneOrMore(.word)
      UnicodeScalar("e")
      Anchor.textSegmentBoundary
    }

    try _testDSLCaptures(
      ("aaaaa1", "aaaaa1"),
      ("aaaaa2", nil),
      ("aaaaa", nil),
      ("aaaaab", nil),
      matchType: Substring.self, ==)
    {
      "a".+
      lookahead(CharacterClass.digit)
      lookahead("2", negative: true)
      CharacterClass.word
    }
  }

  func testNestedGroups() throws {
    return;

    // TODO: clarify what the nesting story is

    /*
    try _testDSLCaptures(
      ("aaaabccccddd", ("aaaabccccddd", [("b", "cccc", ["d", "d", "d"])])),
      matchType: (Substring, [(Substring, Substring, [Substring])]).self, ==)
    {
      "a".+
      oneOrMore {
        capture(oneOrMore("b"))
        capture(zeroOrMore("c"))
        capture("d").*
        "e".?
      }
    }
     */
  }

  func testCapturelessQuantification() throws {
    // This test is to make sure that a captureless quantification, when used
    // straight out of the quantifier (without being wrapped in a builder), is
    // able to produce a regex whose `Match` type does not contain any sort of
    // void.
    let regex = zeroOrMore(.digit)
    // Assert the inferred capture type.
    let _: Substring.Type = type(of: regex).Match.self
    let input = "123123"
    let match = try XCTUnwrap(input.match(regex)?.match)
    XCTAssertTrue(match == input)
  }

  func testQuantificationWithTransformedCapture() throws {
    // This test is to make sure transformed capture type information is
    // correctly propagated from the DSL into the bytecode and that the engine
    // is reconstructing the right types upon quantification (both empty and
    // non-empty).
    enum Word: Int32 {
      case apple
      case orange

      init?(_ string: Substring) {
        switch string {
        case "apple": self = .apple
        case "orange": self = .orange
        default: return nil
        }
      }
    }
    try _testDSLCaptures(
      ("aaa 123 apple orange apple", ("aaa 123 apple orange apple", 123, .apple)),
      ("aaa     ", ("aaa     ", nil, nil)),
      matchType: (Substring, Int?, Word?).self, ==)
    {
      "a".+
      oneOrMore(.whitespace)
      optionally {
        capture(oneOrMore(.digit)) { Int($0)! }
      }
      zeroOrMore {
        oneOrMore(.whitespace)
        capture(oneOrMore(.word)) { Word($0)! }
      }
    }
  }

  func testNestedCaptureTypes() throws {
    let regex1 = Regex {
      "a".+
      capture {
        capture(oneOrMore("b"))
        "e".?
      }
    }
    let _: (Substring, Substring, Substring).Type
      = type(of: regex1).Match.self
    let regex2 = Regex {
      "a".+
      capture {
        tryCapture("b") { Int($0) }.*
        "e".?
      }
    }
    let _: (Substring, Substring, Int?).Type
      = type(of: regex2).Match.self
    let regex3 = Regex {
      "a".+
      capture {
        tryCapture("b") { Int($0) }
        zeroOrMore {
          tryCapture("c") { Double($0) }
        }
        "e".?
      }
    }
    let _: (Substring, Substring, Int, Double?).Type
      = type(of: regex3).Match.self
    let regex4 = Regex {
      "a".+
      capture {
        oneOrMore {
          capture(oneOrMore("b"))
          capture(zeroOrMore("c"))
          capture("d").*
          "e".?
        }
      }
    }
    let _: (
      Substring, Substring, Substring, Substring, Substring?).Type
      = type(of: regex4).Match.self
  }

  func testUnicodeScalarPostProcessing() throws {
    let spaces = Regex {
      zeroOrMore {
        .whitespace
      }
    }

    let unicodeScalar = Regex {
      oneOrMore {
        .hexDigit
      }
      spaces
    }

    let unicodeData = Regex {
      unicodeScalar
      optionally {
        ".."
        unicodeScalar
      }

      ";"
      spaces

      capture {
        oneOrMore {
          .word
        }
      }

      zeroOrMore {
        .any
      }
    }

    // Assert the inferred capture type.
    let _: (Substring, Substring).Type = type(of: unicodeData).Match.self

    let unicodeLine =
      "1BCA0..1BCA3  ; Control # Cf   [4] SHORTHAND FORMAT LETTER OVERLAP..SHORTHAND FORMAT UP STEP"
    let match = try XCTUnwrap(unicodeLine.match(unicodeData))
    XCTAssertEqual(match.0, Substring(unicodeLine))
    XCTAssertEqual(match.1, "Control")
  }

  func testGraphemeBreakData() throws {
    let line = """
      A6F0..A6F1    ; Extend # Mn   [2] BAMUM COMBINING MARK KOQNDON..BAMUM COMBINING MARK TUKWENTIS
      """
    
    let regexWithCapture = Regex {
      capture {
        oneOrMore(.hexDigit)
      } transform: { Unicode.Scalar(hex: $0) }
      optionally {
        ".."
        capture {
          oneOrMore(.hexDigit)
        } transform: { Unicode.Scalar(hex: $0) }
      }
      oneOrMore(.whitespace)
      ";"
      oneOrMore(.whitespace)
      capture(oneOrMore(.word))
      zeroOrMore(.any)
    } // Regex<(Substring, Unicode.Scalar?, Unicode.Scalar??, Substring)>
    do {
      // Assert the inferred capture type.
      typealias ExpectedMatch = (
        Substring, Unicode.Scalar?, Unicode.Scalar??, Substring
      )
      let _: ExpectedMatch.Type = type(of: regexWithCapture).Match.self
      let maybeMatchResult = line.match(regexWithCapture)
      let matchResult = try XCTUnwrap(maybeMatchResult)
      let (wholeMatch, lower, upper, propertyString) = matchResult.match
      XCTAssertEqual(wholeMatch, Substring(line))
      XCTAssertEqual(lower, Unicode.Scalar(0xA6F0))
      XCTAssertEqual(upper, Unicode.Scalar(0xA6F1))
      XCTAssertEqual(propertyString, "Extend")
    }

    let regexWithTryCapture = Regex {
      tryCapture {
        oneOrMore(.hexDigit)
      } transform: {
        Unicode.Scalar(hex: $0)
      }
      optionally {
        ".."
        tryCapture {
          oneOrMore(.hexDigit)
        } transform: {
          Unicode.Scalar(hex: $0)
        }
      }
      oneOrMore(.whitespace)
      ";"
      oneOrMore(.whitespace)
      capture(oneOrMore(.word))
      zeroOrMore(.any)
    } // Regex<(Substring, Unicode.Scalar, Unicode.Scalar?, Substring)>
    do {
      // Assert the inferred capture type.
      typealias ExpectedMatch = (
        Substring, Unicode.Scalar, Unicode.Scalar?, Substring
      )
      let _: ExpectedMatch.Type = type(of: regexWithTryCapture).Match.self
      let maybeMatchResult = line.match(regexWithTryCapture)
      let matchResult = try XCTUnwrap(maybeMatchResult)
      let (wholeMatch, lower, upper, propertyString) = matchResult.match
      XCTAssertEqual(wholeMatch, Substring(line))
      XCTAssertEqual(lower, Unicode.Scalar(0xA6F0))
      XCTAssertEqual(upper, Unicode.Scalar(0xA6F1))
      XCTAssertEqual(propertyString, "Extend")
    }

    do {
      let regexLiteral = try MockRegexLiteral(
        #"([0-9A-F]+)(?:\.\.([0-9A-F]+))?\s+;\s+(\w+).*"#,
        matching: (Substring, Substring, Substring?, Substring).self)
      let maybeMatchResult = line.match(regexLiteral)
      let matchResult = try XCTUnwrap(maybeMatchResult)
      let (wholeMatch, lower, upper, propertyString) = matchResult.match
      XCTAssertEqual(wholeMatch, Substring(line))
      XCTAssertEqual(lower, "A6F0")
      XCTAssertEqual(upper, "A6F1")
      XCTAssertEqual(propertyString, "Extend")
    }
  }

  func testDynamicCaptures() throws {
    do {
      let regex = try Regex("aabcc.")
      let line = "aabccd"
      let captures = try XCTUnwrap(line.match(regex)?.1)
      XCTAssertEqual(captures, [])
    }
    do {

      let regex = try Regex(
        #"([0-9A-F]+)(?:\.\.([0-9A-F]+))?\s+;\s+(\w+).*"#)
      let line = """
        A6F0..A6F1    ; Extend # Mn   [2] BAMUM COMBINING MARK KOQNDON..BAMUM \
        COMBINING MARK TUKWENTIS
        """
      let captures = try XCTUnwrap(line.match(regex)?.1)
      XCTAssertEqual(
        captures,
        [
          dynCap("A6F0"),
          dynCap("A6F1", optional: true),
          dynCap("Extend"),
        ])
    }
  }

  func testBackreference() throws {
    try _testDSLCaptures(
      ("abc#41#42abcabcabc", ("abc#41#42abcabcabc", "abc", 42, "abc", nil)),
      matchType: (Substring, Substring, Int?, Substring?, Substring?).self, ==)
    {
      let a = Reference(Substring.self)
      let b = Reference(Int.self)
      capture("abc", as: a)
      zeroOrMore {
        tryCapture(as: b) {
          "#"
          oneOrMore(.digit)
        } transform: {
          Int($0.dropFirst())
        }
      }
      a
      zeroOrMore {
        capture(a)
      }
      optionally {
        "b"
        capture(a)
      }
    }

    // Match result referencing a `Reference`.
    do {
      let a = Reference(Substring.self)
      let b = Reference(Int.self)
      let regex = Regex {
        capture("abc", as: a)
        zeroOrMore {
          tryCapture(as: b) {
            "#"
            oneOrMore(.digit)
          } transform: {
            Int($0.dropFirst())
          }
        }
        a
        zeroOrMore {
          capture(b)
        }
        optionally {
          capture(a)
        }
      }
      let input = "abc#41#42abc#42#42"
      let result = try XCTUnwrap(input.match(regex))
      XCTAssertEqual(result[a], "abc")
      XCTAssertEqual(result[b], 42)
    }

    // Post-hoc captured references
    // #"(?:\w\1|:(\w):)+"#
    try _testDSLCaptures(
      (":a:baca:o:boco", (":a:baca:o:boco", "o")),
      matchType: (Substring, Substring).self,
      ==
    ) {
      oneOrMore {
        let a = Reference(Substring.self)
        choiceOf {
          Regex {
            .word
            a
          }
          Regex {
            ":"
            capture(.word, as: a)
            ":"
          }
        }
      }
    }
  }
  
  func testSemanticVersionExample() {
    struct SemanticVersion: Equatable {
      var major: Int
      var minor: Int
      var patch: Int
      var dev: String?
    }
    struct SemanticVersionParser: CustomRegexComponent {
      typealias Match = SemanticVersion
      func match(
        _ input: String,
        startingAt index: String.Index,
        in bounds: Range<String.Index>
      ) -> (upperBound: String.Index, match: SemanticVersion)? {
        let regex = Regex {
          tryCapture(oneOrMore(.digit)) { Int($0) }
          "."
          tryCapture(oneOrMore(.digit)) { Int($0) }
          optionally {
            "."
            tryCapture(oneOrMore(.digit)) { Int($0) }
          }
          optionally {
            "-"
            capture(oneOrMore(.word))
          }
        }

        guard let match = input[index..<bounds.upperBound].firstMatch(of: regex),
              match.range.lowerBound == index
        else { return nil }

        let result = SemanticVersion(
          major: match.result.1,
          minor: match.result.2,
          patch: match.result.3 ?? 0,
          dev: match.result.4.map(String.init))
        return (match.range.upperBound, result)
      }
    }
    
    let versions = [
      ("1.0", SemanticVersion(major: 1, minor: 0, patch: 0)),
      ("1.0.1", SemanticVersion(major: 1, minor: 0, patch: 1)),
      ("12.100.5-dev", SemanticVersion(major: 12, minor: 100, patch: 5, dev: "dev")),
    ]
    
    let parser = SemanticVersionParser()
    for (str, version) in versions {
      XCTAssertEqual(str.match(parser)?.match, version)
    }
  }
}

extension Unicode.Scalar {
  // Convert a hexadecimal string to a scalar
  init?<S: StringProtocol>(hex: S) {
    guard let val = UInt32(hex, radix: 16), let scalar = Self(val) else {
      return nil
    }
    self = scalar
  }
}

// MARK: Extra == functions

func == <T0: Equatable, T1: Equatable, T2: Equatable, T3: Equatable, T4: Equatable, T5: Equatable, T6: Equatable>(
  l: (T0, T1, T2, T3, T4, T5, T6), r: (T0, T1, T2, T3, T4, T5, T6)
) -> Bool {
  l.0 == r.0 && (l.1, l.2, l.3, l.4, l.5, l.6) == (r.1, r.2, r.3, r.4, r.5, r.6)
}
