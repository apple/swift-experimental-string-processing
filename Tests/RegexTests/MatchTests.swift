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
@testable import _RegexParser
@testable @_spi(RegexBenchmark) @_spi(Foundation) import _StringProcessing
import TestSupport

struct MatchError: Error {
  var message: String
  init(_ message: String) {
    self.message = message
  }
}

// This just piggy-backs on the existing match testing to validate that
// literal patterns round trip correctly.
@available(SwiftStdlib 6.0, *)
func _roundTripLiteral(
  _ regexStr: String,
  syntax: SyntaxOptions
) throws -> Regex<AnyRegexOutput>? {
  guard let pattern = try Regex(regexStr, syntax: syntax)._literalPattern else {
    return nil
  }
  
  let remadeRegex = try Regex(pattern)
  XCTAssertEqual(pattern, remadeRegex._literalPattern)
  return remadeRegex
}

func _firstMatch(
  _ regexStr: String,
  input: String,
  validateOptimizations: Bool,
  semanticLevel: RegexSemanticLevel = .graphemeCluster,
  syntax: SyntaxOptions = .traditional
) throws -> (String, [String?])? {
  var regex = try Regex(regexStr, syntax: syntax).matchingSemantics(semanticLevel)
  let result = try regex.firstMatch(in: input)
  
  func validateSubstring(_ substringInput: Substring) throws {
    // Sometimes the characters we add to a substring merge with existing
    // string members. This messes up cross-validation, so skip the test.
    guard input == substringInput else { return }
    
    let substringResult = try regex.firstMatch(in: substringInput)
    switch (result, substringResult) {
    case (nil, nil):
      break
    case let (result?, substringResult?):
      if substringResult.range.upperBound > substringInput.endIndex {
        throw MatchError("Range exceeded substring upper bound for \(input) and \(regexStr)")
      }
      let stringMatch = input[result.range]
      let substringMatch = substringInput[substringResult.range]
      if stringMatch != substringMatch {
        throw MatchError("""
        Pattern: '\(regexStr)'
        String match returned: '\(stringMatch)'
        Substring match returned: '\(substringMatch)'
        """)
      }
    case (.some(let result), nil):
      throw MatchError("""
        Pattern: '\(regexStr)'
        Input: '\(input)'
        Substring '\(substringInput)' ('\(substringInput.base)')
        String match returned: '\(input[result.range])'
        Substring match returned: nil
        """)
    case (nil, .some(let substringResult)):
      throw MatchError("""
        Pattern: '\(regexStr)'
        Input: '\(input)'
        Substring '\(substringInput)' ('\(substringInput.base)')
        String match returned: nil
        Substring match returned: '\(substringInput[substringResult.range])'
        """)
    }
  }

  if #available(SwiftStdlib 6.0, *) {
    let roundTripRegex = try? _roundTripLiteral(regexStr, syntax: syntax)
    let roundTripResult = try? roundTripRegex?
      .matchingSemantics(semanticLevel)
      .firstMatch(in: input)?[0]
      .substring
    switch (result?[0].substring, roundTripResult) {
    case let (match?, rtMatch?):
      XCTAssertEqual(match, rtMatch)
    case (nil, nil):
      break // okay
    case let (match?, _):
      XCTFail("""
        Didn't match in round-tripped version of '\(regexStr)'
        For input '\(input)'
        Original: '\(regexStr)'
        _literalPattern: '\(roundTripRegex?._literalPattern ?? "<no pattern>")'
        """)
    case let (_, rtMatch?):
      XCTFail("""
        Incorrectly matched as '\(rtMatch)'
        For input '\(input)'
        Original: '\(regexStr)'
        _literalPattern: '\(roundTripRegex!._literalPattern!)'
        """)
    }
  }

  if !input.isEmpty {
    try validateSubstring("\(input)\(input.last!)".dropLast())
  }
  try validateSubstring("\(input)\n".dropLast())
  try validateSubstring("A\(input)Z".dropFirst().dropLast())
  do {
    // Test sub-character slicing
    let str = input + "\n"
    let prevIndex = str.unicodeScalars.index(str.endIndex, offsetBy: -1)
    try validateSubstring(str[..<prevIndex])
  }
  do {
    // Validate that we don't crash when sub-scalar slicing is used
    // Actual matching behavior is untested here
    let str = "\u{e9}\(input)e\u{e9}"
    let upper = str.utf8.index(before: str.endIndex)
    _ = try regex.firstMatch(in: str[..<upper])
    let lower = str.utf8.index(after: str.startIndex)
    _ = try regex.firstMatch(in: str[lower...])
  }

  if validateOptimizations {
    precondition(regex._forceAction(.addOptions(.disableOptimizations)))
    let unoptResult = try regex.firstMatch(in: input)
    if result != nil && unoptResult == nil {
      throw MatchError("match not found for unoptimized \(regexStr) in \(input)")
    }
    if result == nil && unoptResult != nil {
      throw MatchError("match not found in optimized \(regexStr) in \(input)")
    }
    if let result = result, let unoptResult = unoptResult {
      let optMatch = String(input[result.range])
      let unoptMatch = String(input[unoptResult.range])
      if optMatch != unoptMatch {
        throw MatchError("""

        Unoptimized regex returned: '\(unoptMatch)'
        Optimized regex returned: '\(optMatch)'
        """)
      }
    }
  }
  
  guard let result = result else { return nil }
  let caps = result.output.slices(from: input)
  return (String(input[result.range]), caps.map { $0.map(String.init) })
}

// TODO: multiple-capture variant
// TODO: unify with firstMatch below, etc.
func flatCaptureTest(
  _ regex: String,
  _ tests: (input: String, expect: [String?]?)...,
  syntax: SyntaxOptions = .traditional,
  dumpAST: Bool = false,
  xfail: Bool = false,
  validateOptimizations: Bool = true,
  semanticLevel: RegexSemanticLevel = .graphemeCluster,
  file: StaticString = #file,
  line: UInt = #line
) {
  for (test, expect) in tests {
    do {
      guard var (_, caps) = try? _firstMatch(
        regex,
        input: test,
        validateOptimizations: validateOptimizations,
        semanticLevel: semanticLevel,
        syntax: syntax
      ) else {
        if expect == nil {
          continue
        } else {
          throw MatchError("Match failed")
        }
      }
      // Peel off the whole match.
      caps.removeFirst()
      guard let expect = expect else {
        throw MatchError("""
            Match of \(test) succeeded where failure expected in \(regex)
            """)
      }
      let capStrs = caps.map { $0 == nil ? nil : String($0!) }
      guard expect.count == capStrs.count else {
        throw MatchError("""
          Capture count mismatch:
            \(expect)
            \(capStrs)
          """)
      }

      guard expect.elementsEqual(capStrs) else {
        throw MatchError("""
          Capture mismatch:
            \(expect)
            \(capStrs)
          """)
      }
    } catch {
      if !xfail {
        XCTFail("\(error)", file: file, line: line)
      }
    }
  }
}

/// Test whether a string matches or not
///
/// TODO: Configuration for whole vs partial string matching...
func matchTest(
  _ regex: String,
  _ tests: (input: String, expect: Bool)...,
  syntax: SyntaxOptions = .traditional,
  enableTracing: Bool = false,
  dumpAST: Bool = false,
  xfail: Bool = false,
  validateOptimizations: Bool = true,
  semanticLevel: RegexSemanticLevel = .graphemeCluster,
  file: StaticString = #file,
  line: UInt = #line
) {
  for (test, expect) in tests {
    firstMatchTest(
      regex,
      input: test,
      match: expect ? test : nil,
      syntax: syntax,
      enableTracing: enableTracing,
      dumpAST: dumpAST,
      xfail: xfail,
      validateOptimizations: validateOptimizations,
      semanticLevel: semanticLevel,
      file: file,
      line: line)
  }
}

// TODO: Adjust below to also check captures

/// Test the first match in a string, via `firstRange(of:)`
func firstMatchTest(
  _ regex: String,
  input: String,
  match: String?,
  syntax: SyntaxOptions = .traditional,
  enableTracing: Bool = false,
  dumpAST: Bool = false,
  xfail: Bool = false,
  validateOptimizations: Bool = true,
  semanticLevel: RegexSemanticLevel = .graphemeCluster,
  file: StaticString = #filePath,
  line: UInt = #line
) {
  do {
    let found = try _firstMatch(
      regex,
      input: input,
      validateOptimizations: validateOptimizations,
      semanticLevel: semanticLevel,
      syntax: syntax)?.0

    if xfail {
      XCTAssertNotEqual(found, match, file: file, line: line)
    } else {
      XCTAssertEqual(found, match, "Incorrect match", file: file, line: line)
    }
  } catch {
    if !xfail {
      XCTFail("\(error)", file: file, line: line)
    }
    return
  }
}

func firstMatchTests(
  _ regex: String,
  _ tests: (input: String, match: String?)...,
  syntax: SyntaxOptions = .traditional,
  enableTracing: Bool = false,
  dumpAST: Bool = false,
  xfail: Bool = false,
  semanticLevel: RegexSemanticLevel = .graphemeCluster,
  file: StaticString = #filePath,
  line: UInt = #line
) {
  for (input, match) in tests {
    firstMatchTest(
      regex,
      input: input,
      match: match,
      syntax: syntax,
      enableTracing: enableTracing,
      dumpAST: dumpAST,
      xfail: xfail,
      semanticLevel: semanticLevel,
      file: file,
      line: line)
  }
}

extension RegexTests {
  func testMatch() {
    firstMatchTest(
      "abc", input: "123abcxyz", match: "abc")
    firstMatchTest(
      #"abc\+d*"#, input: "123abc+xyz", match: "abc+")
    firstMatchTest(
      #"abc\+d*"#, input: "123abc+dddxyz", match: "abc+ddd")
    firstMatchTest(
      "a(b)", input: "123abcxyz", match: "ab")

    firstMatchTest(
      "(.)*(.*)", input: "123abcxyz", match: "123abcxyz")
    firstMatchTest(
      #"abc\d"#, input: "xyzabc123", match: "abc1")

    // MARK: Allowed combining characters

    firstMatchTest("e\u{301}", input: "e\u{301}", match: "e\u{301}")
    firstMatchTest("1\u{358}", input: "1\u{358}", match: "1\u{358}")
    firstMatchTest(#"\ \#u{361}"#, input: " \u{361}", match: " \u{361}")

    // MARK: Alternations

    firstMatchTest(
      "abc(?:de)+fghi*k|j", input: "123abcdefghijxyz", match: "j")
    firstMatchTest(
      "abc(?:de)+fghi*k|j", input: "123abcdedefghkxyz", match: "abcdedefghk")
    firstMatchTest(
      "a(?:b|c)?d", input: "123adxyz", match: "ad")
    firstMatchTest(
      "a(?:b|c)?d", input: "123abdxyz", match: "abd")
    firstMatchTest(
      "a(?:b|c)?d", input: "123acdxyz", match: "acd")
    firstMatchTest(
      "a?b??c+d+?e*f*?", input: "123abcdefxyz", match: "abcde")
    firstMatchTest(
      "a?b??c+d+?e*f*?", input: "123bcddefxyz", match: "bcd")
    firstMatchTest(
      "a|b?c", input: "123axyz", match: "a")
    firstMatchTest(
      "a|b?c", input: "123bcxyz", match: "bc")
    firstMatchTest(
      "(a|b)c", input: "123abcxyz", match: "bc")

    // Alternations with empty branches are permitted.
    firstMatchTest("|", input: "ab", match: "")
    firstMatchTest("(|)", input: "ab", match: "")
    firstMatchTest("a|", input: "ab", match: "a")
    firstMatchTest("a|", input: "ba", match: "")
    firstMatchTest("|b", input: "ab", match: "")
    firstMatchTest("|b", input: "ba", match: "")
    firstMatchTest("|b|", input: "ab", match: "")
    firstMatchTest("|b|", input: "ba", match: "")
    firstMatchTest("a|b|", input: "ab", match: "a")
    firstMatchTest("a|b|", input: "ba", match: "b")
    firstMatchTest("a|b|", input: "ca", match: "")
    firstMatchTest("||c|", input: "ab", match: "")
    firstMatchTest("||c|", input: "cb", match: "")
    firstMatchTest("|||", input: "ab", match: "")
    firstMatchTest("a|||d", input: "bc", match: "")
    firstMatchTest("a|||d", input: "abc", match: "a")
    firstMatchTest("a|||d", input: "d", match: "")

    // MARK: Unicode scalars

    firstMatchTest(
      #"a\u0065b\u{00000065}c\x65d\U00000065"#,
      input: "123aebecedexyz", match: "aebecede")

    firstMatchTest(
      #"\u{00000000000000000000000000A}"#,
      input: "123\nxyz", match: "\n")
    firstMatchTest(
      #"\x{00000000000000000000000000A}"#,
      input: "123\nxyz", match: "\n")
    firstMatchTest(
      #"\o{000000000000000000000000007}"#,
      input: "123\u{7}xyz", match: "\u{7}")

    firstMatchTest(#"\o{70}"#, input: "1238xyz", match: "8")
    firstMatchTest(#"\0"#, input: "123\0xyz", match: "\0")
    firstMatchTest(#"\01"#, input: "123\u{1}xyz", match: "\u{1}")
    firstMatchTest(#"\070"#, input: "1238xyz", match: "8")
    firstMatchTest(#"\07A"#, input: "123\u{7}Axyz", match: "\u{7}A")
    firstMatchTest(#"\08"#, input: "123\08xyz", match: "\08")
    firstMatchTest(#"\0707"#, input: "12387\u{1C7}xyz", match: "\u{1C7}")

    // code point sequence
    firstMatchTest(#"\u{61 62 63}"#, input: "123abcxyz", match: "abc")
    firstMatchTest(#"3\u{  61  62 63 }"#, input: "123abcxyz", match: "3abc")
    firstMatchTest(#"\u{61 62}\u{63}"#, input: "123abcxyz", match: "abc")
    firstMatchTest(#"\u{61}\u{62 63}"#, input: "123abcxyz", match: "abc")
    firstMatchTest(#"9|\u{61 62 63}"#, input: "123abcxyz", match: "abc")
    firstMatchTest(#"(?:\u{61 62 63})"#, input: "123abcxyz", match: "abc")
    firstMatchTest(#"23\u{61 62 63}xy"#, input: "123abcxyz", match: "23abcxy")

    // o + horn + dot_below
    firstMatchTest(
      #"\u{006f 031b 0323}"#,
      input: "\u{006f}\u{031b}\u{0323}",
      match: "\u{006f}\u{031b}\u{0323}"
    )

    // e + combining accents
    firstMatchTest(
      #"e\u{301 302 303}"#,
      input: "e\u{301}\u{302}\u{303}",
      match: "e\u{301}\u{302}\u{303}"
    )
    firstMatchTest(
      #"e\u{315 35C 301}"#,
      input: "e\u{301}\u{315}\u{35C}",
      match: "e\u{301}\u{315}\u{35C}"
    )
    firstMatchTest(
      #"e\u{301}\u{302 303}"#,
      input: "e\u{301}\u{302}\u{303}",
      match: "e\u{301}\u{302}\u{303}"
    )
    firstMatchTest(
      #"e\u{35C}\u{315 301}"#,
      input: "e\u{301}\u{315}\u{35C}",
      match: "e\u{301}\u{315}\u{35C}"
    )
    firstMatchTest(
      #"e\u{35C}\u{315 301}"#,
      input: "e\u{315}\u{301}\u{35C}",
      match: "e\u{315}\u{301}\u{35C}"
    )
    firstMatchTest(
      #"e\u{301}\de\u{302}"#,
      input: "e\u{301}0e\u{302}",
      match: "e\u{301}0e\u{302}"
    )
    firstMatchTest(
      #"(?x) e \u{35C} \u{315}(?#hello)\u{301}"#,
      input: "e\u{301}\u{315}\u{35C}",
      match: "e\u{301}\u{315}\u{35C}"
    )
    firstMatchTest(
      #"(?x) e \u{35C} \u{315 301}"#,
      input: "e\u{301}\u{315}\u{35C}",
      match: "e\u{301}\u{315}\u{35C}"
    )

    // We don't coalesce across groups.
    firstMatchTests(
      #"e\u{301}(?:\u{315}\u{35C})?"#,
      ("e\u{301}", "e\u{301}"),
      ("e\u{301}\u{315}\u{35C}", nil)
    )

    // Escape sequences that represent scalar values.
    firstMatchTest(#"\a[\b]\e\f\n\r\t"#,
                   input: "\u{7}\u{8}\u{1B}\u{C}\n\r\t",
                   match: "\u{7}\u{8}\u{1B}\u{C}\n\r\t")
    firstMatchTest(#"[\a][\b][\e][\f][\n][\r][\t]"#,
                   input: "\u{7}\u{8}\u{1B}\u{C}\n\r\t",
                   match: "\u{7}\u{8}\u{1B}\u{C}\n\r\t")

    // MARK: Quotes

    firstMatchTest(
      #"a\Q .\Eb"#,
      input: "123a .bxyz", match: "a .b")
    firstMatchTest(
      #"a\Q \Q \\.\Eb"#,
      input: #"123a \Q \\.bxyz"#, match: #"a \Q \\.b"#)
    firstMatchTest(
      #"\d\Q...\E"#,
      input: "Countdown: 3... 2... 1...", match: "3...")

    // MARK: Comments

    firstMatchTest(
      #"a(?#comment)b"#, input: "123abcxyz", match: "ab")
    firstMatchTest(
      #"a(?#. comment)b"#, input: "123abcxyz", match: "ab")
  }

  func testMatchQuantification() {
    // MARK: Quantification

    firstMatchTest(
      #"a{1,2}"#, input: "123aaaxyz", match: "aa")
    firstMatchTest(
      #"a{ 1 , 2 }"#, input: "123aaaxyz", match: "aa")
    firstMatchTest(
      #"a{,2}"#, input: "123aaaxyz", match: "")
    firstMatchTest(
      #"a{ , 2 }"#, input: "123aaaxyz", match: "")
    firstMatchTest(
      #"a{,2}x"#, input: "123aaaxyz", match: "aax")
    firstMatchTest(
      #"a{,2}x"#, input: "123xyz", match: "x")
    firstMatchTest(
      #"a{2,}"#, input: "123aaaxyz", match: "aaa")
    firstMatchTest(
      #"a{1}"#, input: "123aaaxyz", match: "a")
    firstMatchTest(
      #"a{ 1 }"#, input: "123aaaxyz", match: "a")
    firstMatchTest(
      #"a{1,2}?"#, input: "123aaaxyz", match: "a")
    firstMatchTest(
      #"a{1,2}?x"#, input: "123aaaxyz", match: "aax")
    firstMatchTest(
      #"xa{0}y"#, input: "123aaaxyz", match: "xy")
    firstMatchTest(
      #"xa{0,0}y"#, input: "123aaaxyz", match: "xy")
    firstMatchTest(
      #"(a|a){2}a"#, input: "123aaaxyz", match: "aaa")
    firstMatchTest(
      #"(a|a){3}a"#, input: "123aaaxyz", match: nil)

    firstMatchTest("a.*", input: "dcba", match: "a")

    firstMatchTest("a*", input: "", match: "")
    firstMatchTest("a*", input: "a", match: "a")
    firstMatchTest("a*", input: "aaa", match: "aaa")

    firstMatchTest("a*?", input: "", match: "")
    firstMatchTest("a*?", input: "a", match: "")
    firstMatchTest("a*?a", input: "aaa", match: "a")
    firstMatchTest("xa*?x", input: "_xx__", match: "xx")
    firstMatchTest("xa*?x", input: "_xax__", match: "xax")
    firstMatchTest("xa*?x", input: "_xaax__", match: "xaax")

    firstMatchTest("a+", input: "", match: nil)
    firstMatchTest("a+", input: "a", match: "a")
    firstMatchTest("a+", input: "aaa", match: "aaa")

    firstMatchTest("a+?", input: "", match: nil)
    firstMatchTest("a+?", input: "a", match: "a")
    firstMatchTest("a+?a", input: "aaa", match: "aa")
    firstMatchTest("xa+?x", input: "_xx__", match: nil)
    firstMatchTest("xa+?x", input: "_xax__", match: "xax")
    firstMatchTest("xa+?x", input: "_xaax__", match: "xaax")

    firstMatchTest("a??", input: "", match: "")
    firstMatchTest("a??", input: "a", match: "")
    firstMatchTest("a??a", input: "aaa", match: "a")
    firstMatchTest("xa??x", input: "_xx__", match: "xx")
    firstMatchTest("xa??x", input: "_xax__", match: "xax")
    firstMatchTest("xa??x", input: "_xaax__", match: nil)

    // Possessive .* will consume entire input
    firstMatchTests(
      ".*+x",
      ("abc", nil), ("abcx", nil), ("", nil))

    firstMatchTests(
      "a+b",
      ("abc", "ab"),
      ("aaabc", "aaab"),
      ("b", nil))
    firstMatchTests(
      "a++b",
      ("abc", "ab"),
      ("aaabc", "aaab"),
      ("b", nil))
    firstMatchTests(
      "a+?b",
      ("abc", "ab"),
      ("aaabc", "aaab"), // firstRange will match from front
      ("b", nil))

    firstMatchTests(
      "a+a",
      ("babc", nil),
      ("baaabc", "aaa"),
      ("bb", nil))
    firstMatchTests(
      "a++a",
      ("babc", nil),
      ("baaabc", nil),
      ("bb", nil))
    firstMatchTests(
      "a+?a",
      ("babc", nil),
      ("baaabc", "aa"),
      ("bb", nil))


    firstMatchTests(
      "a{2,4}a",
      ("babc", nil),
      ("baabc", nil),
      ("baaabc", "aaa"),
      ("baaaaabc", "aaaaa"),
      ("baaaaaaaabc", "aaaaa"),
      ("bb", nil))
    firstMatchTests(
      "a{,4}a",
      ("babc", "a"),
      ("baabc", "aa"),
      ("baaabc", "aaa"),
      ("baaaaabc", "aaaaa"),
      ("baaaaaaaabc", "aaaaa"),
      ("bb", nil))
    firstMatchTests(
      "a{2,}a",
      ("babc", nil),
      ("baabc", nil),
      ("baaabc", "aaa"),
      ("baaaaabc", "aaaaa"),
      ("baaaaaaaabc", "aaaaaaaa"),
      ("bb", nil))

    firstMatchTests(
      "a{2,4}?a",
      ("babc", nil),
      ("baabc", nil),
      ("baaabc", "aaa"),
      ("baaaaabc", "aaa"),
      ("baaaaaaaabc", "aaa"),
      ("bb", nil))
    firstMatchTests(
      "a{,4}?a",
      ("babc", "a"),
      ("baabc", "a"),
      ("baaabc", "a"),
      ("baaaaabc", "a"),
      ("baaaaaaaabc", "a"),
      ("bb", nil))
    firstMatchTests(
      "a{2,}?a",
      ("babc", nil),
      ("baabc", nil),
      ("baaabc", "aaa"),
      ("baaaaabc", "aaa"),
      ("baaaaaaaabc", "aaa"),
      ("bb", nil))

    firstMatchTests(
      "a{2,4}+a",
      ("babc", nil),
      ("baabc", nil),
      ("baaaaabc", "aaaaa"),
      ("baaaaaaaabc", "aaaaa"),
      ("bb", nil))
    firstMatchTests(
      "a{,4}+a",
      ("baaaaabc", "aaaaa"),
      ("baaaaaaaabc", "aaaaa"),
      ("bb", nil))
    firstMatchTests(
      "a{2,}+a",
      ("babc", nil),
      ("baabc", nil),
      ("bb", nil))
    
    firstMatchTests(
      "a{2,4}+a",
      ("baaabc", nil))
    firstMatchTests(
      "a{,4}+a",
      ("babc", nil),
      ("baabc", nil),
      ("baaabc", nil))
    firstMatchTests(
      "a{2,}+a",
      ("baaabc", nil),
      ("baaaaabc", nil),
      ("baaaaaaaabc", nil))

    // XFAIL'd possessive tests
    firstMatchTests(
      "a?+a",
      ("a", nil),
      xfail: true)
    firstMatchTests(
      "(a|a)?+a",
      ("a", nil),
      xfail: true)
    firstMatchTests(
      "(a|a){2,4}+a",
      ("a", nil),
      ("aa", nil))
    firstMatchTests(
      "(a|a){2,4}+a",
      ("aaa", nil),
      ("aaaa", nil),
      xfail: true)

    firstMatchTests(
      "(?:a{2,4}?b)+",
      ("aab", "aab"),
      ("aabaabaab", "aabaabaab"),
      ("aaabaaaabaabab", "aaabaaaabaab")
      // TODO: Nested reluctant reentrant example, xfailed
    )

    // Reluctant by default - '*/+/.' and '*?/+?/.?' are swapped
    firstMatchTest("(?U)a*", input: "aaa", match: "")
    firstMatchTest("(?U)a*a", input: "aaa", match: "a")
    firstMatchTest("(?U)a*?", input: "aaa", match: "aaa")
    firstMatchTest("(?U)a*?a", input: "aaa", match: "aaa")

    firstMatchTest("(?U)a+", input: "aaa", match: "a")
    firstMatchTest("(?U)a+?", input: "aaa", match: "aaa")

    firstMatchTest("(?U)a?", input: "a", match: "")
    firstMatchTest("(?U)a?a", input: "aaa", match: "a")
    firstMatchTest("(?U)a??", input: "a", match: "a")
    firstMatchTest("(?U)a??a", input: "aaa", match: "aa")

    // TODO: After captures, easier to test these
  }

  func testQuantificationScalarSemantics() {
    // TODO: We want more thorough testing here, including "a{n,m}", "a?", etc.

    firstMatchTest("a*", input: "aaa\u{301}", match: "aa")
    firstMatchTest("a*", input: "aaa\u{301}", match: "aaa", semanticLevel: .unicodeScalar)
    firstMatchTest("a+", input: "aaa\u{301}", match: "aa")
    firstMatchTest("a+", input: "aaa\u{301}", match: "aaa", semanticLevel: .unicodeScalar)
    firstMatchTest("a?", input: "a\u{301}", match: "")
    firstMatchTest("a?", input: "a\u{301}", match: "a", semanticLevel: .unicodeScalar)

    firstMatchTest("[ab]*", input: "abab\u{301}", match: "aba")
    firstMatchTest("[ab]*", input: "abab\u{301}", match: "abab", semanticLevel: .unicodeScalar)
    firstMatchTest("[ab]+", input: "abab\u{301}", match: "aba")
    firstMatchTest("[ab]+", input: "abab\u{301}", match: "abab", semanticLevel: .unicodeScalar)
    firstMatchTest("[ab]?", input: "b\u{301}", match: "")
    firstMatchTest("[ab]?", input: "b\u{301}", match: "b", semanticLevel: .unicodeScalar)

    firstMatchTest(#"\s*"#, input: "  \u{301}", match: "  \u{301}")
    firstMatchTest(#"\s*"#, input: "  \u{301}", match: "  ", semanticLevel: .unicodeScalar)
    firstMatchTest(#"\s+"#, input: "  \u{301}", match: "  \u{301}")
    firstMatchTest(#"\s+"#, input: "  \u{301}", match: "  ", semanticLevel: .unicodeScalar)
    firstMatchTest(#"\s?"#, input: " \u{301}", match: " \u{301}")
    firstMatchTest(#"\s?"#, input: " \u{301}", match: " ", semanticLevel: .unicodeScalar)

    firstMatchTest(#".*?a"#, input: "xxa\u{301}xaZ", match: "xxa\u{301}xa")
    firstMatchTest(#".*?a"#, input: "xxa\u{301}xaZ", match: "xxa", semanticLevel: .unicodeScalar)
    firstMatchTest(#".+?a"#, input: "xxa\u{301}xaZ", match: "xxa\u{301}xa")
    firstMatchTest(#".+?a"#, input: "xxa\u{301}xaZ", match: "xxa", semanticLevel: .unicodeScalar)
    firstMatchTest(#".?a"#, input: "e\u{301}aZ", match: "e\u{301}a")
    firstMatchTest(#".?a"#, input: "e\u{301}aZ", match: "\u{301}a", semanticLevel: .unicodeScalar)

    firstMatchTest(#".+\u{301}"#, input: "aa\u{301}Z", match: nil)
    firstMatchTest(#".+\u{301}"#, input: "aa\u{301}Z", match: "aa\u{301}", semanticLevel: .unicodeScalar)
    firstMatchTest(#".*\u{301}"#, input: "\u{301}Z", match: "\u{301}")
    firstMatchTest(#".*\u{301}"#, input: "\u{301}Z", match: "\u{301}", semanticLevel: .unicodeScalar)

    firstMatchTest(#".?\u{301}"#, input: "aa\u{302}\u{301}Z", match: nil)
    firstMatchTest(#".?\u{301}.?Z"#, input: "aa\u{302}\u{301}Z", match: "\u{302}\u{301}Z", semanticLevel: .unicodeScalar)
    firstMatchTest(#".?.?\u{301}.?Z"#, input: "aa\u{302}\u{301}Z", match: "a\u{302}\u{301}Z", semanticLevel: .unicodeScalar)


    // TODO: other test cases?
  }

  func testMatchCharacterClasses() {
    // Must have new stdlib for character class ranges and word boundaries.
    guard ensureNewStdlib() else { return }

    // MARK: Character classes

    firstMatchTest(#"abc\d"#, input: "xyzabc123", match: "abc1")

    firstMatchTest(
      "[-|$^:?+*())(*-+-]", input: "123(abc)xyz", match: "(")
    firstMatchTest(
      "[-|$^:?+*())(*-+-]", input: "123-abcxyz", match: "-")
    firstMatchTest(
      "[-|$^:?+*())(*-+-]", input: "123^abcxyz", match: "^")

    firstMatchTest(
      "[a-b-c]", input: "123abcxyz", match: "a")
    firstMatchTest(
      "[a-b-c]", input: "123-abcxyz", match: "-")

    firstMatchTest("[-a-]", input: "123abcxyz", match: "a")
    firstMatchTest("[-a-]", input: "123-abcxyz", match: "-")

    firstMatchTest("[a-z]", input: "123abcxyz", match: "a")
    firstMatchTest("[a-z]", input: "123ABCxyz", match: "x")
    firstMatchTest("[a-z]", input: "123-abcxyz", match: "a")

    firstMatchTest("(?x)[ a - z ]+", input: " 123-abcxyz", match: "abcxyz")

    // Character class subtraction
    firstMatchTest("[a-d--a-c]", input: "123abcdxyz", match: "d")

    // Inverted character class
    matchTest(#"[^a]"#,
              ("💿", true),
              ("a\u{301}", true),
              ("A", true),
              ("a", false))

    matchTest(#"(?i)[a]"#,
              ("💿", false),
              ("a\u{301}", false),
              ("A", true),
              ("a", true))

    matchTest("[a]",
      ("a\u{301}", false))

    // CR-LF special case: \r\n is a single character with ascii value equal
    // to \n, so make sure the ascii bitset optimization handles this correctly
    matchTest("[\r\n]",
      ("\r\n", true),
      ("\n", false),
      ("\r", false))
    // check that in scalar mode this case is handled correctly
    // in scalar semantics the character "\r\n" in the character class is
    // interpreted as matching the scalars "\r" or "\n".
    // It does not fully match the character "\r\n" because the character class
    // in scalar mode will only match one scalar
    matchTest(
      "^[\r\n]$",
      ("\r", true),
      ("\n", true),
      ("\r\n", false),
      semanticLevel: .unicodeScalar)

    matchTest("[^\r\n]",
      ("\r\n", false),
      ("\n", true),
      ("\r", true))
    matchTest("[\n\r]",
      ("\n", true),
      ("\r", true),
      ("\r\n", false))

    let allNewlines = "\u{A}\u{B}\u{C}\u{D}\r\n\u{85}\u{2028}\u{2029}"
    let asciiNewlines = "\u{A}\u{B}\u{C}\u{D}\r\n"

    for level in [RegexSemanticLevel.graphemeCluster, .unicodeScalar] {
      firstMatchTest(
        #"\R+"#,
        input: "abc\(allNewlines)def", match: allNewlines,
        semanticLevel: level
      )
      firstMatchTest(
        #"\v+"#,
        input: "abc\(allNewlines)def", match: allNewlines,
        semanticLevel: level
      )
    }

    // In scalar mode, \R can match \r\n, \v cannot.
    firstMatchTest(
      #"\R"#, input: "\r\n", match: "\r\n", semanticLevel: .unicodeScalar)
    firstMatchTest(
      #"\v"#, input: "\r\n", match: "\r", semanticLevel: .unicodeScalar)
    firstMatchTest(
      #"\v\v"#, input: "\r\n", match: "\r\n", semanticLevel: .unicodeScalar)
    firstMatchTest(
      #"[^\v]"#, input: "\r\n", match: nil, semanticLevel: .unicodeScalar)

    // ASCII-only spaces.
    firstMatchTest(#"(?S)\R+"#, input: allNewlines, match: asciiNewlines)
    firstMatchTest(#"(?S)\v+"#, input: allNewlines, match: asciiNewlines)
    firstMatchTest(
      #"(?S)\R"#, input: "\r\n", match: "\r\n", semanticLevel: .unicodeScalar)
    firstMatchTest(
      #"(?S)\v"#, input: "\r\n", match: "\r", semanticLevel: .unicodeScalar)

    matchTest(
      #"[a]\u0301"#,
      ("a\u{301}", false),
      semanticLevel: .graphemeCluster)
    matchTest(
      #"[a]\u0301"#,
      ("a\u{301}", true),
      semanticLevel: .unicodeScalar)

    // Scalar matching in quoted sequences.
    firstMatchTests(
      "[\\Qe\u{301}\\E]",
      ("e", nil),
      ("E", nil),
      ("\u{301}", nil),
      (eDecomposed, eDecomposed),
      (eComposed, eComposed),
      ("E\u{301}", nil),
      ("\u{C9}", nil)
    )
    firstMatchTests(
      "[\\Qe\u{301}\\E]",
      ("e", "e"),
      ("E", nil),
      ("\u{301}", "\u{301}"),
      (eDecomposed, "e"),
      (eComposed, nil),
      ("E\u{301}", "\u{301}"),
      ("\u{C9}", nil),
      semanticLevel: .unicodeScalar
    )
    firstMatchTests(
      "(?i)[\\Qe\u{301}\\E]",
      ("e", nil),
      ("E", nil),
      ("\u{301}", nil),
      (eDecomposed, eDecomposed),
      (eComposed, eComposed),
      ("E\u{301}", "E\u{301}"),
      ("\u{C9}", "\u{C9}")
    )
    firstMatchTests(
      "(?i)[\\Qe\u{301}\\E]",
      ("e", "e"),
      ("E", "E"),
      ("\u{301}", "\u{301}"),
      (eDecomposed, "e"),
      (eComposed, nil),
      ("E\u{301}", "E"),
      ("\u{C9}", nil),
      semanticLevel: .unicodeScalar
    )

    // Scalar coalescing.
    firstMatchTests(
      #"[e\u{301}]"#,
      (eDecomposed, eDecomposed),
      (eComposed, eComposed),
      ("e", nil),
      ("\u{301}", nil)
    )
    firstMatchTests(
      #"[e\u{301}]"#,
      (eDecomposed, "e"),
      (eComposed, nil),
      ("e", "e"),
      ("\u{301}", "\u{301}"),
      semanticLevel: .unicodeScalar
    )
    firstMatchTests(
      #"[[[e\u{301}]]]"#,
      (eDecomposed, eDecomposed),
      (eComposed, eComposed),
      ("e", nil),
      ("\u{301}", nil)
    )
    firstMatchTests(
      #"[[[e\u{301}]]]"#,
      (eDecomposed, "e"),
      (eComposed, nil),
      ("e", "e"),
      ("\u{301}", "\u{301}"),
      semanticLevel: .unicodeScalar
    )
    firstMatchTests(
      #"[👨\u{200D}👩\u{200D}👧\u{200D}👦]"#,
      ("👨", nil),
      ("👩", nil),
      ("👧", nil),
      ("👦", nil),
      ("\u{200D}", nil),
      ("👨‍👩‍👧‍👦", "👨‍👩‍👧‍👦")
    )
    firstMatchTests(
      #"[👨\u{200D}👩\u{200D}👧\u{200D}👦]"#,
      ("👨", "👨"),
      ("👩", "👩"),
      ("👧", "👧"),
      ("👦", "👦"),
      ("\u{200D}", "\u{200D}"),
      ("👨‍👩‍👧‍👦", "👨"),
      semanticLevel: .unicodeScalar
    )
    firstMatchTests(
      #"[e\u{315}\u{301}\u{35C}]"#,
      ("e", nil),
      ("e\u{315}", nil),
      ("e\u{301}", nil),
      ("e\u{315}\u{301}\u{35C}", "e\u{315}\u{301}\u{35C}"),
      ("e\u{301}\u{315}\u{35C}", "e\u{301}\u{315}\u{35C}"),
      ("e\u{35C}\u{301}\u{315}", "e\u{35C}\u{301}\u{315}")
    )
    firstMatchTests(
      #"(?x) [ e \u{315} \u{301} \u{35C} ]"#,
      ("e", nil),
      ("e\u{315}", nil),
      ("e\u{301}", nil),
      ("e\u{315}\u{301}\u{35C}", "e\u{315}\u{301}\u{35C}"),
      ("e\u{301}\u{315}\u{35C}", "e\u{301}\u{315}\u{35C}"),
      ("e\u{35C}\u{301}\u{315}", "e\u{35C}\u{301}\u{315}")
    )

    // We don't coalesce across character classes.
    firstMatchTests(
      #"e[\u{315}\u{301}\u{35C}]"#,
      ("e", nil),
      ("e\u{315}", nil),
      ("e\u{315}\u{301}", nil),
      ("e\u{301}\u{315}\u{35C}", nil)
    )
    firstMatchTests(
      #"[e[\u{301}]]"#,
      ("e", "e"),
      ("\u{301}", "\u{301}"),
      ("e\u{301}", nil)
    )

    firstMatchTests(
      #"[a-z1\u{E9}-\u{302}\u{E1}3-59]"#,
      ("a", "a"),
      ("a\u{301}", "a\u{301}"),
      ("\u{E1}", "\u{E1}"),
      ("\u{E2}", nil),
      ("z", "z"),
      ("e", "e"),
      (eDecomposed, eDecomposed),
      (eComposed, eComposed),
      ("\u{302}", "\u{302}"),
      ("1", "1"),
      ("2", nil),
      ("3", "3"),
      ("4", "4"),
      ("5", "5"),
      ("6", nil),
      ("7", nil),
      ("8", nil),
      ("9", "9")
    )
    firstMatchTests(
      #"[ab-df-hik-lm]"#,
      ("a", "a"),
      ("b", "b"),
      ("c", "c"),
      ("d", "d"),
      ("e", nil),
      ("f", "f"),
      ("g", "g"),
      ("h", "h"),
      ("i", "i"),
      ("j", nil),
      ("k", "k"),
      ("l", "l"),
      ("m", "m")
    )
    firstMatchTests(
      #"[a-ce-fh-j]"#,
      ("a", "a"),
      ("b", "b"),
      ("c", "c"),
      ("d", nil),
      ("e", "e"),
      ("f", "f"),
      ("g", nil),
      ("h", "h"),
      ("i", "i"),
      ("j", "j")
    )


    // These can't compile in grapheme semantic mode, but make sure they work in
    // scalar semantic mode.
    firstMatchTests(
      #"[a\u{315}\u{301}-\u{302}]"#,
      ("a", "a"),
      ("\u{315}", "\u{315}"),
      ("\u{301}", "\u{301}"),
      ("\u{302}", "\u{302}"),
      ("\u{303}", nil),
      semanticLevel: .unicodeScalar
    )
    firstMatchTests(
      #"[\u{73}\u{323}\u{307}-\u{1E00}]"#,
      ("\u{73}", "\u{73}"),
      ("\u{323}", "\u{323}"),
      ("\u{307}", "\u{307}"),
      ("\u{400}", "\u{400}"),
      ("\u{500}", "\u{500}"),
      ("\u{1E00}", "\u{1E00}"),
      ("\u{1E01}", nil),
      ("\u{1E69}", nil),
      semanticLevel: .unicodeScalar
    )
    firstMatchTests(
      #"[a\u{302}-✅]"#,
      ("a", "a"),
      ("\u{302}", "\u{302}"),
      ("A\u{302}", "\u{302}"),
      ("E\u{301}", nil),
      ("a\u{301}", "a"),
      ("\u{E1}", nil),
      ("a\u{302}", "a"),
      ("\u{E2}", nil),
      ("\u{E3}", nil),
      ("\u{EF}", nil),
      ("e\u{301}", nil),
      ("e\u{302}", "\u{302}"),
      ("\u{2705}", "\u{2705}"),
      ("✅", "✅"),
      ("\u{376}", "\u{376}"),
      ("\u{850}", "\u{850}"),
      ("a\u{302}\u{315}", "a"),
      semanticLevel: .unicodeScalar
    )
    firstMatchTests(
      #"(?i)[a\u{302}-✅]"#,
      ("a", "a"),
      ("\u{302}", "\u{302}"),
      ("A\u{302}", "A"),
      ("E\u{301}", nil),
      ("a\u{301}", "a"),
      ("\u{E1}", nil),
      ("a\u{302}", "a"),
      ("\u{E2}", nil),
      ("\u{E3}", nil),
      ("\u{EF}", nil),
      ("e\u{301}", nil),
      ("e\u{302}", "\u{302}"),
      ("\u{2705}", "\u{2705}"),
      ("✅", "✅"),
      ("\u{376}", "\u{376}"),
      ("\u{850}", "\u{850}"),
      ("a\u{302}\u{315}", "a"),
      semanticLevel: .unicodeScalar
    )
    firstMatchTests(
      #"[e\u{301}-\u{302}]"#,
      ("a", nil),
      ("e", "e"),
      ("\u{302}", "\u{302}"),
      ("A\u{302}", "\u{302}"),
      ("E\u{301}", "\u{301}"),
      ("\u{C8}", nil),
      ("\u{C9}", nil),
      ("\u{CA}", nil),
      ("\u{CB}", nil),
      ("a\u{301}", "\u{301}"),
      ("a\u{302}", "\u{302}"),
      ("e\u{301}", "e"),
      ("e\u{302}", "e"),
      ("\u{E1}", nil),
      ("\u{E2}", nil),
      ("\u{E9}", nil),
      ("\u{EA}", nil),
      ("\u{EF}", nil),
      semanticLevel: .unicodeScalar
    )
    firstMatchTests(
      #"(?i)[e\u{301}-\u{302}]"#,
      ("a", nil),
      ("e", "e"),
      ("\u{302}", "\u{302}"),
      ("A\u{302}", "\u{302}"),
      ("E\u{301}", "E"),
      ("\u{C8}", nil),
      ("\u{C9}", nil),
      ("\u{CA}", nil),
      ("\u{CB}", nil),
      ("a\u{301}", "\u{301}"),
      ("a\u{302}", "\u{302}"),
      ("e\u{301}", "e"),
      ("e\u{302}", "e"),
      ("\u{E1}", nil),
      ("\u{E2}", nil),
      ("\u{E9}", nil),
      ("\u{EA}", nil),
      ("\u{EF}", nil),
      semanticLevel: .unicodeScalar
    )

    // Set operation scalar coalescing.
    firstMatchTests(
      #"[e\u{301}&&e\u{301}e\u{302}]"#,
      ("e", nil),
      ("\u{301}", nil),
      ("\u{302}", nil),
      ("e\u{301}", "e\u{301}"),
      ("e\u{302}", nil))
    firstMatchTests(
      #"[e\u{301}~~[[e\u{301}]e\u{302}]]"#,
      ("e", nil),
      ("\u{301}", nil),
      ("\u{302}", nil),
      ("e\u{301}", nil),
      ("e\u{302}", "e\u{302}"))
    firstMatchTests(
      #"[e\u{301}[e\u{303}]--[[e\u{301}]e\u{302}]]"#,
      ("e", nil),
      ("\u{301}", nil),
      ("\u{302}", nil),
      ("\u{303}", nil),
      ("e\u{301}", nil),
      ("e\u{302}", nil),
      ("e\u{303}", "e\u{303}"))

    firstMatchTests(
      #"(?x) [ e \u{301} [ e \u{303} ] -- [ [ e \u{301} ] e \u{302} ] ]"#,
      ("e", nil),
      ("\u{301}", nil),
      ("\u{302}", nil),
      ("\u{303}", nil),
      ("e\u{301}", nil),
      ("e\u{302}", nil),
      ("e\u{303}", "e\u{303}"))

    firstMatchTest("[-]", input: "123-abcxyz", match: "-")

    // These are metacharacters in certain contexts, but normal characters
    // otherwise.
    firstMatchTest(":-]", input: "123:-]xyz", match: ":-]")

    firstMatchTest(
      "[^abc]", input: "123abcxyz", match: "1")
    firstMatchTest(
      "[a^]", input: "123abcxyz", match: "a")

    firstMatchTest(
      #"\D\S\W"#, input: "123ab-xyz", match: "ab-")

    firstMatchTest(
      #"[\dd]"#, input: "xyzabc123", match: "1")
    firstMatchTest(
      #"[\dd]"#, input: "xyzabcd123", match: "d")

    firstMatchTest(
      #"[^[\D]]"#, input: "xyzabc123", match: "1")
    firstMatchTest(
      "[[ab][bc]]", input: "123abcxyz", match: "a")
    firstMatchTest(
      "[[ab][bc]]", input: "123cbaxyz", match: "c")
    firstMatchTest(
      "[[ab]c[de]]", input: "123abcxyz", match: "a")
    firstMatchTest(
      "[[ab]c[de]]", input: "123cbaxyz", match: "c")

    firstMatchTest(
      #"[ab[:space:]\d[:^upper:]cd]"#,
      input: "123abcxyz", match: "1")
    firstMatchTest(
      #"[ab[:space:]\d[:^upper:]cd]"#,
      input: "xyzabc123", match: "x")
    firstMatchTest(
      #"[ab[:space:]\d[:^upper:]cd]"#,
      input: "XYZabc123", match: "a")
    firstMatchTest(
      #"[ab[:space:]\d[:^upper:]cd]"#,
      input: "XYZ abc123", match: " ")

    firstMatchTest("[[[:space:]]]", input: "123 abc xyz", match: " ")

    firstMatchTest("[[:alnum:]]", input: "[[:alnum:]]", match: "a")
    firstMatchTest("[[:blank:]]", input: "123\tabc xyz", match: "\t")

    firstMatchTest(
      "[[:graph:]]",
      input: "\u{7}\u{1b}\u{a}\n\r\t abc", match: "a")
    firstMatchTest(
      "[[:print:]]",
      input: "\u{7}\u{1b}\u{a}\n\r\t abc", match: " ")

    firstMatchTest(
      "[[:word:]]",
      input: "\u{7}\u{1b}\u{a}\n\r\t abc", match: "a")
    firstMatchTest(
      "[[:xdigit:]]",
      input: "\u{7}\u{1b}\u{a}\n\r\t abc", match: "a")

    firstMatchTest("[[:isALNUM:]]", input: "[[:alnum:]]", match: "a")
    firstMatchTest("[[:AL_NUM:]]", input: "[[:alnum:]]", match: "a")

    firstMatchTest("[[:script=Greek:]]", input: "123αβγxyz", match: "α")

    func scalar(_ u: UnicodeScalar) -> UInt32 { u.value }

    for s in scalar("\u{C}") ... scalar("\u{1B}") {
      let u = UnicodeScalar(s)!
      firstMatchTest(#"[\f-\e]"#, input: "\u{B}\u{1C}\(u)", match: "\(u)")
    }
    for u: UnicodeScalar in ["\u{7}", "\u{8}"] {
      firstMatchTest(#"[\a-\b]"#, input: "\u{6}\u{9}\(u)", match: "\(u)")
    }
    for s in scalar("\u{A}") ... scalar("\u{D}") {
      let u = UnicodeScalar(s)!
      firstMatchTest(#"[\n-\r]"#, input: "\u{9}\u{E}\(u)", match: "\(u)")
    }
    firstMatchTest(#"[\t-\t]"#, input: "\u{8}\u{A}\u{9}", match: "\u{9}")

    firstMatchTest(#"[12]"#, input: "1️⃣", match: nil)
    firstMatchTest(#"[1-2]"#, input: "1️⃣", match: nil)
    firstMatchTest(#"[\d]"#, input: "1️⃣", match: "1️⃣")
    firstMatchTest(#"(?P)[\d]"#, input: "1️⃣", match: nil)
    firstMatchTest("[0-2&&1-3]", input: "1️⃣", match: nil)
    firstMatchTest("[1-2e\u{301}]", input: "1️⃣", match: nil)

    firstMatchTest(#"[\u{3A9}-\u{3A9}]"#, input: "\u{3A9}", match: "\u{3A9}")

    // Currently not supported in the matching engine.
    for c: UnicodeScalar in ["a", "b", "c"] {
      firstMatchTest(#"[\c!-\C-#]"#, input: "def\(c)", match: "\(c)",
                     xfail: true)
    }
    for c: UnicodeScalar in ["$", "%", "&", "'"] {
      firstMatchTest(#"[\N{DOLLAR SIGN}-\N{APOSTROPHE}]"#,
                     input: "#()\(c)", match: "\(c)", xfail: true)
    }

    // MARK: Operators

    firstMatchTest(
      #"[a[bc]de&&[^bc]\d]+"#, input: "123bcdxyz", match: "d")

    // Empty intersection never matches, should this be a compile time error?
    // matchTest("[a&&b]", input: "123abcxyz", match: "")

    firstMatchTest(
      "[abc--def]", input: "123abcxyz", match: "a")

    // We left-associate for chained operators.
    firstMatchTest(
      "[ab&&b~~cd]", input: "123abcxyz", match: "b")
    firstMatchTest(
      "[ab&&b~~cd]", input: "123acdxyz", match: "c") // this doesn't match NSRegularExpression's behavior

    // Operators are only valid in custom character classes.
    firstMatchTest(
      "a&&b", input: "123a&&bcxyz", match: "a&&b")
    firstMatchTest(
      "&?", input: "123a&&bcxyz", match: "")
    firstMatchTest(
      "&&?", input: "123a&&bcxyz", match: "&&")
    firstMatchTest(
      "--+", input: "123---xyz", match: "---")
    firstMatchTest(
      "~~*", input: "123~~~xyz", match: "~~~")


    // Quotes in character classes.
    firstMatchTest(#"[\Qabc\E]"#, input: "QEa", match: "a")
    firstMatchTest(#"[\Qabc\E]"#, input: "cxx", match: "c")
    firstMatchTest(#"[\Qabc\E]+"#, input: "cba", match: "cba")
    firstMatchTest(#"[\Qa-c\E]+"#, input: "a-c", match: "a-c")

    firstMatchTest(#"["a-c"]+"#, input: "abc", match: "a",
                   syntax: .experimental)
    firstMatchTest(#"["abc"]+"#, input: "cba", match: "cba",
                   syntax: .experimental)
    firstMatchTest(#"["abc"]+"#, input: #""abc""#, match: "abc",
                   syntax: .experimental)
    firstMatchTest(#"["abc"]+"#, input: #""abc""#, match: #""abc""#)

    for semantics in [RegexSemanticLevel.unicodeScalar, .graphemeCluster] {
      // Case sensitivity and ranges.
      for ch in "abcD" {
        firstMatchTest("[a-cD]", input: String(ch), match: String(ch))
      }
      for ch in "ABCd" {
        firstMatchTest("[a-cD]", input: String(ch), match: nil)
      }
      for ch in "abcABCdD" {
        let input = String(ch)
        firstMatchTest(
          "(?i)[a-cd]", input: input, match: input, semanticLevel: semantics)
        firstMatchTest(
          "(?i)[A-CD]", input: input, match: input, semanticLevel: semantics)
      }
      for ch in "XYZ[\\]^_`abcd" {
        let input = String(ch)
        firstMatchTest(
          "[X-cd]", input: input, match: input, semanticLevel: semantics)
      }
      for ch in "XYZ[\\]^_`abcxyzABCdD" {
        let input = String(ch)
        firstMatchTest(
          "(?i)[X-cd]", input: input, match: input, semanticLevel: semantics)
        firstMatchTest(
          "(?i)[X-cD]", input: input, match: input, semanticLevel: semantics)
      }
    }
  }

  func testCharacterProperties() {
    // MARK: Character names.

    firstMatchTest(#"\N{ASTERISK}"#, input: "123***xyz", match: "*")
    firstMatchTest(#"[\N{ASTERISK}]"#, input: "123***xyz", match: "*")
    firstMatchTest(
      #"\N{ASTERISK}+"#, input: "123***xyz", match: "***")
    firstMatchTest(
      #"\N {2}"#, input: "123  xyz", match: "3  ", xfail: true)

    firstMatchTest(#"\N{U+2C}"#, input: "123,xyz", match: ",")
    firstMatchTest(#"\N{U+1F4BF}"#, input: "123💿xyz", match: "💿")
    firstMatchTest(#"\N{U+00001F4BF}"#, input: "123💿xyz", match: "💿")

    // MARK: Character properties.

    firstMatchTest(#"\p{L}"#, input: "123abcXYZ", match: "a")
    firstMatchTest(#"\p{gc=L}"#, input: "123abcXYZ", match: "a")
    firstMatchTest(#"\p{Lu}"#, input: "123abcXYZ", match: "X")

    // U+0374 GREEK NUMERAL SIGN (Lm)
    // U+00AA FEMININE ORDINAL INDICATOR (Lo)
    firstMatchTest(#"\p{L}"#, input: "\u{0374}\u{00AA}123abcXYZ", match: "\u{0374}")
    firstMatchTest(#"\p{Lc}"#, input: "\u{0374}\u{00AA}123abcXYZ", match: "a")
    firstMatchTest(#"\p{Lc}"#, input: "\u{0374}\u{00AA}123XYZ", match: "X")
    firstMatchTest(#"\p{L&}"#, input: "\u{0374}\u{00AA}123abcXYZ", match: "a")
    firstMatchTest(#"\p{L&}"#, input: "\u{0374}\u{00AA}123XYZ", match: "X")

    firstMatchTest(
      #"\P{Cc}"#, input: "\n\n\nXYZ", match: "X")
    firstMatchTest(
      #"\P{Z}"#, input: "   XYZ", match: "X")

    firstMatchTest(#"[\p{C}]"#, input: "123\n\n\nXYZ", match: "\n")
    firstMatchTest(#"\p{C}+"#, input: "123\n\n\nXYZ", match: "\n\n\n")

    // UAX44-LM3 means all of the below are equivalent.
    firstMatchTest(#"\p{ll}"#, input: "123abcXYZ", match: "a")
    firstMatchTest(#"\p{gc=ll}"#, input: "123abcXYZ", match: "a")
    firstMatchTest(
      #"\p{General_Category=Ll}"#, input: "123abcXYZ", match: "a")
    firstMatchTest(
      #"\p{General-Category=isLl}"#,
      input: "123abcXYZ", match: "a")
    firstMatchTest(#"\p{  __l_ l  _ }"#, input: "123abcXYZ", match: "a")
    firstMatchTest(
      #"\p{ g_ c =-  __l_ l  _ }"#, input: "123abcXYZ", match: "a")
    firstMatchTest(
      #"\p{ general ca-tegory =  __l_ l  _ }"#,
      input: "123abcXYZ", match: "a")
    firstMatchTest(
      #"\p{- general category =  is__l_ l  _ }"#,
      input: "123abcXYZ", match: "a")
    firstMatchTest(
      #"\p{ general category -=  IS__l_ l  _ }"#,
      input: "123abcXYZ", match: "a")

    firstMatchTest(#"\p{Any}"#, input: "123abcXYZ", match: "1")
    firstMatchTest(#"\p{Assigned}"#, input: "123abcXYZ", match: "1")
    firstMatchTest(#"\p{ascii}"#, input: "123abcXYZ", match: "1")
    firstMatchTest(#"\p{isAny}"#, input: "123abcXYZ", match: "1")

    firstMatchTest(#"\p{sc=grek}"#, input: "123αβγxyz", match: "α")
    firstMatchTest(#"\p{sc=isGreek}"#, input: "123αβγxyz", match: "α")
    firstMatchTest(#"\p{Greek}"#, input: "123αβγxyz", match: "α")
    firstMatchTest(#"\p{isGreek}"#, input: "123αβγxyz", match: "α")
    firstMatchTest(#"\P{Script=Latn}"#, input: "abcαβγxyz", match: "α")
    firstMatchTest(#"\p{script=Greek}"#, input: "123αβγxyz", match: "α")
    firstMatchTest(#"\p{ISscript=isGreek}"#, input: "123αβγxyz", match: "α")
    firstMatchTest(#"\p{scx=bamum}"#, input: "123ꚠꚡꚢxyz", match: "ꚠ")
    firstMatchTest(#"\p{ISBAMUM}"#, input: "123ꚠꚡꚢxyz", match: "ꚠ")
    firstMatchTest(#"\p{Script=Unknown}"#, input: "\u{10FFFF}", match: "\u{10FFFF}")
    firstMatchTest(#"\p{scx=Gujr}"#, input: "\u{a839}", match: "\u{a839}")
    firstMatchTest(#"\p{Gujr}"#, input: "\u{a839}", match: "\u{a839}")

    firstMatchTest(#"\p{alpha}"#, input: "123abcXYZ", match: "a")
    firstMatchTest(#"\P{alpha}"#, input: "123abcXYZ", match: "1")
    firstMatchTest(
      #"\p{alphabetic=True}"#, input: "123abcXYZ", match: "a")

    // This is actually available-ed...
    firstMatchTest(
      #"\p{emoji=t}"#, input: "123💿xyz", match: "a",
      xfail: true)

    firstMatchTest(#"\p{Alpha=no}"#, input: "123abcXYZ", match: "1")
    firstMatchTest(#"\P{Alpha=no}"#, input: "123abcXYZ", match: "a")
    firstMatchTest(#"\p{isAlphabetic}"#, input: "123abcXYZ", match: "a")
    firstMatchTest(
      #"\p{isAlpha=isFalse}"#, input: "123abcXYZ", match: "1")

    // Oniguruma special support not in stdlib
    firstMatchTest(
      #"\p{In_Runic}"#, input: "123ᚠᚡᚢXYZ", match: "ᚠ",
    xfail: true)

    // TODO: PCRE special
    firstMatchTest(
      #"\p{Xan}"#, input: "[[:alnum:]]", match: "a",
      xfail: true)
    firstMatchTest(
      #"\p{Xps}"#, input: "123 abc xyz", match: " ",
      xfail: true)
    firstMatchTest(
      #"\p{Xsp}"#, input: "123 abc xyz", match: " ",
      xfail: true)
    firstMatchTest(
      #"\p{Xuc}"#, input: "$var", match: "$",
      xfail: true)
    firstMatchTest(
      #"\p{Xwd}"#, input: "[[:alnum:]]", match: "a",
      xfail: true)

    firstMatchTest(#"\p{alnum}"#, input: "[[:alnum:]]", match: "a")
    firstMatchTest(#"\p{is_alnum}"#, input: "[[:alnum:]]", match: "a")

    firstMatchTest(#"\p{blank}"#, input: "123\tabc xyz", match: "\t")
    firstMatchTest(
      #"\p{graph}"#,
      input: "\u{7}\u{1b}\u{a}\n\r\t abc", match: "a")

    firstMatchTest(
      #"\p{print}"#,
      input: "\u{7}\u{1b}\u{a}\n\r\t abc", match: " ")
    firstMatchTest(
      #"\p{word}"#,
      input: "\u{7}\u{1b}\u{a}\n\r\t abc", match: "a")
    firstMatchTest(
      #"\p{xdigit}"#,
      input: "\u{7}\u{1b}\u{a}\n\r\t abc", match: "a")

    firstMatchTest("[[:alnum:]]", input: "[[:alnum:]]", match: "a")
    firstMatchTest("[[:blank:]]", input: "123\tabc xyz", match: "\t")
    firstMatchTest("[[:graph:]]",
      input: "\u{7}\u{1b}\u{a}\n\r\t abc", match: "a")
    firstMatchTest("[[:print:]]",
      input: "\u{7}\u{1b}\u{a}\n\r\t abc", match: " ")
    firstMatchTest("[[:word:]]",
      input: "\u{7}\u{1b}\u{a}\n\r\t abc", match: "a")
    firstMatchTest("[[:xdigit:]]",
      input: "\u{7}\u{1b}\u{a}\n\r\t abc", match: "a")
  }

  func testAssertions() {
    // MARK: Assertions
    firstMatchTest(
      #"\d+(?= dollars)"#,
      input: "Price: 100 dollars", match: "100")
    firstMatchTest(
      #"\d+(?= pesos)"#,
      input: "Price: 100 dollars", match: nil)
    firstMatchTest(
      #"(?=\d+ dollars)\d+"#,
      input: "Price: 100 dollars", match: "100")

    firstMatchTest(
      #"\d+(*pla: dollars)"#,
      input: "Price: 100 dollars", match: "100")
    firstMatchTest(
      #"\d+(*positive_lookahead: dollars)"#,
      input: "Price: 100 dollars", match: "100")

    firstMatchTest(
      #"\d+(?! dollars)"#,
      input: "Price: 100 pesos", match: "100")
    firstMatchTest(
      #"\d+(?! dollars)"#,
      input: "Price: 100 dollars", match: "10")
    firstMatchTest(
      #"(?!\d+ dollars)\d+"#,
      input: "Price: 100 pesos", match: "100")
    firstMatchTest(
      #"\d+(*nla: dollars)"#,
      input: "Price: 100 pesos", match: "100")
    firstMatchTest(
      #"\d+(*negative_lookahead: dollars)"#,
      input: "Price: 100 pesos", match: "100")

    // More complex lookaheads
    firstMatchTests(
      #"(?=.*e)(?=.*o)(?!.*z)."#,
      (input: "hello", match: "h"),
      (input: "hzello", match: "e"),
      (input: "hezllo", match: nil),
      (input: "helloz", match: nil))

    firstMatchTest(
      #"(?<=USD)\d+"#, input: "Price: USD100", match: "100", xfail: true)
    firstMatchTest(
      #"(*plb:USD)\d+"#, input: "Price: USD100", match: "100", xfail: true)
    firstMatchTest(
      #"(*positive_lookbehind:USD)\d+"#,
      input: "Price: USD100", match: "100", xfail: true)
    // engines generally enforce that lookbehinds are fixed width
    firstMatchTest(
      #"\d{3}(?<=USD\d{3})"#, input: "Price: USD100", match: "100", xfail: true)

    firstMatchTest(
      #"(?<!USD)\d+"#, input: "Price: JYP100", match: "100", xfail: true)
    firstMatchTest(
      #"(*nlb:USD)\d+"#, input: "Price: JYP100", match: "100", xfail: true)
    firstMatchTest(
      #"(*negative_lookbehind:USD)\d+"#,
      input: "Price: JYP100", match: "100", xfail: true)
    // engines generally enforce that lookbehinds are fixed width
    firstMatchTest(
      #"\d{3}(?<!USD\d{3})"#, input: "Price: JYP100", match: "100", xfail: true)
  }

  func testMatchAnchors() throws {
    // Must have new stdlib for character class ranges and word boundaries.
    guard ensureNewStdlib() else { return }

    // MARK: Anchors
    firstMatchTests(
      #"^\d+"#,
      ("123", "123"),
      (" 123", nil),
      ("123 456", "123"),
      (" 123 \n456", nil),
      (" \n123 \n456", nil))

    firstMatchTests(
      #"\d+$"#,
      ("123", "123"),
      (" 123", "123"),
      (" 123 \n456", "456"),
      (" 123\n456", "456"),
      ("123 456", "456"))

    firstMatchTests(
      #"\A\d+"#,
      ("123", "123"),
      (" 123", nil),
      (" 123 \n456", nil),
      (" 123\n456", nil),
      ("123 456", "123"))

    firstMatchTests(
      #"\d+\Z"#,
      ("123", "123"),
      (" 123", "123"),
      ("123\n", "123"),
      (" 123\n", "123"),
      (" 123 \n456", "456"),
      (" 123\n456", "456"),
      (" 123\n456\n", "456"),
      ("123 456", "456"))


    firstMatchTests(
      #"\d+\z"#,
      ("123", "123"),
      (" 123", "123"),
      ("123\n", nil),
      (" 123\n", nil),
      (" 123 \n456", "456"),
      (" 123\n456", "456"),
      (" 123\n456\n", nil),
      ("123 456", "456"))

    firstMatchTests(
      #"\d+\b"#,
      ("123", "123"),
      (" 123", "123"),
      ("123 456", "123"),
      ("123A 456", "456"))
    firstMatchTests(
      #"\d+\b\s\b\d+"#,
      ("123", nil),
      (" 123", nil),
      ("123 456", "123 456"))

    firstMatchTests(
      #"\B\d+"#,
      ("123", "23"),
      (" 123", "23"),
      ("123 456", "23"))

    let defaultBoundaryRegex = try Regex(#"\b.{3}X.{3}\b"#)
    // Default word boundaries match at the start/end of a string/line.
    XCTAssertNotNil(try defaultBoundaryRegex.firstMatch(in: "---X---"))
    XCTAssertNotNil(try defaultBoundaryRegex.firstMatch(in: "abc\n---X---\ndef"))
    
    let simpleBoundaryRegex = defaultBoundaryRegex.wordBoundaryKind(.simple)
    // Simple word boundaries match only when the adjacent position matches \w.
    XCTAssertNil(try simpleBoundaryRegex.firstMatch(in: "---X---"))
    XCTAssertNil(try simpleBoundaryRegex.firstMatch(in: "abc\n---X---\ndef"))
    
    XCTAssertNotNil(try simpleBoundaryRegex.firstMatch(in: "x--X--x"))
    XCTAssertNotNil(try simpleBoundaryRegex.firstMatch(in: "abc\nx--X--x\ndef"))
    
    // \G and \K
    let regex = try Regex(#"\Gab"#, as: Substring.self)
    XCTAssertEqual("abab".matches(of: regex).map(\.output), ["ab", "ab"])

    
    // TODO: Oniguruma \y and \Y
    firstMatchTests(
      #"\u{65}"#,             // Scalar 'e' is present in both
      ("Cafe\u{301}", nil))   // but scalar mode requires boundary at end of match

    firstMatchTests(
      #"\u{65}"#,             // Scalar 'e' is present in both
      ("Sol Cafe", "e"))      // standalone is okay

    firstMatchTests(
      #"\u{65}\y"#,           // Grapheme boundary assertion
      ("Cafe\u{301}", nil),
      ("Sol Cafe", "e"))
    
    // FIXME: Figure out (?X) and (?u) semantics
    firstMatchTests(
      #"(?u)\u{65}\Y"#,       // Grapheme non-boundary assertion
      ("Cafe\u{301}", "e"),
      ("Sol Cafe", nil), xfail: true)
  }

  func testLevel2WordBoundaries() {
    // Must have new stdlib for character class ranges and word boundaries.
    guard ensureNewStdlib() else { return }

    // MARK: Level 2 Word Boundaries
    firstMatchTest(#"\b😊\b"#, input: "🔥😊👍", match: "😊")
    firstMatchTest(#"\b👨🏽\b"#, input: "👩🏻👶🏿👨🏽🧑🏾👩🏼", match: "👨🏽")
    firstMatchTest(#"\b🇺🇸\b"#, input: "🇨🇦🇺🇸🇲🇽", match: "🇺🇸")
    firstMatchTest(#"\b.+\b"#, input: "€1 234,56", match: "€1 234,56")
    firstMatchTest(#"〱\B㋞\Bツ"#, input: "〱㋞ツ", match: "〱㋞ツ")
    firstMatchTest(#"\bhello\b"#, input: "hello〱㋞ツ", match: "hello")
    firstMatchTest(#"\bChicago\b"#, input: "나는 Chicago에 산다", match: "Chicago")
    firstMatchTest(#"\blove\b"#, input: "眼睛love食物", match: "love")
    firstMatchTest(#"\b\u{d}\u{a}\b"#, input: "\u{d}\u{a}", match: "\u{d}\u{a}")
    firstMatchTest(#"\bㅋㅋㅋ\b"#, input: "아니ㅋㅋㅋ네", match: "ㅋㅋㅋ")
    firstMatchTest(#"Re\B\:\BZero"#, input: "Re:Zero Starting Life in Another World", match: "Re:Zero")
    firstMatchTest(#"can\B\'\Bt"#, input: "I can't do that.", match: "can't")
    firstMatchTest(#"\b÷\b"#, input: "3 ÷ 3 = 1", match: "÷")
  }

  func testMatchGroups() {
    // Must have new stdlib for character class ranges and word boundaries.
    guard ensureNewStdlib() else { return }

    // MARK: Groups

    // Named captures
    firstMatchTest(
      #"a(?<label>b)c"#, input: "123abcxyz", match: "abc")
    firstMatchTest(
      #"a(?'label'b)c"#, input: "123abcxyz", match: "abc")
    firstMatchTest(
      #"a(?P<label>b)c"#, input: "123abcxyz", match: "abc")

    // Other groups
    firstMatchTest(
      #"a(?:b)c"#, input: "123abcxyz", match: "abc")
    firstMatchTest(
      "(?|(a)|(b)|(c))", input: "123abcxyz", match: "a", xfail: true)

    firstMatchTest(
      #"(?:a|.b)c"#, input: "123abcacxyz", match: "abc")
    firstMatchTest(
      #"(?>a|.b)c"#, input: "123abcacxyz", match: "ac")
    firstMatchTest(
      "(*atomic:a|.b)c", input: "123abcacxyz", match: "ac")
    firstMatchTest(
      #"(?:a+)[a-z]c"#, input: "123aacacxyz", match: "aac")
    firstMatchTest(
      #"(?>a+)[a-z]c"#, input: "123aacacxyz", match: nil)
    
    // Atomicity should stay in the atomic group
    firstMatchTest(
      #"(?:(?>a)|.b)c"#, input: "123abcacxyz", match: "abc")

    firstMatchTest(
      #"(?>a+)a"#, input: "aa", match: nil)
    firstMatchTest(
      #"(?>a+?)a"#, input: "aa", match: "aa")
    firstMatchTest(
      #"(?>(a+))a"#, input: "aa", match: nil)
    firstMatchTest(
      #"(?>(a+?))a"#, input: "aa", match: "aa")

    // Quantifier behavior inside atomic groups
    
    // (?:a+?) matches as few 'a's as possible, after matching the first
    // (?>a+?) always matches exactly one 'a'
    firstMatchTests(
      #"^(?:a+?)a$"#,
      (input: "a", match: nil),
      (input: "aa", match: "aa"),
      (input: "aaa", match:  "aaa"))
    firstMatchTests(
      #"^(?>a+?)a$"#,
      (input: "a", match: nil),
      (input: "aa", match: "aa"),
      (input: "aaa", match:  nil))
    
    // (?:a?+) and (?>a?+) are equivalent: they match one 'a' if available
    firstMatchTests(
      #"^(?:a?+)a$"#,
      (input: "a", match: nil),
      xfail: true)
    firstMatchTests(
      #"^(?:a?+)a$"#,
      (input: "aa", match: "aa"),
      (input: "aaa", match: nil))
    firstMatchTests(
      #"^(?>a?+)a$"#,
      (input: "a", match: nil),
      (input: "aa", match: "aa"),
      (input: "aaa", match: nil))

    // Capture behavior in non-atomic vs atomic groups
    firstMatchTests(
      #"(\d+)\w+\1"#,
      (input: "123x12", match: "123x12"), // `\w+` matches "3x" in this case
      (input: "23x23", match: "23x23"),
      (input: "123x23", match: "23x23"))
    firstMatchTests(
      #"(?>(\d+))\w+\1"#,
      (input: "123x12", match: nil))
    firstMatchTests(
      #"(?>(\d+))\w+\1"#,
      (input: "23x23", match: "23x23"),
      (input: "123x23", match: "23x23"))
    
    // Backreferences in scalar mode
    // In scalar mode the backreference should not match
    firstMatchTest(#"(.+)\1"#, input: "ée\u{301}", match: "ée\u{301}")
    firstMatchTest(#"(.+)\1"#, input: "ée\u{301}", match: nil, semanticLevel: .unicodeScalar)

    // Backreferences in lookaheads
    firstMatchTests(
      #"^(?=.*(.)(.)\2\1).+$"#,
      (input: "abbba", match: nil),
      (input: "ABBA", match: "ABBA"),
      (input: "defABBAdef", match: "defABBAdef"))
    firstMatchTests(
      #"^(?=.*(.)(.)\2\1).+\2$"#,
      (input: "abbba", match: nil),
      (input: "ABBA", match: nil),
      (input: "defABBAdef", match: nil))
    firstMatchTests(
      #"^(?=.*(.)(.)\2\1).+\2$"#,
      (input: "ABBAB", match: "ABBAB"),
      (input: "defABBAdefB", match: "defABBAdefB"))
    
    firstMatchTests(
      #"^(?!.*(.)(.)\2\1).+$"#,
      (input: "abbba", match: "abbba"),
      (input: "ABBA", match: nil),
      (input: "defABBAdef", match: nil))
    // Backreferences don't escape negative lookaheads;
    // matching only proceeds when the lookahead fails
    firstMatchTests(
      #"^(?!.*(.)(.)\2\1).+\2$"#,
      (input: "abbba", match: nil),
      (input: "abbbab", match: nil),
      (input: "ABBAB", match: nil))

    // TODO: Test example where non-atomic is significant
    firstMatchTest(
      #"\d+(?* dollars)"#,
      input: "Price: 100 dollars", match: "100", xfail: true)
    firstMatchTest(
      #"(?*\d+ dollars)\d+"#,
      input: "Price: 100 dollars", match: "100", xfail: true)
    firstMatchTest(
      #"\d+(*napla: dollars)"#,
      input: "Price: 100 dollars", match: "100", xfail: true)
    firstMatchTest(
      #"\d+(*non_atomic_positive_lookahead: dollars)"#,
      input: "Price: 100 dollars", match: "100", xfail: true)

    // TODO: Test example where non-atomic is significant
    firstMatchTest(
      #"(?<*USD)\d+"#, input: "Price: USD100", match: "100", xfail: true)
    firstMatchTest(
      #"(*naplb:USD)\d+"#, input: "Price: USD100", match: "100", xfail: true)
    firstMatchTest(
      #"(*non_atomic_positive_lookbehind:USD)\d+"#,
      input: "Price: USD100", match: "100", xfail: true)
    // engines generally enforce that lookbehinds are fixed width
    firstMatchTest(
      #"\d{3}(?<*USD\d{3})"#, input: "Price: USD100", match: "100", xfail: true)

    // https://www.effectiveperlprogramming.com/2019/03/match-only-the-same-unicode-script/
    firstMatchTest(
      #"abc(*sr:\d+)xyz"#, input: "abc۵۲۸528੫੨੮xyz", match: "۵۲۸", xfail: true)
    firstMatchTest(
      #"abc(*script_run:\d+)xyz"#,
      input: "abc۵۲۸528੫੨੮xyz", match: "۵۲۸", xfail: true)

    // TODO: Test example where atomic is significant
    firstMatchTest(
      #"abc(*asr:\d+)xyz"#, input: "abc۵۲۸528੫੨੮xyz", match: "۵۲۸", xfail: true)
    firstMatchTest(
      #"abc(*atomic_script_run:\d+)xyz"#,
      input: "abc۵۲۸528੫੨੮xyz", match: "۵۲۸", xfail: true)

  }

  func testMatchCaptureBehavior() {
    flatCaptureTest(
      #"a(b)c|abe"#,
      ("abc", ["b"]),
      ("abe", [nil]),
      ("axbe", nil))
    flatCaptureTest(
      #"a(bc)d|abce"#,
      ("abcd", ["bc"]),
      ("abce", [nil]),
      ("abxce", nil))
    flatCaptureTest(
      #"a(bc)+d|abce"#,
      ("abcbcbcd", ["bc"]),
      ("abcbce", nil),
      ("abce", [nil]),
      ("abcbbd", nil))
    flatCaptureTest(
      #"a(bc)+d|(a)bce"#,
      ("abcbcbcd", ["bc", nil]),
      ("abce", [nil, "a"]),
      ("abcbbd", nil))
    flatCaptureTest(
      #"a(b|c)+d|(a)bce"#,
      ("abcbcbcd", ["c", nil]),
      ("abce", [nil, "a"]),
      ("abcbbd", ["b", nil]))
    flatCaptureTest(
      #"a(b+|c+)d|(a)bce"#,
      ("abbbd", ["bbb", nil]),
      ("acccd", ["ccc", nil]),
      ("abce", [nil, "a"]),
      ("abbbe", nil),
      ("accce", nil),
      ("abcbbd", nil))
    flatCaptureTest(
      #"(?:\w\1|:(\w):)+"#,
      (":a:bacada", ["a"]),
      (":a:baca:o:boco", ["o"]),
      ("bacada", nil),
      (":a:boco", ["a"])          // this matches only the ':a:' prefix
    )
  }

  func testMatchReferences() {
    firstMatchTest(
      #"(.)\1"#,
      input: "112", match: "11")
    firstMatchTest(
      #"(.)(.)(.)(.)(.)(.)(.)(.)(.)(.)\10"#,
      input: "aaaaaaaaabbc", match: "aaaaaaaaabb")

    firstMatchTest(
      #"(.)(.)(.)(.)(.)(.)(.)(.)(.)(?<a1>.)(?P=a1)"#,
      input: "aaaaaaaaabbc", match: "aaaaaaaaabb")

    firstMatchTest(
      #"(.)\g001"#,
      input: "112", match: "11")

    firstMatchTest(#"(?<a>.)(.)\k<a>"#, input: "abac", match: "aba")

    firstMatchTest(#"(?<a>.)(?<b>.)(?<c>.)\k<c>\k<a>\k<b>"#,
                   input: "xyzzxy", match: "xyzzxy")

    firstMatchTest(#"\1(.)"#, input: "112", match: nil)
    firstMatchTest(#"\k<a>(?<a>.)"#, input: "112", match: nil)

    // TODO: Implement subpattern matching.
    firstMatchTest(#"(.)(.)\g-02"#, input: "abac", match: "aba", xfail: true)
    firstMatchTest(#"\g'+2'(.)(.)"#, input: "abac", match: "aba", xfail: true)
  }
  
  func testMatchExamples() {
    // Must have new stdlib for character class ranges and word boundaries.
    guard ensureNewStdlib() else { return }

    // Backreferences
    matchTest(
      #"(sens|respons)e and \1ibility"#,
      ("sense and sensibility", true),
      ("response and responsibility", true),
      ("response and sensibility", false),
      ("sense and responsibility", false))
    matchTest(
      #"a(?'name'b(c))d\1\2|abce"#,
      ("abcdbcc", true),
      ("abcdbc", false),
      ("abce", true)
    )

    // Subpatterns
    matchTest(
      #"(sens|respons)e and (?1)ibility"#,
      ("sense and sensibility", true),
      ("response and responsibility", true),
      ("response and sensibility", true),
      ("sense and responsibility", true),
      xfail: true)

    // Palindromes
    matchTest(
      #"(\w)(?:(?R)|\w?)\1"#,
      ("abccba", true),
      ("abcba", true),
      ("abba", true),
      ("stackcats", true),
      ("racecar", true),
      ("a anna c", true), // OK: Partial match
      ("abc", false),
      ("cat", false),
      xfail: true
    )
    matchTest(
      #"^((\w)(?:(?1)|\w?)\2)$"#,
      ("abccba", true),
      ("abcba", true),
      ("abba", true),
      ("stackcats", true),
      ("racecar", true),
      ("a anna c", false), // FAIL: Not whole line
      ("abc", false),
      ("cat", false),
      xfail: true
    )

    // HTML tags
    matchTest(
      #"<([a-zA-Z][a-zA-Z0-9]*)\b[^>]*>.*?</\1>"#,
      ("<html> a b c </html>", true),
      (#"<table style="float:right"> a b c </table>"#, true),
      ("<html> a b c </htm>", false),
      ("<htm> a b c </html>", false),
      (#"<table style="float:right"> a b c </tab>"#, false)
    )

    // Doubled words
    flatCaptureTest(
      #"\b(\w+)\s+\1\b"#,
      ("this does have one one in it", ["one"]),
      ("pass me the the kettle", ["the"]),
      ("this doesn't have any", nil)
    )

    // Floats
    flatCaptureTest(
      #"^([-+])?([0-9]*)(?:\.([0-9]+))?(?:[eE]([-+]?[0-9]+))?$"#,
      ("123.45", [nil, "123", "45", nil]),
      ("-123e12", ["-", "123", nil, "12"]),
      ("+123.456E-12", ["+", "123", "456", "-12"]),
      ("-123e1.2", nil)
    )
  }
  
  func testSingleLineMode() {
    firstMatchTest(#".+"#, input: "a\nb", match: "a")
    firstMatchTest(#"(?s:.+)"#, input: "a\nb", match: "a\nb")

    // We recognize LF, line tab, FF, and CR as newlines by default
    firstMatchTest(#"."#, input: "\u{A}\u{B}\u{C}\u{D}\nb", match: "b")
    firstMatchTest(#".+"#, input: "\u{A}\u{B}\u{C}\u{D}\nbb", match: "bb")

  }

  func testMatchNewlines() {
    // Must have new stdlib for character class ranges and word boundaries.
    guard ensureNewStdlib() else { return }

    for semantics in [RegexSemanticLevel.unicodeScalar, .graphemeCluster] {
      firstMatchTest(
        #"\r\n"#, input: "\r\n", match: "\r\n",
        semanticLevel: semantics
      )
      firstMatchTest(
        #"\r\n"#, input: "\n", match: nil, semanticLevel: semantics)
      firstMatchTest(
        #"\r\n"#, input: "\r", match: nil, semanticLevel: semantics)

      // \r\n is not treated as ASCII.
      firstMatchTest(
        #"^\p{ASCII}$"#, input: "\r\n", match: nil,
        semanticLevel: semantics
      )
      firstMatchTest(
        #"^\r$"#, input: "\r\n", match: nil,
        semanticLevel: semantics
      )
      firstMatchTest(
        #"^[\r]$"#, input: "\r\n", match: nil,
        semanticLevel: semantics
      )
      firstMatchTest(
        #"^\n$"#, input: "\r\n", match: nil,
        semanticLevel: semantics
      )
      firstMatchTest(
        #"^[\n]$"#, input: "\r\n", match: nil,
        semanticLevel: semantics
      )
      firstMatchTest(
        #"^[\u{0}-\u{7F}]$"#, input: "\r\n", match: nil,
        semanticLevel: semantics
      )

      let scalarSemantics = semantics == .unicodeScalar
      firstMatchTest(
        #"\p{ASCII}"#, input: "\r\n", match:  scalarSemantics ? "\r" : nil,
        semanticLevel: semantics
      )
      firstMatchTest(
        #"\r"#, input: "\r\n", match:  scalarSemantics ? "\r" : nil,
        semanticLevel: semantics
      )
      firstMatchTest(
        #"[\r]"#, input: "\r\n", match:  scalarSemantics ? "\r" : nil,
        semanticLevel: semantics
      )
      firstMatchTest(
        #"\n"#, input: "\r\n", match:  scalarSemantics ? "\n" : nil,
        semanticLevel: semantics
      )
      firstMatchTest(
        #"[\n]"#, input: "\r\n", match:  scalarSemantics ? "\n" : nil,
        semanticLevel: semantics
      )
      firstMatchTest(
        #"[\u{0}-\u{7F}]"#, input: "\r\n", match:  scalarSemantics ? "\r" : nil,
        semanticLevel: semantics
      )
    }
  }
  
  func testCaseSensitivity() {
    // Must have new stdlib for character class ranges and word boundaries.
    guard ensureNewStdlib() else { return }

    matchTest(
      #"c..e"#,
      ("cafe", true),
      ("Cafe", false))
    matchTest(
      #"(?i)c.f."#,
      ("cafe", true),
      ("Cafe", true),
      ("caFe", true))
    matchTest(
      #"(?i)cafe"#,
      ("cafe", true),
      ("Cafe", true),
      ("caFe", true))
    matchTest(
      #"(?i)café"#,
      ("café", true),
      ("CafÉ", true))
    matchTest(
      #"(?i)\u{63}af\u{e9}"#,
      ("café", true),
      ("CafÉ", true))
    
    matchTest(
      #"[caFE]{4}"#,
      ("cafe", false),
      ("CAFE", false),
      ("caFE", true),
      ("EFac", true))
    matchTest(
      #"(?i)[caFE]{4}"#,
      ("cafe", true),
      ("CaFe", true),
      ("EfAc", true))
    matchTest(
      #"(?i)[a-f]{4}"#,
      ("cafe", true),
      ("CaFe", true),
      ("EfAc", true))
  }

  func testNonSemanticWhitespace() {
    firstMatchTest(#" \t "#, input: " \t ", match: " \t ")
    firstMatchTest(#"(?xx) \t "#, input: " \t ", match: "\t")

    firstMatchTest(#"[ \t]+"#, input: " \t ", match: " \t ")
    firstMatchTest(#"(?xx)[ \t]+"#, input: " \t ", match: "\t")
    firstMatchTest(#"(?xx)[ \t]+"#, input: " \t\t ", match: "\t\t")
    firstMatchTest(#"(?xx)[ \t]+"#, input: " \t \t", match: "\t")

    firstMatchTest("(?xx)[ a && ab ]+", input: " aaba ", match: "aa")
    
    // Preserve whitespace in quoted section inside extended syntax region
    firstMatchTest(
      #"(?x) a b \Q c d \E e f"#, input: "ab c d ef", match: "ab c d ef")
    firstMatchTest(
      #"(?x)[a b]+ _ [a\Q b\E]+"#, input: "aba_ a b a", match: "aba_ a b a")
    firstMatchTest(
      #"(?x)[a b]+ _ [a\Q b\E]+"#, input: "aba _ a b a", match: nil)
  }
  
  func testASCIIClasses() {
    // Must have new stdlib for character class ranges and word boundaries.
    guard ensureNewStdlib() else { return }

    // 'D' ASCII-only digits
    matchTest(
      #"\d+"#,
      ("123", true),
      ("¹೨¾", true))
    matchTest(
      #"(?D)\d+"#,
      ("123", true),
      ("¹೨¾", false))
    matchTest(
      #"(?P)\d+"#,
      ("123", true),
      ("¹೨¾", false))

    // 'W' ASCII-only word characters (and word boundaries)
    matchTest(
      #"\w+"#,
      ("aeiou", true),
      ("åe\u{301}ïôú", true))
    matchTest(
      #"(?W)\w+"#,
      ("aeiou", true),
      ("åe\u{301}ïôú", false))
    matchTest(
      #"(?P)\w+"#,
      ("aeiou", true),
      ("åe\u{301}ïôú", false))

    matchTest(
      #"abcd\b.+"#,
      ("abcd ef", true),
      ("abcdef", false),
      ("abcdéf", false))
    matchTest(
      #"(?W)abcd\b.+"#,
      ("abcd ef", true),
      ("abcdef", false),
      ("abcdéf", false))
    matchTest(
      #"(?P)abcd\b.+"#,
      ("abcd ef", true),
      ("abcdef", false),
      ("abcdéf", false))

    // 'S' ASCII-only spaces
    matchTest(
      #"a\sb"#,
      ("a\tb", true),
      ("a\u{202f}b", true)) // NARROW NO-BREAK SPACE
    matchTest(
      #"(?S)a\sb"#,
      ("a\tb", true),
      ("a\u{202f}b", false))
    matchTest(
      #"(?P)a\sb"#,
      ("a\tb", true),
      ("a\u{202f}b", false))
  }
  
  func testAnchorMatching() throws {
    let string = """
      01: Alabama
      02: Alaska
      03: Arizona
      04: Arkansas
      05: California
      """
    XCTAssertTrue(string.contains(try Regex(#"^\d+"#)))
    XCTAssertEqual(string.ranges(of: try Regex(#"^\d+"#)).count, 1)
    XCTAssertEqual(string.ranges(of: try Regex(#"(?m)^\d+"#)).count, 5)

    let regex = try Regex(#"^\d+: [\w ]+$"#)
    XCTAssertFalse(string.contains(regex))
    let allRanges = string.ranges(of: regex.anchorsMatchLineEndings())
    XCTAssertEqual(allRanges.count, 5)
  }
  
  func testSubstringAnchors() throws {
    let string = "123abc456def789"
    let trimmed = string.dropFirst(3).dropLast(3) // "abc456def"
    let prefixLetters = try Regex(#"^[a-z]+"#, as: Substring.self)
    let postfixLetters = try Regex(#"[a-z]+$"#, as: Substring.self)

    // start anchor (^) should match beginning of substring
    XCTAssertEqual(trimmed.firstMatch(of: prefixLetters)?.output, "abc")
    XCTAssertEqual(trimmed.replacing(prefixLetters, with: ""), "456def")
    
    // end anchor ($) should match end of substring
    XCTAssertEqual(trimmed.firstMatch(of: postfixLetters)?.output, "def")
    XCTAssertEqual(trimmed.replacing(postfixLetters, with: ""), "abc456")

    // start anchor (^) should _not_ match beginning of replaced subrange
    XCTAssertEqual(
      string.replacing(
        prefixLetters,
        with: "",
        subrange: trimmed.startIndex..<trimmed.endIndex),
      string)
    // end anchor ($) should _not_ match end of replaced subrange
    XCTAssertEqual(
      string.replacing(
        postfixLetters,
        with: "",
        subrange: trimmed.startIndex..<trimmed.endIndex),
      string)
    
    // if subrange == actual subject bounds, anchors _do_ match
    XCTAssertEqual(
      trimmed.replacing(
        prefixLetters,
        with: "",
        subrange: trimmed.startIndex..<trimmed.endIndex),
      "456def")
    XCTAssertEqual(
      trimmed.replacing(
        postfixLetters,
        with: "",
        subrange: trimmed.startIndex..<trimmed.endIndex),
      "abc456")
  }
  
  func testMatchingOptionsScope() {
    // `.` only matches newlines when the 's' option (single-line mode)
    // is turned on. Standalone option-setting groups (e.g. `(?s)`) are
    // scoped only to the current group.
    
    firstMatchTest(#"(?s)a.b"#, input: "a\nb", match: "a\nb")
    firstMatchTest(#"((?s)a.)b"#, input: "a\nb", match: "a\nb")
    firstMatchTest(#"(?-s)((?s)a.)b"#, input: "a\nb", match: "a\nb")
    firstMatchTest(#"(?-s)(?s:a.)b"#, input: "a\nb", match: "a\nb")
    firstMatchTest(#"((?s)a).b"#, input: "a\nb", match: nil)
    firstMatchTest(#"((?s))a.b"#, input: "a\nb", match: nil)
    firstMatchTest(#"(?:(?s))a.b"#, input: "a\nb", match: nil)
    firstMatchTest(#"((?s)a(?s)).b"#, input: "a\nb", match: nil)
    firstMatchTest(#"(?s)a(?-s).b"#, input: "a\nb", match: nil)
    firstMatchTest(#"(?s)a(?-s:.b)"#, input: "a\nb", match: nil)
    firstMatchTest(#"(?:(?s)a).b"#, input: "a\nb", match: nil)
    firstMatchTest(#"(((?s)a)).b"#, input: "a\nb", match: nil)
    firstMatchTest(#"(?s)(((?-s)a)).b"#, input: "a\nb", match: "a\nb")
    firstMatchTest(#"(?s)((?-s)((?i)a)).b"#, input: "a\nb", match: "a\nb")

    // Matching option changing persists across alternations.
    firstMatchTest(#"a(?s)b|c|.d"#, input: "abc", match: "ab")
    firstMatchTest(#"a(?s)b|c|.d"#, input: "c", match: "c")
    firstMatchTest(#"a(?s)b|c|.d"#, input: "a\nd", match: "\nd")
    firstMatchTest(#"a(?s)(?^)b|c|.d"#, input: "a\nd", match: nil)
    firstMatchTest(#"a(?s)b|.c(?-s)|.d"#, input: "a\nd", match: nil)
    firstMatchTest(#"a(?s)b|.c(?-s)|.d"#, input: "a\nc", match: "\nc")
    firstMatchTest(#"a(?s)b|c(?-s)|(?^s).d"#, input: "a\nd", match: "\nd")
    firstMatchTest(#"a(?:(?s).b)|.c|.d"#, input: "a\nb", match: "a\nb")
    firstMatchTest(#"a(?:(?s).b)|.c"#, input: "a\nc", match: nil)
  }
  
  func testOptionMethods() throws {
    let regex = try Regex("c.f.")
    XCTAssertTrue ("cafe".contains(regex))
    XCTAssertFalse("CaFe".contains(regex))
    
    let caseInsensitiveRegex = regex.ignoresCase()
    XCTAssertTrue("cafe".contains(caseInsensitiveRegex))
    XCTAssertTrue("CaFe".contains(caseInsensitiveRegex))
  }
  
  // MARK: Character Semantics
  
  var eComposed: String { "é" }
  var eDecomposed: String { "e\u{301}" }
  
  var eComposedUpper: String { "É" }
  var eDecomposedUpper: String { "E\u{301}" }

  func testIndividualScalars() {
    // Expectation: A standalone Unicode scalar value in a regex literal
    // can match either that specific scalar value or participate in matching
    // as a character.

    firstMatchTest(#"\u{65}\u{301}$"#, input: eDecomposed, match: eDecomposed)
    firstMatchTest(#"\u{65}\u{301}$"#, input: eComposed, match: eComposed)

    firstMatchTest(#"\u{65 301}$"#, input: eDecomposed, match: eDecomposed)
    firstMatchTest(#"\u{65 301}$"#, input: eComposed, match: eComposed)

    // FIXME: Implicit \y at end of match
    firstMatchTest(#"\u{65}"#, input: eDecomposed, match: nil)
    firstMatchTest(#"\u{65}$"#, input: eDecomposed, match: nil)
    firstMatchTest(#"\u{65}\y"#, input: eDecomposed, match: nil)

    // FIXME: Unicode scalars are only matched at the start of a grapheme cluster
    firstMatchTest(#"\u{301}"#, input: eDecomposed, match: "\u{301}",
      xfail: true)

    firstMatchTest(#"\y\u{301}"#, input: eDecomposed, match: nil)
  }

  func testCanonicalEquivalence() throws {
    // Expectation: Matching should use canonical equivalence whenever comparing
    // characters, so a user can write characters using any equivalent spelling
    // in either a regex literal or the string targeted for matching.
    
    matchTest(
      #"é$"#,
      (eComposed, true),
      (eDecomposed, true))

    matchTest(
      #"e\u{301}$"#,
      (eComposed, true),
      (eDecomposed, true))

    matchTest(
      #"e$"#,
      (eComposed, false),
      (eDecomposed, false))

    matchTest(
      #"\u{65 301}"#,
      (eComposed, true),
      (eDecomposed, true))

    matchTest(
      #"(?x) \u{65} \u{301}"#,
      (eComposed, true),
      (eDecomposed, true))
  }

  func testCanonicalEquivalenceCharacterClass() throws {
    // Expectation: Character classes should match equivalent characters to the
    // same degree, regardless of how they are spelled. Unicode "property
    // classes" should match characters when all the code points that comprise
    // the character are members of the property class.
    
    // \w
    matchTest(
      #"^\w$"#,
      (eComposed, true),
      (eDecomposed, true))
    // \p{Letter}
    firstMatchTest(#"\p{Letter}$"#, input: eComposed, match: eComposed)
    firstMatchTest(#"\p{Letter}$"#, input: eDecomposed, match: eDecomposed)
    
    // \d
    firstMatchTest(#"\d"#, input: "5", match: "5")
    // FIXME: \d shouldn't match a digit composed with a non-digit character
    firstMatchTest(#"\d"#, input: "5\u{305}", match: nil,
              xfail: true)
    // \p{Number}
    firstMatchTest(#"\p{Number}"#, input: "5", match: "5")
    // FIXME: \p{Number} shouldn't match a number composed with a non-number character
    firstMatchTest(#"\p{Number}"#, input: "5\u{305}", match: nil,
              xfail: true)
    
    // Should this match the '5' but not the ZWJ, or should it treat '5'+ZWJ
    // as one entity and fail to match altogether?
    firstMatchTest(#"^\d"#, input: "5\u{200d}0", match: "5",
              xfail: true)
    
    // \s
    firstMatchTest(#"\s"#, input: " ", match: " ")
    // FIXME: \s shouldn't match a number composed with a non-number character
    firstMatchTest(#"\s\u{305}"#, input: " ", match: nil)
    // \p{Whitespace}
    firstMatchTest(#"\s"#, input: " ", match: " ")
    // \p{Whitespace} shouldn't match whitespace composed with a non-whitespace character
    firstMatchTest(#"\s\u{305}"#, input: " ", match: nil)
  }
  
  func testCanonicalEquivalenceCustomCharacterClass() throws {
    // Expectation: Custom character class matches do not cross grapheme
    // character boundaries by default. When matching with Unicode scalar
    // semantics, grapheme cluster boundaries are ignored, so matching
    // sequences of custom character classes can succeed.

    // Must have new stdlib for character class ranges and word boundaries.
    guard ensureNewStdlib() else { return }

    matchTest(
      #"[áéíóú]$"#,
      (eComposed, true),
      (eDecomposed, true))

    for input in [eDecomposed, eComposed] {
      // Unicode scalar semantics means that only the decomposed version can
      // match here.
      let match = input.unicodeScalars.count == 2 ? input : nil
      firstMatchTest(
        #"e[\u{301}]$"#, input: input, match: match,
        semanticLevel: .unicodeScalar)
      firstMatchTest(
        #"e[\u{300}-\u{320}]$"#, input: input, match: match,
        semanticLevel: .unicodeScalar)
      firstMatchTest(
        #"[e][\u{300}-\u{320}]$"#, input: input, match: match,
        semanticLevel: .unicodeScalar)
      firstMatchTest(
        #"[e-e][\u{300}-\u{320}]$"#, input: input, match: match,
        semanticLevel: .unicodeScalar)
      firstMatchTest(
        #"[a-z][\u{300}-\u{320}]$"#, input: input, match: match,
        semanticLevel: .unicodeScalar)
    }
    for input in [eComposed, eDecomposed] {
      // Grapheme cluster semantics means that we can't match the 'e' separately
      // from the accent.
      firstMatchTest(#"e[\u{301}]$"#, input: input, match: nil)
      firstMatchTest(#"e[\u{300}-\u{320}]$"#, input: input, match: nil)
      firstMatchTest(#"[e][\u{300}-\u{320}]$"#, input: input, match: nil)
      firstMatchTest(#"[e-e][\u{300}-\u{320}]$"#, input: input, match: nil)
      firstMatchTest(#"[a-z][\u{300}-\u{320}]$"#, input: input, match: nil)

      // A range that covers é (U+E9). Inputs are mapped to NFC, so match.
      firstMatchTest(#"[\u{E8}-\u{EA}]"#, input: input, match: input)
    }

    // A range that covers É (U+C9). Inputs are mapped to NFC, so match.
    for input in [eComposedUpper, eDecomposedUpper] {
      firstMatchTest(#"[\u{C8}-\u{CA}]"#, input: input, match: input)
      firstMatchTest(#"[\u{C9}-\u{C9}]"#, input: input, match: input)
    }
    // Case insensitive matching of É (U+C9).
    for input in [eComposed, eDecomposed, eComposedUpper, eDecomposedUpper] {
      firstMatchTest(#"(?i)[\u{C8}-\u{CA}]"#, input: input, match: input)
      firstMatchTest(#"(?i)[\u{C9}-\u{C9}]"#, input: input, match: input)
    }

    let flag = "🇰🇷"
    firstMatchTest(#"🇰🇷"#, input: flag, match: flag)
    firstMatchTest(#"[🇰🇷]"#, input: flag, match: flag)
    firstMatchTest(#"\u{1F1F0}\u{1F1F7}"#, input: flag, match: flag)
    firstMatchTest(#"\u{1F1F0 1F1F7}"#, input: flag, match: flag)

    // First Unicode scalar followed by CCC of regional indicators
    firstMatchTest(
      #"^\u{1F1F0}[\u{1F1E6}-\u{1F1FF}]$"#, input: flag, match: flag,
      semanticLevel: .unicodeScalar
    )
    // A CCC of regional indicators followed by the second Unicode scalar
    firstMatchTest(
      #"^[\u{1F1E6}-\u{1F1FF}]\u{1F1F7}$"#, input: flag, match: flag,
      semanticLevel: .unicodeScalar
    )
    // A CCC of regional indicators x 2
    firstMatchTest(
      #"^[\u{1F1E6}-\u{1F1FF}]{2}$"#, input: flag, match: flag,
      semanticLevel: .unicodeScalar
    )
    // A CCC of N regional indicators
    firstMatchTest(
      #"^[\u{1F1E6}-\u{1F1FF}]+$"#, input: flag, match: flag,
      semanticLevel: .unicodeScalar
    )

    // A single CCC of regional indicators
    firstMatchTest(
      #"^[\u{1F1E6}-\u{1F1FF}]$"#, input: flag, match: nil)
    firstMatchTest(
      #"^[\u{1F1E6}-\u{1F1FF}]$"#, input: flag, match: nil,
      semanticLevel: .unicodeScalar
    )
  }
  
  func testAnyChar() throws {
    // Expectation: \X and, in grapheme cluster mode, `.` should consume an
    // entire character, regardless of how it's spelled. \O should consume only
    // a single Unicode scalar value, leaving any other grapheme scalar
    // components to be matched.
    
    // FIXME: Figure out (?X) and (?u) semantics
    firstMatchTest(#"(?u:.)"#, input: eDecomposed, match: "e", xfail: true)

    matchTest(
      #".\u{301}"#,
      (eComposed, false),
      (eDecomposed, false))
    matchTest(
      #"\X\u{301}"#,
      (eComposed, false),
      (eDecomposed, false))
    
    // FIXME: Figure out (?X) and (?u) semantics
    // FIXME: \O is unsupported
    firstMatchTest(
      #"(?u)\O\u{301}"#,
      input: eDecomposed,
      match: eDecomposed,
      xfail: true
    )
    firstMatchTest(
      #"(?u)e\O"#,
      input: eDecomposed,
      match: eDecomposed,
      xfail: true
    )
    firstMatchTest(#"\O"#, input: eComposed, match: eComposed, xfail: true)
    firstMatchTest(#"\O"#, input: eDecomposed, match: nil,
              xfail: true)

    // FIXME: Figure out (?X) and (?u) semantics
    matchTest(
      #"(?u).\u{301}"#,
      (eComposed, false),
      (eDecomposed, true), xfail: true)
    firstMatchTest(#"(?u).$"#, input: eComposed, match: eComposed, xfail: true)
    
    // Option permutations for 'u' and 's'
    matchTest(
      #"...."#,
      ("e\u{301}ab", false),
      ("e\u{301}abc", true),
      ("e\u{301}\nab", false))
    matchTest(
      #"(?s)...."#,
      ("e\u{301}ab", false),
      ("e\u{301}abc", true),
      ("e\u{301}\nab", true))
    
    // FIXME: Figure out (?X) and (?u) semantics
    matchTest(
      #"(?u)...."#,
      ("e\u{301}ab", true),
      ("e\u{301}\na", false), xfail: true)
    matchTest(
      #"(?us)...."#,
      ("e\u{301}ab", true),
      ("e\u{301}\na", true), xfail: true)
  }
  
  // TODO: Add test for implied grapheme cluster requirement at group boundaries
  
  // TODO: Add test for grapheme boundaries at start/end of match

  // Testing the matchScalar optimization for ascii quoted literals and characters
  func testScalarOptimization() throws {
    // check that we are correctly doing the boundary check after matchScalar
    firstMatchTest("a", input: "a\u{301}", match: nil)
    firstMatchTest("aa", input: "aa\u{301}", match: nil)

    firstMatchTest("a", input: "a\u{301}", match: "a", semanticLevel: .unicodeScalar)
    firstMatchTest("aa", input: "aa\u{301}", match: "aa", semanticLevel: .unicodeScalar)

    // case insensitive tests
    firstMatchTest(#"(?i)abc\u{301}d"#, input: "AbC\u{301}d", match: "AbC\u{301}d", semanticLevel: .unicodeScalar)

    // check that we don't crash on empty strings
    firstMatchTest(#"\Q\E"#, input: "", match: "")
  }
  
  func testCase() {
    let regex = try! Regex(#".\N{SPARKLING HEART}."#)
    let input = "🧟‍♀️💖🧠 or 🧠💖☕️"
    let characterMatches = input.matches(of: regex)
    XCTAssertEqual(characterMatches.map { $0.0 }, ["🧟‍♀️💖🧠", "🧠💖☕️"])

    let scalarMatches = input.matches(of: regex.matchingSemantics(.unicodeScalar))
    let scalarExpected: [Substring] = ["\u{FE0F}💖🧠", "🧠💖☕"]
    XCTAssertEqual(scalarMatches.map { $0.0 }, scalarExpected)
  }
  
  func testConcurrentAccess() async throws {
    for _ in 0..<1000 {
      let regex = try Regex(#"abc+d*e?"#)
      let strings = [
        "abc",
        "abccccccccdddddddddde",
        "abcccce",
        "abddddde",
      ]
      let matches = await withTaskGroup(of: Optional<Regex<AnyRegexOutput>.Match>.self) { group -> [Regex<AnyRegexOutput>.Match] in
        var result: [Regex<AnyRegexOutput>.Match] = []
        
        for str in strings {
          group.addTask {
            str.firstMatch(of: regex)
          }
        }
        
        for await match in group {
          guard let match = match else { continue }
          result.append(match)
        }
        
        return result
      }
      
      XCTAssertEqual(matches.count, 3)
    }
  }

  func expectCompletion(regex: String, in target: String) {
    let expectation = XCTestExpectation(description: "Run the given regex to completion")
    Task.init {
      let r = try! Regex(regex)
      let val = target.matches(of: r).isEmpty
      expectation.fulfill()
      return val
    }
    wait(for: [expectation], timeout: 3.0)
  }

  func testQuantificationForwardProgress() {
    expectCompletion(regex: #"(?:(?=a)){1,}"#, in: "aa")
    expectCompletion(regex: #"(?:\b)+"#, in: "aa")
    expectCompletion(regex: #"(?:(?#comment))+"#, in: "aa")
    expectCompletion(regex: #"(?:|)+"#, in: "aa")
    expectCompletion(regex: #"(?:\w|)+"#, in: "aa")
    expectCompletion(regex: #"(?:\w|(?i-i:))+"#, in: "aa")
    expectCompletion(regex: #"(?:\w|(?#comment))+"#, in: "aa")
    expectCompletion(regex: #"(?:\w|(?#comment)(?i-i:))+"#, in: "aa")
    expectCompletion(regex: #"(?:\w|(?i))+"#, in: "aa")
    expectCompletion(regex: #"(a*)*"#, in: "aa")
    expectCompletion(regex: #"(a?)*"#, in: "aa")
    expectCompletion(regex: #"(a{,4})*"#, in: "aa")
    expectCompletion(regex: #"((|)+)*"#, in: "aa")
  }

  func testQuantifyOptimization() throws {
    // test that the maximum values for minTrips and maxExtraTrips are handled correctly
    let maxStorable = Int(QuantifyPayload.maxStorableTrips)
    let maxExtraTrips = "a{,\(maxStorable)}"
    expectProgram(for: maxExtraTrips, contains: [.quantify])
    firstMatchTest(maxExtraTrips, input: String(repeating: "a", count: maxStorable), match: String(repeating: "a", count: maxStorable))
    firstMatchTest(maxExtraTrips, input: String(repeating: "a", count: maxStorable + 1), match: String(repeating: "a", count: maxStorable))
    XCTAssertNil(try Regex(maxExtraTrips).wholeMatch(in: String(repeating: "a", count: maxStorable + 1)))

    let maxMinTrips = "a{\(maxStorable),}"
    expectProgram(for: maxMinTrips, contains: [.quantify])
    firstMatchTest(maxMinTrips, input: String(repeating: "a", count: maxStorable), match: String(repeating: "a", count: maxStorable))
    firstMatchTest(maxMinTrips, input: String(repeating: "a", count: maxStorable - 1), match: nil)

    let maxBothTrips = "a{\(maxStorable),\(maxStorable*2)}"
    expectProgram(for: maxBothTrips, contains: [.quantify])
    XCTAssertNil(try Regex(maxBothTrips).wholeMatch(in: String(repeating: "a", count: maxStorable*2 + 1)))
    firstMatchTest(maxBothTrips, input: String(repeating: "a", count: maxStorable*2), match: String(repeating: "a", count: maxStorable*2))
    firstMatchTest(maxBothTrips, input: String(repeating: "a", count: maxStorable), match: String(repeating: "a", count: maxStorable))
    firstMatchTest(maxBothTrips, input: String(repeating: "a", count: maxStorable - 1), match: nil)
    
    expectProgram(for: "a{,\(maxStorable+1)}", doesNotContain: [.quantify])
    expectProgram(for: "a{\(maxStorable+1),}", doesNotContain: [.quantify])
    expectProgram(for: "a{\(maxStorable-1),\(maxStorable*2)}", doesNotContain: [.quantify])
    expectProgram(for: "a{\(maxStorable),\(maxStorable*2+1)}", doesNotContain: [.quantify])
  }
  
  func testFuzzerArtifacts() throws {
    expectCompletion(regex: #"(b?)\1*"#, in: "a")
  }
  
  func testIssue640() throws {
    // Original report from https://github.com/apple/swift-experimental-string-processing/issues/640
    let original = try Regex("[1-9][0-9]{0,2}(?:,?[0-9]{3})*")
    XCTAssertNotNil("36,769".wholeMatch(of: original))
    XCTAssertNotNil("36769".wholeMatch(of: original))

    // Simplified case
    let simplified = try Regex("a{0,2}a")
    XCTAssertNotNil("aaa".wholeMatch(of: simplified))

    for max in 1...8 {
      let patternEager = "a{0,\(max)}a"
      let regexEager = try Regex(patternEager)
      let patternReluctant = "a{0,\(max)}?a"
      let regexReluctant = try Regex(patternReluctant)
      for length in 1...(max + 1) {
        let str = String(repeating: "a", count: length)
        if str.wholeMatch(of: regexEager) == nil {
          XCTFail("Didn't match '\(patternEager)' in '\(str)' (\(max),\(length)).")
        }
        if str.wholeMatch(of: regexReluctant) == nil {
          XCTFail("Didn't match '\(patternReluctant)' in '\(str)' (\(max),\(length)).")
        }
      }
      
      let possessiveRegex = try Regex("a{0,\(max)}+a")
      let str = String(repeating: "a", count: max + 1)
      XCTAssertNotNil(str.wholeMatch(of: possessiveRegex))
    }
  }
  
  func testIssue713() throws {
    // Original report from https://github.com/apple/swift-experimental-string-processing/issues/713
    let originalInput = "Something 9a"
    let originalRegex = #/(?=([1-9]|(a|b)))/#
    let originalOutput = originalInput.matches(of: originalRegex).map(\.output)
    XCTAssert(originalOutput[0] == ("", "9", nil))
    XCTAssert(originalOutput[1] == ("", "a", "a"))

    let simplifiedRegex = #/(?=(9))/#
    let simplifiedOutput = originalInput.matches(of: simplifiedRegex).map(\.output)
    XCTAssert(simplifiedOutput[0] == ("", "9"))

    let additionalRegex = #/(a+)b(a+)/#
    let additionalInput = "abaaba"
    XCTAssertNil(additionalInput.wholeMatch(of: additionalRegex))
  }
  
  func testNSRECompatibility() throws {
    // NSRE-compatibility includes scalar matching, so `[\r\n]` should match
    // either `\r` or `\n`.
    let text = #"""
      y=sin(x)+sin(2x)+sin(3x);\#rText "This is a function of x.";\r
      """#
    let lineTerminationRegex = try Regex(#";[\r\n]"#)
      ._nsreCompatibility
    
    let afterLine = try XCTUnwrap(text.firstRange(of: "Text"))
    let match = try lineTerminationRegex.firstMatch(in: text)
    XCTAssert(match?.range.upperBound == afterLine.lowerBound)
    
    // NSRE-compatibility treats "dot" as special, in that it can match a
    // newline sequence as well as a single Unicode scalar.
    let aDotBRegex = try Regex(#"a.b"#)
      ._nsreCompatibility
      .dotMatchesNewlines()
    for input in ["a\rb", "a\nb", "a\r\nb"] {
      XCTAssertNotNil(try aDotBRegex.wholeMatch(in: input))
    }
    
    // NSRE-compatibility doesn't give special treatment to newline sequences
    // when matching other "match everything" regex patterns, like `[[^z]z]`,
    // so this pattern doesn't match "a\r\nb".
    let aCCBRegex = try Regex(#"a[[^z]z]b"#)
      ._nsreCompatibility
    for input in ["a\rb", "a\nb", "a\r\nb"] {
      if input.unicodeScalars.count == 3 {
        XCTAssertNotNil(try aCCBRegex.wholeMatch(in: input))
      } else {
        XCTAssertNil(try aCCBRegex.wholeMatch(in: input))
      }
    }
  }
}
