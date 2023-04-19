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
import TestSupport

@available(SwiftStdlib 5.7, *)
class RegexDSLTests: XCTestCase {
  func _testDSLCaptures<MatchType>(
    _ tests: (input: String, expectedCaptures: MatchType?)...,
    matchType: MatchType.Type,
    _ equivalence: (MatchType, MatchType) -> Bool,
    xfail: Bool = false,
    file: StaticString = #file,
    line: UInt = #line,
    @RegexComponentBuilder _ content: () -> some RegexComponent<MatchType>
  ) throws {
    let regex = content()
    for (input, maybeExpectedCaptures) in tests {
      let maybeMatch = input.wholeMatch(of: regex)
      guard let match = maybeMatch else {
        if !xfail, maybeExpectedCaptures != nil {
          XCTFail("Failed to match '\(input)'", file: file, line: line)
        }
        continue
      }
      guard let expectedCaptures = maybeExpectedCaptures else {
        if !xfail {
          XCTFail(
            "Unexpectedly matched '\(match)' for '\(input)'",
            file: file, line: line)
        }
        continue
      }
      if xfail {
        XCTFail("Unexpectedly matched", file: file, line: line)
        continue
      }
      let captures = match.output
      XCTAssertTrue(
        equivalence(captures, expectedCaptures),
        "'\(captures)' is not equal to the expected '\(expectedCaptures)'.",
        file: file, line: line)
    }
  }
  
  func testSimpleStrings() throws {
    let regex = Regex {
      "a"
      Capture(Character("b")) // Character
      TryCapture { "1" } transform: { Int($0) } // Int
    }
    // Assert the inferred capture type.
    let _: (Substring, Substring, Int).Type = type(of: regex).RegexOutput.self
    let maybeMatch = "ab1".wholeMatch(of: regex)
    let match = try XCTUnwrap(maybeMatch)
    XCTAssertTrue(match.output == ("ab1", "b", 1))
    
    let substring = "ab1"[...]
    let substringMatch = try XCTUnwrap(substring.wholeMatch(of: regex))
    XCTAssertTrue(match.output == substringMatch.output)
  }
  
  let allNewlines = "\u{A}\u{B}\u{C}\u{D}\r\n\u{85}\u{2028}\u{2029}"
  let asciiNewlines = "\u{A}\u{B}\u{C}\u{D}\r\n"
  
  func testCharacterClasses() throws {
    // Must have new stdlib for character class ranges.
    guard ensureNewStdlib() else { return }
    
    try _testDSLCaptures(
      ("a c", ("a c", " ", "c")),
      matchType: (Substring, Substring, Substring).self, ==)
    {
      One(.any)
      Capture(.whitespace) // Substring
      Capture("c") // Substring
    }
    
    try _testDSLCaptures(
      ("abc1def2", "abc1def2"),
      matchType: Substring.self, ==)
    {
      // First group
      OneOrMore {
        CharacterClass("a"..."z", .digit)
      }
      
      // Second group
      OneOrMore {
        ChoiceOf {
          "a"..."z"
          CharacterClass.hexDigit
        }
      }
    }
    
    try _testDSLCaptures(
      ("abc1def2", ("abc1def2", "abc1")),
      matchType: (Substring, Substring).self, ==)
    {
      Capture {
        OneOrMore(.digit.inverted)
        ("a"..."z").inverted
      }
      
      OneOrMore {
        CharacterClass.whitespace.inverted
      }
    }
    
    // `.newlineSequence` and `.verticalWhitespace` match the same set of
    // newlines in grapheme semantic mode, and scalar mode when applied with
    // OneOrMore.
    for cc in [CharacterClass.newlineSequence, .verticalWhitespace] {
      for mode in [RegexSemanticLevel.unicodeScalar, .graphemeCluster] {
        try _testDSLCaptures(
          ("\n", ("\n", "\n")),
          ("\r", ("\r", "\r")),
          ("\r\n", ("\r\n", "\r\n")),
          (allNewlines, (allNewlines[...], allNewlines[...])),
          ("abc\ndef", ("abc\ndef", "\n")),
          ("abc\n\r\ndef", ("abc\n\r\ndef", "\n\r\n")),
          ("abc\(allNewlines)def", ("abc\(allNewlines)def", allNewlines[...])),
          ("abc", nil),
          matchType: (Substring, Substring).self, ==)
        {
          Regex {
            ZeroOrMore {
              cc.inverted
            }
            Capture {
              OneOrMore(cc)
            }
            ZeroOrMore {
              cc.inverted
            }
          }.matchingSemantics(mode)
        }
        
        // Try with ASCII-only whitespace.
        try _testDSLCaptures(
          ("\n", ("\n", "\n")),
          ("\r", ("\r", "\r")),
          ("\r\n", ("\r\n", "\r\n")),
          (allNewlines, (allNewlines[...], asciiNewlines[...])),
          ("abc\ndef", ("abc\ndef", "\n")),
          ("abc\n\r\ndef", ("abc\n\r\ndef", "\n\r\n")),
          ("abc\(allNewlines)def", ("abc\(allNewlines)def", asciiNewlines[...])),
          ("abc", nil),
          matchType: (Substring, Substring).self, ==)
        {
          Regex {
            ZeroOrMore {
              cc.inverted
            }
            Capture {
              OneOrMore(cc)
            }
            ZeroOrMore {
              cc.inverted
            }
          }.matchingSemantics(mode).asciiOnlyWhitespace()
        }
      }
    }
    
    // `.newlineSequence` in scalar mode may match a single `\r\n`.
    // `.verticalWhitespace` may not.
    for asciiOnly in [true, false] {
      try _testDSLCaptures(
        ("\r", "\r"),
        ("\r\n", "\r\n"),
        matchType: Substring.self, ==)
      {
        Regex {
          CharacterClass.newlineSequence
        }.matchingSemantics(.unicodeScalar).asciiOnlyWhitespace(asciiOnly)
      }
      try _testDSLCaptures(
        ("\r", nil),
        ("\r\n", nil),
        matchType: Substring.self, ==)
      {
        Regex {
          CharacterClass.newlineSequence.inverted
        }.matchingSemantics(.unicodeScalar).asciiOnlyWhitespace(asciiOnly)
      }
      try _testDSLCaptures(
        ("\r", "\r"),
        ("\r\n", nil),
        matchType: Substring.self, ==)
      {
        Regex {
          CharacterClass.verticalWhitespace
        }.matchingSemantics(.unicodeScalar).asciiOnlyWhitespace(asciiOnly)
      }
      try _testDSLCaptures(
        ("\r", nil),
        ("\r\n", nil),
        matchType: Substring.self, ==)
      {
        Regex {
          CharacterClass.verticalWhitespace.inverted
        }.matchingSemantics(.unicodeScalar).asciiOnlyWhitespace(asciiOnly)
      }
      try _testDSLCaptures(
        ("\r", nil),
        ("\r\n", nil),
        matchType: Substring.self, ==)
      {
        Regex {
          CharacterClass.verticalWhitespace.inverted
          "\n"
        }.matchingSemantics(.unicodeScalar).asciiOnlyWhitespace(asciiOnly)
      }
    }
    
    // Make sure horizontal whitespace does not match newlines or other
    // vertical whitespace.
    try _testDSLCaptures(
      ("  \u{A0} \u{9}  \t ", "  \u{A0} \u{9}  \t "),
      (" \n", nil),
      (" \r", nil),
      (" \r\n", nil),
      (" \u{2028}", nil),
      matchType: Substring.self, ==)
    {
      OneOrMore(.horizontalWhitespace)
    }
    
    // Horizontal whitespace in ASCII mode.
    try _testDSLCaptures(
      ("   \u{9}  \t ", "   \u{9}  \t "),
      ("\u{A0}", nil),
      matchType: Substring.self, ==)
    {
      Regex {
        OneOrMore(.horizontalWhitespace)
      }.asciiOnlyWhitespace()
    }
  }
  
  func testCharacterClassOperations() throws {
    // Must have new stdlib for character class ranges.
    guard ensureNewStdlib() else { return }
    
    try _testDSLCaptures(
      ("bcdefn1a", "bcdefn1a"),
      ("nbcdef1a", nil),        // fails symmetric difference lookahead
      ("abcdef1a", nil),        // fails union
      ("bcdef3a", nil),         // fails subtraction
      ("bcdef1z", nil),         // fails intersection
      matchType: Substring.self, ==)
    {
      let disallowedChars = CharacterClass.hexDigit
        .symmetricDifference("a"..."z")
      NegativeLookahead(disallowedChars)      // No: 0-9 + g-z
      
      OneOrMore(("b"..."g").union("d"..."n"))         // b-n
      
      CharacterClass.digit.subtracting("3"..."9")     // 1, 2, non-ascii digits
      
      CharacterClass.hexDigit.intersection("a"..."z") // a-f
    }
  }
  
  func testAny() throws {
    // .any matches newlines regardless of matching options.
    for dotMatchesNewline in [true, false] {
      try _testDSLCaptures(
        ("abc\(allNewlines)def", "abc\(allNewlines)def"),
        matchType: Substring.self, ==)
      {
        Regex {
          OneOrMore(.any)
        }.dotMatchesNewlines(dotMatchesNewline)
      }
    }
    
    // `.anyGraphemeCluster` is the same as `.any` in grapheme mode.
    for mode in [RegexSemanticLevel.graphemeCluster, .unicodeScalar] {
      try _testDSLCaptures(
        ("a", "a"),
        ("\r\n", "\r\n"),
        ("e\u{301}", "e\u{301}"),
        ("e\u{301}f", nil),
        ("e\u{303}\u{301}\u{302}", "e\u{303}\u{301}\u{302}"),
        matchType: Substring.self, ==)
      {
        Regex {
          One(.anyGraphemeCluster)
        }.matchingSemantics(mode)
      }
      
      // Like `.any` it also always matches newlines.
      for dotMatchesNewline in [true, false] {
        try _testDSLCaptures(
          ("abc\(allNewlines)def", "abc\(allNewlines)def"),
          matchType: Substring.self, ==)
        {
          Regex {
            OneOrMore(.anyGraphemeCluster)
          }.matchingSemantics(mode).dotMatchesNewlines(dotMatchesNewline)
        }
      }
    }
  }
  
  func testAnyNonNewline() throws {
    // `.anyNonNewline` is `.` without single-line mode.
    for mode in [RegexSemanticLevel.graphemeCluster, .unicodeScalar] {
      for dotMatchesNewline in [true, false] {
        try _testDSLCaptures(
          ("abcdef", "abcdef"),
          ("abcdef\n", nil),
          ("\r\n", nil),
          ("\r", nil),
          ("\n", nil),
          matchType: Substring.self, ==)
        {
          Regex {
            OneOrMore(.anyNonNewline)
          }.matchingSemantics(mode).dotMatchesNewlines(dotMatchesNewline)
        }
        
        try _testDSLCaptures(
          ("abcdef", nil),
          ("abcdef\n", nil),
          ("\r\n", "\r\n"),
          ("\r", "\r"),
          ("\n", "\n"),
          matchType: Substring.self, ==)
        {
          Regex {
            OneOrMore(.anyNonNewline.inverted)
          }.matchingSemantics(mode).dotMatchesNewlines(dotMatchesNewline)
        }
        
        try _testDSLCaptures(
          ("abc", "abc"),
          ("abcd", nil),
          ("\r\n", nil),
          ("\r", nil),
          ("\n", nil),
          matchType: Substring.self, ==)
        {
          Regex {
            OneOrMore(CharacterClass.anyNonNewline.intersection(.anyOf("\n\rabc")))
          }.matchingSemantics(mode).dotMatchesNewlines(dotMatchesNewline)
        }
      }
    }
    
    try _testDSLCaptures(
      ("\r\n", "\r\n"), matchType: Substring.self, ==) {
        CharacterClass.anyNonNewline.inverted
      }
    try _testDSLCaptures(
      ("\r\n", nil), matchType: Substring.self, ==) {
        Regex {
          CharacterClass.anyNonNewline.inverted
        }.matchingSemantics(.unicodeScalar)
      }
  }
  
  func testMatchResultDotZeroWithoutCapture() throws {
    let match = try XCTUnwrap("aaa".wholeMatch { OneOrMore { "a" } })
    XCTAssertEqual(match.0, "aaa")
  }
  
  func testAlternation() throws {
    do {
      let regex = ChoiceOf {
        "aaa"
      }
      XCTAssertTrue("aaa".wholeMatch(of: regex)?.output == "aaa")
      XCTAssertNil("aab".wholeMatch(of: regex)?.output)
    }
    do {
      let regex = ChoiceOf {
        "aaa"
        "bbb"
        "ccc"
      }
      XCTAssertTrue("aaa".wholeMatch(of: regex)?.output == "aaa")
      XCTAssertNil("aab".wholeMatch(of: regex)?.output)
      XCTAssertTrue("bbb".wholeMatch(of: regex)?.output == "bbb")
      XCTAssertTrue("ccc".wholeMatch(of: regex)?.output == "ccc")
    }
    do {
      let regex = Regex {
        "ab"
        OneOrMore {
          Capture {
            ChoiceOf {
              "c"
              "def"
            }
          }
        }
      }
      XCTAssertTrue(
        try XCTUnwrap("abc".wholeMatch(of: regex)?.output) == ("abc", "c"))
    }
    do {
      let regex = ChoiceOf {
        "aaa"
        "bbb"
        "ccc"
      }
      XCTAssertTrue("aaa".wholeMatch(of: regex)?.output == "aaa")
      XCTAssertNil("aab".wholeMatch(of: regex)?.output)
      XCTAssertTrue("bbb".wholeMatch(of: regex)?.output == "bbb")
      XCTAssertTrue("ccc".wholeMatch(of: regex)?.output == "ccc")
    }
    do {
      let regex = ChoiceOf {
        Capture("aaa")
      }
      XCTAssertTrue(
        try XCTUnwrap("aaa".wholeMatch(of: regex)?.output) == ("aaa", "aaa"))
      XCTAssertNil("aab".wholeMatch(of: regex)?.output)
    }
    do {
      let regex = ChoiceOf {
        Capture("aaa")
        Capture("bbb")
        Capture("ccc")
      }
      XCTAssertTrue(
        try XCTUnwrap("aaa".wholeMatch(of: regex)?.output) == ("aaa", "aaa", nil, nil))
      XCTAssertTrue(
        try XCTUnwrap("bbb".wholeMatch(of: regex)?.output) == ("bbb", nil, "bbb", nil))
      XCTAssertTrue(
        try XCTUnwrap("ccc".wholeMatch(of: regex)?.output) == ("ccc", nil, nil, "ccc"))
      XCTAssertNil("aab".wholeMatch(of: regex)?.output)
    }
  }
  
  func testCombinators() throws {
    try _testDSLCaptures(
      ("aaaabccccdddkj", ("aaaabccccdddkj", "b", "cccc", "d", "k", nil, "j")),
      matchType: (Substring, Substring, Substring, Substring?, Substring, Substring?, Substring?).self, ==)
    {
      OneOrMore("a")
      Capture(OneOrMore(Character("b"))) // Substring
      Capture(ZeroOrMore("c")) // Substring
      ZeroOrMore(Capture(.hexDigit)) // Substring?
      Optionally("e")
      Capture {
        ChoiceOf {
          "t"
          "k"
        }
      } // Substring
      ChoiceOf { Capture("k"); Capture("j") } // (Substring?, Substring?)
    }
  }
  
  func testOptions() throws {
    try _testDSLCaptures(
      ("abc", "abc"),
      ("ABC", "ABC"),
      ("abcabc", "abcabc"),
      ("abcABCaBc", "abcABCaBc"),
      matchType: Substring.self, ==) {
        Regex {
          OneOrMore {
            "abc"
          }
        }.ignoresCase(true)
      }
    
    // Multiple options on one component wrap successively, but do not
    // override - equivalent to each option attached to a wrapping `Regex`.
    try _testDSLCaptures(
      ("abc", "abc"),
      ("ABC", "ABC"),
      ("abcabc", "abcabc"),
      ("abcABCaBc", "abcABCaBc"),
      matchType: Substring.self, ==) {
        Regex {
          OneOrMore {
            "abc"
          }
        }
        .ignoresCase(true)
        .ignoresCase(false)
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
        Regex {
          OneOrMore {
            Regex {
              "abc"
            }.ignoresCase(true)
            Optionally("de")
          }
        }
        .ignoresCase(false)
      }
    
    // FIXME: Re-enable this test
    try _testDSLCaptures(
      ("can't stop won't stop", ("can't stop won't stop", "can't", "won't")),
      matchType: (Substring, Substring, Substring).self, ==, xfail: true) {
        Capture {
          OneOrMore(.word)
          Anchor.wordBoundary
        }
        OneOrMore(.any, .reluctant)
        "stop"
        " "
        
        Capture {
          OneOrMore(.word)
          Anchor.wordBoundary
        }
        OneOrMore(.any, .reluctant)
        "stop"
      }
    
    // FIXME: Re-enable this test
    try _testDSLCaptures(
      ("can't stop won't stop", ("can't stop won't stop", "can", "won")),
      matchType: (Substring, Substring, Substring).self, ==, xfail: true) {
        Capture {
          OneOrMore(.word)
          Anchor.wordBoundary
        }
        OneOrMore(.any, .reluctant)
        "stop"
        " "
        
        Regex {
          Capture {
            OneOrMore(.word)
            Anchor.wordBoundary
          }
        }.wordBoundaryKind(.simple)
        
        OneOrMore(.any, .reluctant)
        "stop"
      }
    
    try _testDSLCaptures(
      ("abcdef123", ("abcdef123", "a", "123")),
      matchType: (Substring, Substring, Substring).self, ==) {
        Capture {
          // Reluctant behavior due to option
          Regex {
            OneOrMore(.anyOf("abcd"))
          }.repetitionBehavior(.reluctant)
        }
        ZeroOrMore("a"..."z")
        
        Capture {
          // Eager behavior due to explicit parameter, despite option
          Regex {
            OneOrMore(.digit, .eager)
          }.repetitionBehavior(.reluctant)
        }
        ZeroOrMore(.digit)
      }
    
    try _testDSLCaptures(
      ("abcdefg", ("abcdefg", "abcdefg")),
      ("abcdéfg", ("abcdéfg", "abcd")),
      matchType: (Substring, Substring).self, ==) {
        Regex {
          Capture {
            OneOrMore(.word)
          }
        }.asciiOnlyWordCharacters()
        
        ZeroOrMore(.any)
      }
  }
  
  func testQuantificationBehavior() throws {
    // Must have new stdlib for character class ranges.
    guard ensureNewStdlib() else { return }
    
    // Eager by default
    try _testDSLCaptures(
      ("abc1def2", ("abc1def2", "2")),
      matchType: (Substring, Substring).self, ==)
    {
      OneOrMore(.word)
      Capture(.digit)
      ZeroOrMore(.any)
    }
    
    // Explicitly reluctant
    try _testDSLCaptures(
      ("abc1def2", ("abc1def2", "1")),
      matchType: (Substring, Substring).self, ==)
    {
      OneOrMore(.word, .reluctant)
      Capture(.digit)
      ZeroOrMore(.any)
    }
    // Explicitly reluctant overrides default option
    try _testDSLCaptures(
      ("abc1def2", ("abc1def2", "1")),
      matchType: (Substring, Substring).self, ==)
    {
      Regex {
        OneOrMore(.reluctant) {
          One(.word)
        }
      }.repetitionBehavior(.possessive)
      Capture(.digit)
      ZeroOrMore(.any)
    }
    // Default set to reluctant
    try _testDSLCaptures(
      ("abc1def2", ("abc1def2", "1")),
      matchType: (Substring, Substring).self, ==)
    {
      Regex {
        OneOrMore(.word)
        Capture(.digit)
        ZeroOrMore(.any)
      }.repetitionBehavior(.reluctant)
    }
    // Default set to reluctant applies to regex syntax
    try _testDSLCaptures(
      ("abc1def2", ("abc1def2", "1")),
      matchType: (Substring, Substring).self, ==)
    {
      try! Regex(#"\w+(\d).*"#, as: (Substring, Substring).self)
        .repetitionBehavior(.reluctant)
    }
    
    // Explicitly possessive
    try _testDSLCaptures(
      ("aaaa", nil),
      matchType: Substring.self, ==)
    {
      Regex {
        OneOrMore("a", .possessive)
        "a"
      }
    }
    // Default set to possessive
    try _testDSLCaptures(
      ("aaaa", nil),
      matchType: Substring.self, ==)
    {
      Regex {
        OneOrMore("a")
        "a"
      }.repetitionBehavior(.possessive)
    }
    // More specific default set to eager
    try _testDSLCaptures(
      ("aaaa", ("aaaa", "aaa")),
      matchType: (Substring, Substring).self, ==)
    {
      Regex {
        Capture {
          Regex {
            OneOrMore("a")
          }.repetitionBehavior(.eager)
        }
        OneOrMore("a")
      }.repetitionBehavior(.possessive)
    }
    // More specific default set to reluctant
    try _testDSLCaptures(
      ("aaaa", ("aaaa", "a")),
      matchType: (Substring, Substring).self, ==)
    {
      Regex {
        Capture {
          Regex {
            OneOrMore("a")
          }.repetitionBehavior(.reluctant)
        }
        OneOrMore("a")
      }.repetitionBehavior(.possessive)
    }
    
    try _testDSLCaptures(
      ("abc1def2", "abc1def2"),
      matchType: Substring.self, ==)
    {
      Repeat(2...) {
        Repeat(count: 3) {
          CharacterClass.word
        }
        CharacterClass.digit
      }
    }
    
    try _testDSLCaptures(
      ("abcdef2", ("abcdef2", "f")),
      ("2", ("2", nil)),
      ("", ("", nil)),
      matchType: (Substring, Substring??).self, ==)
    {
      Optionally {
        ZeroOrMore {
          Capture(CharacterClass.word)
        }
        CharacterClass.digit
      }
    }
    
    try _testDSLCaptures(
      ("aaabbbcccdddeeefff", "aaabbbcccdddeeefff"),
      ("aaabbbcccccdddeeefff", "aaabbbcccccdddeeefff"),
      ("aaabbbcccddddeeefff", "aaabbbcccddddeeefff"),
      ("aaabbbccccccdddeeefff", nil),
      ("aaaabbbcccdddeeefff", nil),
      ("aaacccdddeeefff", nil),
      ("aaabbbcccccccdddeeefff", nil),
      ("aaabbbcccdddddeeefff", nil),
      ("aaabbbcccddddddeeefff", nil),
      ("aaabbbcccdddefff", nil),
      ("aaabbbcccdddeee", "aaabbbcccdddeee"),
      matchType: Substring.self, ==)
    {
      Repeat(count: 3) { "a" }
      Repeat(1...) { "b" }
      Repeat(2...5) { "c" }
      Repeat(..<5) { "d" }
      Repeat(2...) { "e" }
      Repeat(0...) { "f" }
    }
    
    try _testDSLCaptures(
      ("", nil),
      ("a", nil),
      ("aa", "aa"),
      ("aaa", "aaa"),
      matchType: Substring.self, ==)
    {
      Repeat(2...) { "a" }
    }
    
    try _testDSLCaptures(
      ("", ""),
      ("a", "a"),
      ("aa", "aa"),
      ("aaa", nil),
      matchType: Substring.self, ==)
    {
      Repeat(...2) { "a" }
    }
    
    try _testDSLCaptures(
      ("", ""),
      ("a", "a"),
      ("aa", nil),
      ("aaa", nil),
      matchType: Substring.self, ==)
    {
      Repeat(..<2) { "a" }
    }
    
    try _testDSLCaptures(
      ("", ""),
      ("a", nil),
      ("aa", nil),
      matchType: Substring.self, ==)
    {
      Repeat(...0) { "a" }
    }
    
    try _testDSLCaptures(
      ("", ""),
      ("a", nil),
      ("aa", nil),
      matchType: Substring.self, ==)
    {
      Repeat(0 ... 0) { "a" }
    }
    
    try _testDSLCaptures(
      ("", ""),
      ("a", nil),
      ("aa", nil),
      matchType: Substring.self, ==)
    {
      Repeat(count: 0) { "a" }
    }
    
    try _testDSLCaptures(
      ("", ""),
      ("a", "a"),
      ("aa", nil),
      matchType: Substring.self, ==)
    {
      Repeat(0 ... 1) { "a" }
    }
    
    try _testDSLCaptures(
      ("", nil),
      ("a", "a"),
      ("aa", "aa"),
      ("aaa", nil),
      matchType: Substring.self, ==)
    {
      Repeat(1 ... 2) { "a" }
    }
    
    try _testDSLCaptures(
      ("", ""),
      ("a", nil),
      ("aa", nil),
      matchType: Substring.self, ==)
    {
      Repeat(0 ..< 1) { "a" }
    }
    
    try _testDSLCaptures(
      ("", ""),
      ("a", "a"),
      ("aa", nil),
      matchType: Substring.self, ==)
    {
      Repeat(0 ..< 2) { "a" }
    }
    
    try _testDSLCaptures(
      ("", nil),
      ("a", "a"),
      ("aa", "aa"),
      ("aaa", nil),
      matchType: Substring.self, ==)
    {
      Repeat(1 ..< 3) { "a" }
    }
    
    let octoDecimalRegex: Regex<(Substring, Int?)> = Regex {
      let charClass = CharacterClass(.digit, "a"..."h")//.ignoringCase()
      Capture {
        OneOrMore(charClass)
      } transform: { Int($0, radix: 18) }
    }
    XCTAssertEqual("ab12".firstMatch(of: octoDecimalRegex)!.output.1, 61904)
  }
  
  func testLocal() throws {
    try _testDSLCaptures(
      ("aaaaa", nil),
      matchType: Substring.self, ==)
    {
      Local {
        OneOrMore("a")
      }
      "a"
    }
    
    try _testDSLCaptures(
      ("aa", "aa"),
      ("aaa", nil),
      matchType: Substring.self, ==)
    {
      Local {
        OneOrMore("a", .reluctant)
      }
      "a"
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
      OneOrMore("a")
      "b"
      Anchor.endOfLine
    }
    
    try _testDSLCaptures(
      ("Cafe\u{301}", nil),
      ("Cafe", "Cafe"),
      matchType: Substring.self, ==)
    {
      OneOrMore(.word)
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
      OneOrMore("a")
      Lookahead(CharacterClass.digit)
      NegativeLookahead { "2" }
      CharacterClass.word
    }
    
    try _testDSLCaptures(
      ("aaa", "aaa"),
      ("\naaa", nil),
      ("aaa\n", nil),
      ("\naaa\n", nil),
      matchType: Substring.self, ==)
    {
      Regex {
        Anchor.startOfSubject
        Repeat("a", count: 3)
        Anchor.endOfSubject
      }.anchorsMatchLineEndings()
    }
    
    try _testDSLCaptures(
      ("\naaa", "\naaa"),
      ("aaa\n", "aaa\n"),
      ("\naaa\n", "\naaa\n"),
      matchType: Substring.self, ==)
    {
      Regex {
        Optionally { "\n" }
        Anchor.startOfLine
        Repeat("a", count: 3)
        Anchor.endOfLine
        Optionally { "\n" }
      }
    }
    
    // startOfLine/endOfLine apply regardless of mode.
    for matchLineEndings in [true, false] {
      for mode in [RegexSemanticLevel.graphemeCluster, .unicodeScalar] {
        let r = Regex {
          Anchor.startOfLine
          Repeat("a", count: 3)
          Anchor.endOfLine
        }.anchorsMatchLineEndings(matchLineEndings).matchingSemantics(mode)
        
        XCTAssertNotNil(try r.firstMatch(in: "\naaa"))
        XCTAssertNotNil(try r.firstMatch(in: "aaa\n"))
        XCTAssertNotNil(try r.firstMatch(in: "\naaa\n"))
        XCTAssertNotNil(try r.firstMatch(in: "\naaa\r\n"))
        XCTAssertNotNil(try r.firstMatch(in: "\r\naaa\n"))
        XCTAssertNotNil(try r.firstMatch(in: "\r\naaa\r\n"))
        
        XCTAssertNil(try r.firstMatch(in: "\nbaaa\n"))
        XCTAssertNil(try r.firstMatch(in: "\naaab\n"))
      }
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
     OneOrMore {
     Capture(OneOrMore("b"))
     Capture(ZeroOrMore("c"))
     Capture("d").*
     "e".?
     }
     }
     */
  }
  
  func testCaptureTransform() throws {
    try _testDSLCaptures(
      ("aaaa1", ("aaaa1", "aaa")),
      matchType: (Substring, Substring).self, ==)
    {
      Capture {
        OneOrMore("a")
      } transform: {
        $0.dropFirst()
      }
      One(.digit)
    }
    try _testDSLCaptures(
      ("aaaa1", ("aaaa1", "a")),
      matchType: (Substring, Substring??).self, ==)
    {
      ZeroOrMore {
        Capture("a", transform: { Optional.some($0) })
      }
      One(.digit)
    }
  }
  
  func testCapturelessQuantification() throws {
    // This test is to make sure that a captureless quantification, when used
    // straight out of the quantifier (without being wrapped in a builder), is
    // able to produce a regex whose `Match` type does not contain any sort of
    // void.
    let regex = ZeroOrMore(.digit)
    // Assert the inferred capture type.
    let _: Substring.Type = type(of: regex).RegexOutput.self
    let input = "123123"
    let match = try XCTUnwrap(input.wholeMatch(of: regex)?.output)
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
      OneOrMore("a")
      OneOrMore(.whitespace)
      Optionally {
        Capture(OneOrMore(.digit)) { Int($0)! }
      }
      ZeroOrMore {
        OneOrMore(.whitespace)
        Capture(OneOrMore(.word)) { Word($0)! }
      }
    }
  }
  
  func testNestedCaptureTypes() throws {
    let regex1 = Regex {
      OneOrMore("a")
      Capture {
        Capture(OneOrMore("b"))
        Optionally("e")
      }
    }
    let _: (Substring, Substring, Substring).Type
    = type(of: regex1).RegexOutput.self
    
    let regex2 = Regex {
      OneOrMore("a")
      Capture {
        ZeroOrMore {
          TryCapture("b") { Int($0) }
        }
        Optionally("e")
      }
    }
    let _: (Substring, Substring, Int?).Type
    = type(of: regex2).RegexOutput.self
    
    let regex3 = Regex {
      OneOrMore("a")
      Capture {
        TryCapture("b", transform: { Int($0) })
        ZeroOrMore<(Substring, Double?)>(
          TryCapture("c", transform: { Double($0) })
        )
        Optionally("e")
      }
    }
    let _: (Substring, Substring, Int, Double?).Type
    = type(of: regex3).RegexOutput.self

    // FIXME: Remove explicit type and `subregex1` and `subregex2` when type checker regression is fixed
    let subregex1: Regex<(Substring, Substring?)> = Regex {
      ZeroOrMore(Capture("d"))
    }
    let subregex2: Regex<(
      Substring, Substring, Substring, Substring?
    )> = Regex {
      Capture(OneOrMore("b"))
      Capture(ZeroOrMore("c"))
      subregex1
      Optionally("e")
    }
    let regex4: Regex<(
      Substring, Substring, Substring, Substring, Substring?
    )> = Regex {
      OneOrMore("a")
      Capture {
        OneOrMore {
          subregex2
        }
      }
    }
    let _: (
      Substring, Substring, Substring, Substring, Substring?).Type
    = type(of: regex4).RegexOutput.self
  }
  
  func testUnicodeScalarPostProcessing() throws {
    let spaces = Regex {
      ZeroOrMore {
        One(.whitespace)
      }
    }
    
    let unicodeScalar = Regex {
      OneOrMore {
        One(.hexDigit)
      }
      spaces
    }
    
    let unicodeData = Regex {
      unicodeScalar
      Optionally {
        ".."
        unicodeScalar
      }
      
      ";"
      spaces
      
      Capture {
        OneOrMore(.word)
      }
      
      ZeroOrMore(.any)
    }
    
    // Assert the inferred capture type.
    let _: (Substring, Substring).Type = type(of: unicodeData).RegexOutput.self
    
    let unicodeLine =
    "1BCA0..1BCA3  ; Control # Cf   [4] SHORTHAND FORMAT LETTER OVERLAP..SHORTHAND FORMAT UP STEP"
    let match = try XCTUnwrap(unicodeLine.wholeMatch(of: unicodeData))
    XCTAssertEqual(match.0, Substring(unicodeLine))
    XCTAssertEqual(match.1, "Control")
  }
  
  func testGraphemeBreakData() throws {
    let line = """
      A6F0..A6F1    ; Extend # Mn   [2] BAMUM COMBINING MARK KOQNDON..BAMUM COMBINING MARK TUKWENTIS
      """
    
    let regexWithCapture = Regex {
      Capture {
        OneOrMore(.hexDigit)
      } transform: { Unicode.Scalar(hex: $0) }
      Optionally {
        ".."
        Capture {
          OneOrMore(.hexDigit)
        } transform: { Unicode.Scalar(hex: $0) }
      }
      OneOrMore(.whitespace)
      ";"
      OneOrMore(.whitespace)
      Capture(OneOrMore(.word))
      ZeroOrMore(.any)
    } // Regex<(Substring, Unicode.Scalar?, Unicode.Scalar??, Substring)>
    do {
      // Assert the inferred capture type.
      typealias ExpectedMatch = (
        Substring, Unicode.Scalar?, Unicode.Scalar??, Substring
      )
      let _: ExpectedMatch.Type = type(of: regexWithCapture).RegexOutput.self
      let maybeMatchResult = line.wholeMatch(of: regexWithCapture)
      let matchResult = try XCTUnwrap(maybeMatchResult)
      let (wholeMatch, lower, upper, propertyString) = matchResult.output
      XCTAssertEqual(wholeMatch, Substring(line))
      XCTAssertEqual(lower, Unicode.Scalar(0xA6F0))
      XCTAssertEqual(upper, Unicode.Scalar(0xA6F1))
      XCTAssertEqual(propertyString, "Extend")
    }
    
    let regexWithTryCapture = Regex {
      TryCapture {
        OneOrMore(.hexDigit)
      } transform: {
        Unicode.Scalar(hex: $0)
      }
      Optionally {
        ".."
        TryCapture {
          OneOrMore(.hexDigit)
        } transform: {
          Unicode.Scalar(hex: $0)
        }
      }
      OneOrMore(.whitespace)
      ";"
      OneOrMore(.whitespace)
      Capture(OneOrMore(.word))
      ZeroOrMore(.any)
    } // Regex<(Substring, Unicode.Scalar, Unicode.Scalar?, Substring)>
    do {
      // Assert the inferred capture type.
      typealias ExpectedMatch = (
        Substring, Unicode.Scalar, Unicode.Scalar?, Substring
      )
      let _: ExpectedMatch.Type = type(of: regexWithTryCapture).RegexOutput.self
      let maybeMatchResult = line.wholeMatch(of: regexWithTryCapture)
      let matchResult = try XCTUnwrap(maybeMatchResult)
      let (wholeMatch, lower, upper, propertyString) = matchResult.output
      XCTAssertEqual(wholeMatch, Substring(line))
      XCTAssertEqual(lower, Unicode.Scalar(0xA6F0))
      XCTAssertEqual(upper, Unicode.Scalar(0xA6F1))
      XCTAssertEqual(propertyString, "Extend")
    }
    
    do {
      let regexLiteral = try Regex(
        #"([0-9A-F]+)(?:\.\.([0-9A-F]+))?\s+;\s+(\w+).*"#,
        as: (Substring, Substring, Substring?, Substring).self)
      let maybeMatchResult = line.wholeMatch(of: regexLiteral)
      let matchResult = try XCTUnwrap(maybeMatchResult)
      let (wholeMatch, lower, upper, propertyString) = matchResult.output
      XCTAssertEqual(wholeMatch, Substring(line))
      XCTAssertEqual(lower, "A6F0")
      XCTAssertEqual(upper, "A6F1")
      XCTAssertEqual(propertyString, "Extend")
    }
  }
  
  func testBackreference() throws {
    try _testDSLCaptures(
      ("abc#41#42abcabcabc", ("abc#41#42abcabcabc", "abc", 42, "abc", nil)),
      matchType: (Substring, Substring, Int?, Substring?, Substring?).self, ==)
    {
      let a = Reference(Substring.self)
      let b = Reference(Int.self)
      Capture("abc", as: a)
      ZeroOrMore {
        TryCapture(as: b) {
          "#"
          OneOrMore(.digit)
        } transform: {
          Int($0.dropFirst())
        }
      }
      a
      ZeroOrMore {
        Capture(a)
      }
      Optionally {
        "b"
        Capture(a)
      }
    }
    
    // Match result referencing a `Reference`.
    do {
      let a = Reference(Substring.self)
      let b = Reference(Int.self)
      let regex = Regex {
        Capture("abc", as: a)
        ZeroOrMore {
          TryCapture(as: b) {
            "#"
            OneOrMore(.digit)
          } transform: {
            Int($0.dropFirst())
          }
        }
        a
        ZeroOrMore {
          Capture(b)
        }
        Optionally {
          Capture(a)
        }
      }
      let input = "abc#41#42abc#42#42"
      let result = try XCTUnwrap(input.wholeMatch(of: regex))
      XCTAssertEqual(result[a], "abc")
      XCTAssertEqual(result[b], 42)
    }
    
    do {
      let key = Reference(Substring.self)
      let value = Reference(Int.self)
      let input = "      "
      let regex = Regex {
        Capture(as: key) {
          Optionally {
            OneOrMore(.word)
          }
        }
        ":"
        Optionally {
          Capture(as: value) {
            OneOrMore(.digit)
          } transform: { Int($0)! }
        }
      }
      
      let result1 = try XCTUnwrap("age:123".wholeMatch(of: regex))
      XCTAssertEqual(result1[key], "age")
      XCTAssertEqual(result1[value], 123)
      
      let result2 = try XCTUnwrap(":567".wholeMatch(of: regex))
      XCTAssertEqual(result2[key], "")
      XCTAssertEqual(result2[value], 567)
      
      let result3 = try XCTUnwrap("status:".wholeMatch(of: regex))
      XCTAssertEqual(result3[key], "status")
      // Traps:
      // XCTAssertEqual(result3[value], nil)
    }
    
    // Post-hoc captured references
    // #"(?:\w\1|:(\w):)+"#
    try _testDSLCaptures(
      (":a:baca:o:boco", (":a:baca:o:boco", "o")),
      matchType: (Substring, Substring?).self,
      ==
    ) {
      // NOTE: "expression too complex to type check" when inferring the generic
      // parameter.
      OneOrMore {
        let a = Reference(Substring.self)
        ChoiceOf<(Substring, Substring?)> {
          Regex {
            One(.word)
            a
          }
          Regex {
            ":"
            Capture(.word, as: a)
            ":"
          }
        }
      }
    }
    
    // Post-hoc captured reference w/ attempted match before capture
    // #"(?:\w\1|(\w):)+"#
    //
    // This tests that the reference `a` simply fails to match instead of
    // erroring when encountered before a match is captured into `a`. The
    // matching process here goes like this:
    //  - the first time through, the first alternation is taken
    //    - `.word` matches on "a"
    //    - the `a` backreference fails on ":", because `a` hasn't matched yet
    //    - backtrack to the beginning of the input
    //  - now the second alternation is taken
    //    - `.word` matches on "a" and is captured as `a`
    //    - the literal ":" matches
    //  - proceeding from the position of the first "b" in the first alternation
    //    - `.word` matches on "b"
    //    - the `a` backreference now contains "a", and matches on "a"
    //  - proceeding from the position of the first "c" in the first alternation
    //    - `.word` matches on "c"
    //    - the `a` backreference still contains "a", and matches on "a"
    //  - proceeding from the position of the first "o" in the first alternation
    //    - `.word` matches on "o"
    //    - the `a` backreference still contains "a", so it fails on ":"
    //  - now the second alternation is taken
    //    - `.word` matches on "o" and is captured as `a`
    //    - the literal ":" matches
    //  - continuing as above from the second "b"...
    try _testDSLCaptures(
      ("a:bacao:boco", ("a:bacao:boco", "o")),
      matchType: (Substring, Substring?).self,
      ==
    ) {
      // NOTE: "expression too complex to type check" when inferring the generic
      // parameter.
      OneOrMore {
        let a = Reference(Substring.self)
        ChoiceOf<(Substring, Substring?)> {
          Regex {
            One(.word)
            a
          }
          Regex {
            Capture(.word, as: a)
            ":"
          }
        }
      }
    }
  }
  
  func testScalarMatching() throws {
    // RegexBuilder provides a RegexComponent conformance for UnicodeScalar. In
    // grapheme cluster mode, it should only match entire graphemes. It may
    // match a single scalar of a grapheme cluster in scalar semantic mode.
    XCTAssertNotNil("a".firstMatch(of: "a" as UnicodeScalar))
    XCTAssertNil("a\u{301}".firstMatch(of: "a" as UnicodeScalar))
    XCTAssertNotNil("a\u{301}".firstMatch(
      of: ("a" as UnicodeScalar).regex.matchingSemantics(.unicodeScalar)))
    
    let r1 = Regex {
      "a" as UnicodeScalar
    }
    XCTAssertNil(try r1.firstMatch(in: "a\u{301}"))
    XCTAssertNotNil(
      try r1.matchingSemantics(.unicodeScalar).firstMatch(in: "a\u{301}")
    )
    
    let r2 = Regex {
      CharacterClass.anyOf(["a" as UnicodeScalar, "👍"])
    }
    XCTAssertNil(try r2.firstMatch(in: "a\u{301}"))
    XCTAssertNotNil(
      try r2.matchingSemantics(.unicodeScalar).firstMatch(in: "a\u{301}")
    )
    
    let r3 = Regex {
      "👨" as UnicodeScalar
      "\u{200D}" as UnicodeScalar
      "👨" as UnicodeScalar
      "\u{200D}" as UnicodeScalar
      "👧" as UnicodeScalar
      "\u{200D}" as UnicodeScalar
      "👦" as UnicodeScalar
    }
    XCTAssertNotNil(try r3.firstMatch(in: "👨‍👨‍👧‍👦"))
    XCTAssertNotNil(try r3.wholeMatch(in: "👨‍👨‍👧‍👦"))
    XCTAssertNotNil(try r3.matchingSemantics(.unicodeScalar).firstMatch(in: "👨‍👨‍👧‍👦"))
    XCTAssertNotNil(try r3.matchingSemantics(.unicodeScalar).wholeMatch(in: "👨‍👨‍👧‍👦"))
    
    let r4 = Regex { "é" as UnicodeScalar }
    XCTAssertNotNil(
      try r4.firstMatch(in: "e\u{301}")
    )
    XCTAssertNotNil(
      try r4.firstMatch(in: "é")
    )
    
    let r5 = Regex {
      "e"
      "\u{301}" as UnicodeScalar
    }
    XCTAssertNotNil(try r5.firstMatch(in: "e\u{301}"))
    XCTAssertNotNil(try r5.firstMatch(in: "é"))
    
    let r6 = Regex {
      "abcde"
      "\u{301}"
    }
    XCTAssertNotNil(try r6.firstMatch(in: "abcde\u{301}"))
    XCTAssertNotNil(try r6.firstMatch(in: "abcdé"))
    
    let r7 = Regex {
      "e" as Character
      "\u{301}" as Character
    }
    XCTAssertNotNil(try r7.firstMatch(in: "e\u{301}"))
    XCTAssertNotNil(try r7.firstMatch(in: "é"))
    
    // You can't match a partial grapheme in grapheme semantic mode.
    let r8 = Regex {
      "👨" as UnicodeScalar
      "\u{200D}" as UnicodeScalar
      "👨" as UnicodeScalar
      "\u{200D}" as UnicodeScalar
      "👧" as UnicodeScalar
    }
    XCTAssertNil(try r8.firstMatch(in: "👨‍👨‍👧‍👦"))
    XCTAssertNil(try r8.wholeMatch(in: "👨‍👨‍👧‍👦"))
    XCTAssertNotNil(try r8.matchingSemantics(.unicodeScalar).firstMatch(in: "👨‍👨‍👧‍👦"))
    XCTAssertNil(try r8.matchingSemantics(.unicodeScalar).wholeMatch(in: "👨‍👨‍👧‍👦"))
    
    // Scalar coalescing occurs across nested concatenations and literals.
    let r9 = Regex {
      Regex {
        try! Regex(#"👨"#)
        "\u{200D}" as UnicodeScalar
        Regex {
          "👨" as UnicodeScalar
        }
      }
      Regex {
        Regex {
          "\u{200D}" as UnicodeScalar
          "👧"
        }
        try! Regex(#"\u{200D}👦"#)
      }
    }
    XCTAssertNotNil(try r9.firstMatch(in: "👨‍👨‍👧‍👦"))
    XCTAssertNotNil(try r9.wholeMatch(in: "👨‍👨‍👧‍👦"))
    XCTAssertNotNil(try r9.matchingSemantics(.unicodeScalar).firstMatch(in: "👨‍👨‍👧‍👦"))
    XCTAssertNotNil(try r9.matchingSemantics(.unicodeScalar).wholeMatch(in: "👨‍👨‍👧‍👦"))
    
    let r10 = Regex {
      "👨" as UnicodeScalar
      try! Regex(#"\u{200D 1F468 200D 1F467}"#)
      "\u{200D}" as UnicodeScalar
      "👦" as UnicodeScalar
    }
    XCTAssertNotNil(try r10.firstMatch(in: "👨‍👨‍👧‍👦"))
    XCTAssertNotNil(try r10.wholeMatch(in: "👨‍👨‍👧‍👦"))
    XCTAssertNotNil(try r10.matchingSemantics(.unicodeScalar).firstMatch(in: "👨‍👨‍👧‍👦"))
    XCTAssertNotNil(try r10.matchingSemantics(.unicodeScalar).wholeMatch(in: "👨‍👨‍👧‍👦"))
  }
  
  struct SemanticVersion: Equatable {
    var major: Int
    var minor: Int
    var patch: Int
    var dev: String?
  }
  struct SemanticVersionParser: CustomConsumingRegexComponent {
    typealias RegexOutput = SemanticVersion
    func consuming(
      _ input: String,
      startingAt index: String.Index,
      in bounds: Range<String.Index>
    ) throws -> (upperBound: String.Index, output: SemanticVersion)? {
      let regex = Regex {
        TryCapture<(Substring, Int)>(OneOrMore(.digit)) { Int($0) }
        "."
        TryCapture<(Substring, Int)>(OneOrMore(.digit)) { Int($0) }
        Optionally {
          "."
          TryCapture<(Substring, Int)>(OneOrMore(.digit)) { Int($0) }
        }
        Optionally {
          "-"
          Capture(OneOrMore(.word))
        }
      }
      
      guard let match = input[index..<bounds.upperBound].firstMatch(of: regex),
            match.range.lowerBound == index
      else { return nil }
      
      let result = SemanticVersion(
        major: match.output.1,
        minor: match.output.2,
        patch: match.output.3 ?? 0,
        dev: match.output.4.map(String.init))
      return (match.range.upperBound, result)
    }
  }
  
  func testTransformCapturedMatcherOutput() {
    let versions = [
      ("version: 1.0", "1.0.0"),
      ("version: 1.0.1", "1.0.1"),
      ("version: 12.100.5-dev", "12.100.5-dev"),
    ]
    let parser = Regex {
      "version:"
      OneOrMore(.whitespace)
      Capture {
        SemanticVersionParser()
      } transform: {
        "\($0.major).\($0.minor).\($0.patch)\($0.dev.map { "-\($0)" } ?? "")"
      }
    }
    for (str, version) in versions {
      XCTAssertEqual(str.wholeMatch(of: parser)?.1, version)
    }
  }
  
  func testZeroWidthConsumer() throws {
    struct Trace: CustomConsumingRegexComponent {
      typealias RegexOutput = Void
      var label: String
      init(_ label: String) { self.label = label }
      
      static var traceOutput = ""
      
      func consuming(_ input: String, startingAt index: String.Index, in bounds: Range<String.Index>) throws -> (upperBound: String.Index, output: Void)? {
        print("Matching '\(label)'", to: &Self.traceOutput)
        print(input, to: &Self.traceOutput)
        let dist = input.distance(from: input.startIndex, to: index)
        print(String(repeating: " ", count: dist) + "^", to: &Self.traceOutput)
        return (index, ())
      }
    }
    
    let regex = Regex {
      OneOrMore(.word)
      Trace("end of key")
      ":"
      Trace("start of value")
      OneOrMore(.word)
    }
    XCTAssertNotNil("hello:goodbye".firstMatch(of: regex))
    XCTAssertEqual(Trace.traceOutput, """
      Matching 'end of key'
      hello:goodbye
           ^
      Matching 'start of value'
      hello:goodbye
            ^
      
      """)
  }
  
  func testRegexComponentBuilderResultType() {
    // Test that the user can declare a closure or computed property marked with
    // `@RegexComponentBuilder` with `Regex` as the result type.
    @RegexComponentBuilder
    var unaryWithSingleNonRegex: Regex<Substring> {
      OneOrMore("a")
    }
    @RegexComponentBuilder
    var multiComponent: Regex<Substring> {
      OneOrMore("a")
      "b"
    }
    struct MyCustomRegex: RegexComponent {
      @RegexComponentBuilder
      var regex: Regex<Substring> {
        OneOrMore("a")
      }
    }
  }
  
  // rdar://96280236
  func testCharacterClassAnyCrash() {
    let regex = Regex {
      "{"
      Capture {
        OneOrMore {
          CharacterClass.any.subtracting(.anyOf("}"))
        }
      }
      "}"
    }
    
    func replace(_ template: String) throws -> String {
      var b = template
      while let result = try regex.firstMatch(in: b) {
        b.replaceSubrange(result.range, with: "foo")
      }
      return b
    }
    
    XCTAssertEqual(try replace("{bar}"), "foo")
  }
  
  func testOptionalNesting() throws {
    try _testDSLCaptures(
      ("a", ("a", nil)),
      ("", ("", nil)),
      ("b", ("b", "b")),
      ("bb", ("bb", "b")),
      matchType: (Substring, Substring?).self, ==)
    {
      try! Regex("(?:a|(b)*)?", as: (Substring, Substring?).self)
    }
    
    try _testDSLCaptures(
      ("a", ("a", nil)),
      ("", ("", nil)),
      ("b", ("b", "b")),
      ("bb", ("bb", "b")),
      matchType: (Substring, Substring??).self, ==)
    {
      Optionally {
        try! Regex("a|(b)*", as: (Substring, Substring?).self)
      }
    }
    
    try _testDSLCaptures(
      ("a", ("a", nil)),
      ("", ("", nil)),
      ("b", ("b", "b")),
      ("bb", ("bb", "b")),
      matchType: (Substring, Substring???).self, ==)
    {
      Optionally {
        ChoiceOf {
          try! Regex("a", as: Substring.self)
          try! Regex("(b)*", as: (Substring, Substring?).self)
        }
      }
    }
    
    try _testDSLCaptures(
      ("a", ("a", nil)),
      ("", ("", nil)),
      ("b", ("b", "b")),
      ("bb", ("bb", "b")),
      matchType: (Substring, Substring??).self, ==)
    {
      ChoiceOf {
        try! Regex("a", as: Substring.self)
        try! Regex("(b)*", as: (Substring, Substring?).self)
      }
    }
    
    try _testDSLCaptures(
      ("a", ("a", nil)),
      ("", ("", nil)),
      ("b", ("b", "b")),
      ("bb", ("bb", "b")),
      matchType: (Substring, Substring??).self, ==)
    {
      ChoiceOf {
        try! Regex("a", as: Substring.self)
        ZeroOrMore {
          try! Regex("(b)", as: (Substring, Substring).self)
        }
      }
    }
    
    try _testDSLCaptures(
      ("a", ("a", nil)),
      ("", ("", nil)),
      ("b", ("b", "b")),
      ("bb", ("bb", "b")),
      matchType: (Substring, Substring??).self, ==)
    {
      ChoiceOf {
        try! Regex("a", as: Substring.self)
        ZeroOrMore {
          Capture {
            try! Regex("b", as: Substring.self)
          }
        }
      }
    }
    
    let r = Regex {
      Optionally {
        Optionally {
          Capture {
            "a"
          }
        }
      }
    }
    if let _ = try r.wholeMatch(in: "")!.output.1 {
      XCTFail("Unexpected capture match")
    }
    if let _ = try r.wholeMatch(in: "a")!.output.1 {}
    else {
      XCTFail("Expected to match capture")
    }
  }
}

fileprivate let oneNumericField = "abc:123:def"
fileprivate let twoNumericFields = "abc:123:def:456:ghi"

@available(SwiftStdlib 5.7, *)
fileprivate let regexWithCapture = #/:(\d+):/#
@available(SwiftStdlib 5.7, *)
fileprivate let regexWithLabeledCapture = #/:(?<number>\d+):/#
@available(SwiftStdlib 5.7, *)
fileprivate let regexWithNonCapture = #/:(?:\d+):/#

@available(SwiftStdlib 5.7, *)
extension RegexDSLTests {
  func testLabeledCaptures_regularCapture() throws {
    // The output type of a regex with unlabeled captures is concatenated.
    let dslWithCapture = Regex {
      OneOrMore(.word)
      regexWithCapture
      OneOrMore(.word)
    }
    XCTAssert(type(of: dslWithCapture).self == Regex<(Substring, Substring)>.self)
    
    let output = try XCTUnwrap(oneNumericField.wholeMatch(of: dslWithCapture)?.output)
    XCTAssertEqual(output.0, oneNumericField[...])
    XCTAssertEqual(output.1, "123")
  }
  
  func testLabeledCaptures_labeledCapture() throws {
    guard #available(macOS 13, *) else {
      XCTSkip("Fix only exists on macOS 13")
      return
    }
    // The output type of a regex with a labeled capture is dropped.
    let dslWithLabeledCapture = Regex {
      OneOrMore(.word)
      regexWithLabeledCapture
      OneOrMore(.word)
    }
    XCTAssert(type(of: dslWithLabeledCapture).self == Regex<Substring>.self)
    
    let match = try XCTUnwrap(oneNumericField.wholeMatch(of: dslWithLabeledCapture))
    XCTAssertEqual(match.output, oneNumericField[...])
    
    // We can recover the ignored captures by converting to `AnyRegexOutput`.
    let anyOutput = AnyRegexOutput(match)
    XCTAssertEqual(anyOutput.count, 2)
    XCTAssertEqual(anyOutput[0].substring, oneNumericField[...])
    XCTAssertEqual(anyOutput[1].substring, "123")
    XCTAssertEqual(anyOutput["number"]?.substring, "123")
  }
  
  func testLabeledCaptures_coalescingWithCapture() throws {
    let coalescingWithCapture = Regex {
      "e" as Character
      #/\u{301}(\d*)/#
    }
    XCTAssertNotNil(try coalescingWithCapture.firstMatch(in: "e\u{301}"))
    XCTAssertNotNil(try coalescingWithCapture.firstMatch(in: "é"))
    
    let coalescingWithLabeledCapture = Regex {
      "e" as Character
      #/\u{301}(?<number>\d*)/#
    }
    XCTAssertNotNil(try coalescingWithLabeledCapture.firstMatch(in: "e\u{301}"))
    XCTAssertNotNil(try coalescingWithLabeledCapture.firstMatch(in: "é"))
  }
  
  func testLabeledCaptures_bothCapture() throws {
    guard #available(macOS 13, *) else {
      XCTSkip("Fix only exists on macOS 13")
      return
    }
    // Only the output type of a regex with a labeled capture is dropped,
    // outputs of other regexes in the same DSL are concatenated.
    let dslWithBothCaptures = Regex {
      OneOrMore(.word)
      regexWithCapture
      OneOrMore(.word)
      regexWithLabeledCapture
      OneOrMore(.word)
    }
    XCTAssert(type(of: dslWithBothCaptures).self == Regex<(Substring, Substring)>.self)
    
    let match = try XCTUnwrap(twoNumericFields.wholeMatch(of: dslWithBothCaptures))
    XCTAssertEqual(match.output.0, twoNumericFields[...])
    XCTAssertEqual(match.output.1, "123")
    
    let anyOutput = AnyRegexOutput(match)
    XCTAssertEqual(anyOutput.count, 3)
    XCTAssertEqual(anyOutput[0].substring, twoNumericFields[...])
    XCTAssertEqual(anyOutput[1].substring, "123")
    XCTAssertEqual(anyOutput[2].substring, "456")
  }
  
  func testLabeledCaptures_tooManyCapture() throws {
    guard #available(macOS 13, *) else {
      XCTSkip("Fix only exists on macOS 13")
      return
    }
    // The output type of a regex with too many captures is dropped.
    // "Too many" means the left and right output types would add up to >= 10.
    let alpha = "AAA:abcdefghijklm:123:456:"
    let regexWithTooManyCaptures = #/(a)(b)(c)(d)(e)(f)(g)(h)(i)(j)(k)(l)(m)/#
    let dslWithTooManyCaptures = Regex {
      Capture(OneOrMore(.word))
      ":"
      regexWithTooManyCaptures
      ":"
      TryCapture<(Substring, Int)>(OneOrMore(.word)) { Int($0) }
      #/:(\d+):/#
    }
    XCTAssert(type(of: dslWithTooManyCaptures).self
              == Regex<(Substring, Substring, Int, Substring)>.self)
    
    let match = try XCTUnwrap(alpha.wholeMatch(of: dslWithTooManyCaptures))
    XCTAssertEqual(match.output.0, alpha[...])
    XCTAssertEqual(match.output.1, "AAA")
    XCTAssertEqual(match.output.2, 123)
    XCTAssertEqual(match.output.3, "456")
    
    // All captures groups are available through `AnyRegexOutput`.
    let anyOutput = AnyRegexOutput(match)
    XCTAssertEqual(anyOutput.count, 17)
    XCTAssertEqual(anyOutput[0].substring, alpha[...])
    XCTAssertEqual(anyOutput[1].substring, "AAA")
    for (offset, letter) in "abcdefghijklm".enumerated() {
      XCTAssertEqual(anyOutput[offset + 2].substring, String(letter)[...])
    }
    XCTAssertEqual(anyOutput[15].substring, "123")
    XCTAssertEqual(anyOutput[15].value as? Int, 123)
    XCTAssertEqual(anyOutput[16].substring, "456")
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
