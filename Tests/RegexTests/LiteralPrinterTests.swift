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
@_spi(LiteralPattern)
import _StringProcessing
import RegexBuilder

@available(SwiftStdlib 6.0, *)
fileprivate func _literalTest<T>(
  _ regex: Regex<T>,
  expected: String?,
  file: StaticString = #filePath,
  line: UInt = #line
) {
  XCTAssertEqual(regex._literalPattern, expected, file: file, line: line)
  if let expected {
    let remadeRegex = try? Regex(expected)
    XCTAssertEqual(expected, remadeRegex?._literalPattern, file: file, line: line)
  }
}

@available(SwiftStdlib 6.0, *)
extension RegexTests {
  func testPrintableRegex() throws {
    let regexString = #"([a-fGH1-9[^\D]]+)?b*cd(e.+)\2\w\S+?"#
    let regex = try Regex(regexString)
    // Note: This is true for this particular regex, but not all regexes
    _literalTest(regex, expected: regexString)
    
    let printableRegex = try XCTUnwrap(PrintableRegex(regex))
    XCTAssertEqual("\(printableRegex)", regexString)
  }
  
  func testUnicodeEscapes() throws {
    let regex = #/\r\n\t cafe\u{301} \u{1D11E}/#
    _literalTest(regex, expected: #"\r\n\t cafe\u0301 \U0001D11E"#)
  }
  
  func testPrintableDSLRegex() throws {
    let regex = Regex {
      OneOrMore("aaa", .reluctant)
      Regex {
        ChoiceOf {
          ZeroOrMore("bbb")
          OneOrMore("d")
          Repeat("e", 3...)
        }
      }.dotMatchesNewlines()
      Optionally("c")
    }.ignoresCase()
    _literalTest(regex, expected: "(?i:(?:aaa)+?(?s:(?:bbb)*|d+|e{3,})c?)")

    let nonPrintableRegex = Regex {
      OneOrMore("a")
      Capture {
        OneOrMore(.digit)
      } transform: { Int($0)! }
      Optionally("b")
    }
    _literalTest(nonPrintableRegex, expected: nil)
  }
}

// MARK: - PrintableRegex

// Demonstration of a guaranteed Codable/Sendable regex type.
@available(SwiftStdlib 6.0, *)
struct PrintableRegex: RegexComponent, @unchecked Sendable {
  var pattern: String
  var regex: Regex<AnyRegexOutput>
  
  init?(_ re: some RegexComponent) {
    guard let pattern = re.regex._literalPattern
    else { return nil }
    self.pattern = pattern
    self.regex = Regex(re.regex)
  }
  
  func matches(in string: String) -> Bool {
    string.contains(regex)
  }
  
  func wholeMatches(in string: String) -> Bool {
    string.wholeMatch(of: regex) != nil
  }
}

@available(SwiftStdlib 6.0, *)
extension PrintableRegex: Codable {
  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self.pattern = try container.decode(String.self)
    self.regex = try Regex(self.pattern)
  }
  
  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(pattern)
  }
}

@available(SwiftStdlib 6.0, *)
extension PrintableRegex: CustomStringConvertible {
  var description: String {
    pattern
  }
}
