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
@testable import RegexBuilder

// A nibbler processes a single character from a string
@available(SwiftStdlib 5.7, *)
private protocol Nibbler: CustomConsumingRegexComponent {
  func nibble(_: Character) -> RegexOutput?
}

@available(SwiftStdlib 5.7, *)
extension Nibbler {
  // Default implementation, just feed the character in
  func consuming(
    _ input: String,
    startingAt index: String.Index,
    in bounds: Range<String.Index>
  ) throws -> (upperBound: String.Index, output: RegexOutput)? {
    guard index != bounds.upperBound, let res = nibble(input[index]) else {
      return nil
    }
    return (input.index(after: index), res)
  }
}


// A number nibbler
@available(SwiftStdlib 5.7, *)
private struct Numbler: Nibbler {
  typealias RegexOutput = Int
  func nibble(_ c: Character) -> Int? {
    c.wholeNumberValue
  }
}

// An ASCII value nibbler
@available(SwiftStdlib 5.7, *)
private struct Asciibbler: Nibbler {
  typealias RegexOutput = UInt8
  func nibble(_ c: Character) -> UInt8? {
    c.asciiValue
  }
}

@available(SwiftStdlib 5.7, *)
private struct IntParser: CustomConsumingRegexComponent {
  struct ParseError: Error, Hashable {}
  typealias RegexOutput = Int
  func consuming(_ input: String,
    startingAt index: String.Index,
    in bounds: Range<String.Index>
  ) throws -> (upperBound: String.Index, output: Int)? {
    guard index != bounds.upperBound else { return nil }

    let r = Regex {
      Capture<(Substring, Int?)>(OneOrMore(.digit)) { Int($0) }
    }

    guard let match = input[index..<bounds.upperBound].prefixMatch(of: r),
            let output = match.1 else {
      throw ParseError()
    }

    return (match.range.upperBound, output)
  }
}

@available(SwiftStdlib 5.7, *)
private struct CurrencyParser: CustomConsumingRegexComponent {
  enum Currency: String, Hashable {
    case usd = "USD"
    case ntd = "NTD"
    case dem = "DEM"
  }

  enum ParseError: Error, Hashable {
    case unrecognized
    case deprecated
  }

  typealias RegexOutput = Currency
  func consuming(_ input: String,
             startingAt index: String.Index,
             in bounds: Range<String.Index>
  ) throws -> (upperBound: String.Index, output: Currency)? {

    guard index != bounds.upperBound else { return nil }

    let substr = input[index..<bounds.upperBound]
    guard !substr.isEmpty else { return nil }

    let currencies: [Currency] = [ .usd, .ntd ]
    let deprecated: [Currency] = [ .dem ]

    for currency in currencies {
      if substr.hasPrefix(currency.rawValue) {
        return (input.range(of: currency.rawValue)!.upperBound, currency)
      }
    }

    for dep in deprecated {
      if substr.hasPrefix(dep.rawValue) {
        throw ParseError.deprecated
      }
    }
    throw ParseError.unrecognized
  }
}

enum MatchCall {
  case match
  case firstMatch
}

@available(SwiftStdlib 5.7, *)
fileprivate func customTest<Match: Equatable>(
  _ regex: Regex<Match>,
  _ tests: (input: String, call: MatchCall, match: Match?)...,
  file: StaticString = #file,
  line: UInt = #line
) {
  for (input, call, match) in tests {
    let result: Match?
    switch call {
    case .match:
      result = input.wholeMatch(of: regex)?.output
    case .firstMatch:
      result = input.firstMatch(of: regex)?.output
    }
    XCTAssertEqual(result, match, file: file, line: line)
  }
}

@available(SwiftStdlib 5.7, *)
fileprivate func customTest<Match>(
  _ regex: some RegexComponent<Match>,
  _ isEquivalent: (Match, Match) -> Bool,
  _ tests: (input: String, call: MatchCall, match: Match?)...,
  file: StaticString = #file,
  line: UInt = #line
) {
  for (input, call, match) in tests {
    let result: Match?
    switch call {
    case .match:
      result = input.wholeMatch(of: regex)?.output
    case .firstMatch:
      result = input.firstMatch(of: regex)?.output
    }
    switch (result, match) {
    case let (result?, match?):
      XCTAssert(
        isEquivalent(result, match),
        "'\(result)' isn't equal to '\(match)'.",
        file: file, line: line)
    case (nil, nil):
      // Success
      break
    case (nil, _):
      XCTFail("No match when expected", file: file, line: line)
    case (_, nil):
      XCTFail("Unexpected match", file: file, line: line)
    }
  }
}

// Test support
struct Concat : Equatable {
  var wrapped: String
  init(_ name: String, _ suffix: Int?) {
    if let suffix = suffix {
      wrapped = name + String(suffix)
    } else {
      wrapped = name
    }
  }
}

extension Concat : Collection {
  typealias Index = String.Index
  typealias Element = String.Element

  var startIndex: Index { return wrapped.startIndex }
  var endIndex: Index { return wrapped.endIndex }

  subscript(position: Index) -> Element {
    return wrapped[position]
  }

  func index(after i: Index) -> Index {
    return wrapped.index(after: i)
  }
}

extension Concat: BidirectionalCollection {
  typealias Indices = String.Indices
  typealias SubSequence = String.SubSequence

  func index(before i: Index) -> Index {
    return wrapped.index(before: i)
  }

  var indices: Indices {
    wrapped.indices
  }

  subscript(bounds: Range<Index>) -> Substring {
    Substring(wrapped[bounds])
  }
}

@available(SwiftStdlib 5.7, *)
class CustomRegexComponentTests: XCTestCase {
  // TODO: Refactor below into more exhaustive, declarative
  // tests.
  func testCustomRegexComponents() throws {
    customTest(
      Regex {
        Numbler()
        Asciibbler()
      },
      ("4t", .match, "4t"),
      ("4", .match, nil),
      ("t", .match, nil),
      ("t x1y z", .firstMatch, "1y"),
      ("t4", .match, nil))

    customTest(
      Regex {
        OneOrMore { Numbler() }
      },
      ("ab123c", .firstMatch, "123"),
      ("abc", .firstMatch, nil),
      ("55z", .match, nil),
      ("55z", .firstMatch, "55"))

    customTest(
      Regex {
        Numbler()
      },
      ("ab123c", .firstMatch, 1),
      ("abc", .firstMatch, nil),
      ("55z", .match, nil),
      ("55z", .firstMatch, 5))

//    customTest(
//      Regex<Substring> {
//        #/(?<prefix>\D+)/#
//        Optionally("~")
//      },
//      ("ab123c", .firstMatch, "ab"),
//      ("abc", .firstMatch, "abc"),
//      ("123", .firstMatch, nil),
//      ("a55z", .match, nil),
//      ("a55z", .firstMatch, "a"))

    customTest(
      Regex<(Substring, Substring, Int)> {
        #/(\D+)/#
        Capture(Numbler())
      },
      ==,
      ("ab123c", .firstMatch, ("ab1", "ab", 1)),
      ("abc", .firstMatch, nil),
      ("123", .firstMatch, nil),
      ("a55z", .match, nil),
      ("a55z", .firstMatch, ("a5", "a", 5)))

    customTest(
      Regex<(Substring, prefix: Substring)> {
        #/(?<prefix>\D+)/#
      },
      ==,
      ("ab123c", .firstMatch, ("ab", "ab")),
      ("abc", .firstMatch, ("abc", "abc")),
      ("123", .firstMatch, nil),
      ("a55z", .match, nil),
      ("a55z", .firstMatch, ("a", "a")))

//    customTest(
//      Regex<(Substring, Int)> {
//        #/(?<prefix>\D+)/#
//        Capture(Numbler())
//      },
//      ==,
//      ("ab123c", .firstMatch, ("ab1", 1)),
//      ("abc", .firstMatch, nil),
//      ("123", .firstMatch, nil),
//      ("a55z", .match, nil),
//      ("a55z", .firstMatch, ("a5", 5)))
    
//    customTest(
//      Regex<(Substring, Int, Substring)> {
//        #/(?<prefix>\D+)/#
//        Regex {
//          Capture(Numbler())
//          Capture(OneOrMore(.word))
//        }
//      },
//      ==,
//      ("ab123c", .firstMatch, ("ab123c", 1, "23c")),
//      ("abc", .firstMatch, nil),
//      ("123", .firstMatch, nil),
//      ("a55z", .match, ("a55z", 5, "5z")),
//      ("a55z", .firstMatch, ("a55z", 5, "5z")))
    
    customTest(
      Regex<(Substring, Substring)> {
        Capture {
          OneOrMore {
            Numbler()
          }
        }
      },
      ==,
      ("abc123", .firstMatch, ("123", "123")),
      ("abc123", .match, nil),
      ("abc", .firstMatch, nil))
    
    customTest(
      Regex<(Substring, Int)> {
        OneOrMore {
          Capture { Numbler() }
        }
      },
      ==,
      ("ab123c", .firstMatch, ("123", 3)),
      ("abc", .firstMatch, nil),
      ("55z", .match, nil),
      ("55z", .firstMatch, ("55", 5)))
  }

  func testRegexAbort() {

    enum Radix: Hashable {
      case dot
      case comma
    }
    struct Abort: Error, Hashable {}

    let hexRegex = Regex {
      Capture { OneOrMore(.hexDigit) }
      TryCapture { CharacterClass.any } transform: { c -> Radix? in
        switch c {
        case ".": return Radix.dot
        case ",": return Radix.comma
        case "❗️":
          // Malicious! Toxic levels of emphasis detected.
          throw Abort()
        default:
          // Not a radix
          return nil
        }
      }
      Capture { OneOrMore(.hexDigit) }
    }
    // hexRegex: Regex<(Substring, Substring, Radix?, Substring)>
    // TODO: Why is Radix optional?

    do {
      guard let m = try hexRegex.wholeMatch(in: "123aef.345") else {
        XCTFail()
        return
      }
      XCTAssertEqual(m.0, "123aef.345")
      XCTAssertEqual(m.1, "123aef")
      XCTAssertEqual(m.2, .dot)
      XCTAssertEqual(m.3, "345")
    } catch {
      XCTFail()
    }

    do {
      _ = try hexRegex.wholeMatch(in: "123aef❗️345")
      XCTFail()
    } catch let e as Abort {
      XCTAssertEqual(e, Abort())
    } catch {
      XCTFail()
    }

    struct Poison: Error, Hashable {}

    let addressRegex = Regex {
      "0x"
      Capture(Repeat(.hexDigit, count: 8)) { hex -> Int in
        let i = Int(hex, radix: 16)!
        if i == 0xdeadbeef {
          throw Poison()
        }
        return i
      }
    }

    do {
      guard let m = try addressRegex.wholeMatch(in: "0x1234567f") else {
        XCTFail()
        return
      }
      XCTAssertEqual(m.0, "0x1234567f")
      XCTAssertEqual(m.1, 0x1234567f)
    } catch {
      XCTFail()
    }

    do {
      _ = try addressRegex.wholeMatch(in: "0xdeadbeef")
      XCTFail()
    } catch let e as Poison {
      XCTAssertEqual(e, Poison())
    } catch {
      XCTFail()
    }


  }

  func testCustomRegexThrows() {

    func customTest<Match: Equatable, E: Error & Equatable>(
      _ regex: Regex<Match>,
      _ tests: (input: String, match: Match?, expectError: E?)...,
      file: StaticString = #file,
      line: UInt = #line
    ) {
      for (input, match, expectError) in tests {
        do {
          let result = try regex.wholeMatch(in: input)?.output
          XCTAssertEqual(result, match)
        } catch let e as E {
          XCTAssertEqual(e, expectError)
        } catch {
          XCTFail()
        }
      }
    }

    func customTest<Match: Equatable, Error1: Error & Equatable, Error2: Error & Equatable>(
      _ regex: Regex<Match>,
      _ tests: (input: String, match: Match?, expectError1: Error1?, expectError2: Error2?)...,
      file: StaticString = #file,
      line: UInt = #line
    ) {
      for (input, match, expectError1, expectError2) in tests {
        do {
          let result = try regex.wholeMatch(in: input)?.output
          XCTAssertEqual(result, match)
        } catch let e as Error1 {
          XCTAssertEqual(e, expectError1, input, file: file, line: line)
        } catch let e as Error2 {
          XCTAssertEqual(e, expectError2, input, file: file, line: line)
        } catch {
          XCTFail("caught error: \(error.localizedDescription)")
        }
      }
    }

    func customTest<Capture: Equatable, Error1: Error & Equatable, Error2: Error & Equatable>(
      _ regex: Regex<(Substring, Capture)>,
      _ tests: (input: String, match: (Substring, Capture)?, expectError1: Error1?, expectError2: Error2?)...,
      file: StaticString = #file,
      line: UInt = #line
    ) {
      for (input, match, expectError1, expectError2) in tests {
        do {
          let result = try regex.wholeMatch(in: input)?.output
          XCTAssertEqual(result?.0, match?.0, file: file, line: line)
          XCTAssertEqual(result?.1, match?.1, file: file, line: line)
        } catch let e as Error1 {
          XCTAssertEqual(e, expectError1, input, file: file, line: line)
        } catch let e as Error2 {
          XCTAssertEqual(e, expectError2, input, file: file, line: line)
        } catch {
          XCTFail("caught error: \(error.localizedDescription)")
        }
      }
    }

    func customTest<Capture1: Equatable, Capture2: Equatable, Error1: Error & Equatable, Error2: Error & Equatable>(
      _ regex: Regex<(Substring, Capture1, Capture2)>,
      _ tests: (input: String, match: (Substring, Capture1, Capture2)?, expectError1: Error1?, expectError2: Error2?)...,
      file: StaticString = #file,
      line: UInt = #line
    ) {
      for (input, match, expectError1, expectError2) in tests {
        do {
          let result = try regex.wholeMatch(in: input)?.output
          XCTAssertEqual(result?.0, match?.0, file: file, line: line)
          XCTAssertEqual(result?.1, match?.1, file: file, line: line)
          XCTAssertEqual(result?.2, match?.2, file: file, line: line)
        } catch let e as Error1 {
          XCTAssertEqual(e, expectError1, input,  file: file, line: line)
        } catch let e as Error2 {
          XCTAssertEqual(e, expectError2, input, file: file, line: line)
        } catch {
          XCTFail("caught error: \(error.localizedDescription)")
        }
      }
    }

    // No capture, one error
    customTest(
      Regex {
        IntParser()
      },
      ("zzz", nil, IntParser.ParseError()),
      ("x10x", nil, IntParser.ParseError()),
      ("30", 30, nil)
    )

    customTest(
      Regex {
        CurrencyParser()
      },
      ("USD", .usd, nil),
      ("NTD", .ntd, nil),
      ("NTD USD", nil, nil),
      ("DEM", nil, CurrencyParser.ParseError.deprecated),
      ("XXX", nil, CurrencyParser.ParseError.unrecognized)
    )

    // No capture, two errors
    customTest(
      Regex {
        IntParser()
        " "
        IntParser()
      },
      ("20304 100", "20304 100", nil, nil),
      ("20304.445 200", nil, IntParser.ParseError(), nil),
      ("20304 200.123", nil, nil, IntParser.ParseError()),
      ("20304.445 200.123", nil, IntParser.ParseError(), IntParser.ParseError())
    )

    customTest(
      Regex {
        CurrencyParser()
        IntParser()
      },
      ("USD100", "USD100", nil, nil),
      ("XXX100", nil, CurrencyParser.ParseError.unrecognized, nil),
      ("USD100.000", nil, nil, IntParser.ParseError()),
      ("XXX100.0000", nil, CurrencyParser.ParseError.unrecognized, IntParser.ParseError())
    )

    // One capture, two errors: One error is thrown from inside a capture,
    // while the other one is thrown from outside
    customTest(
      Regex {
        Capture { CurrencyParser() }
        IntParser()
      },
      ("USD100", ("USD100", .usd), nil, nil),
      ("NTD305.5", nil, nil, IntParser.ParseError()),
      ("DEM200", ("DEM200", .dem), CurrencyParser.ParseError.deprecated, nil),
      ("XXX", nil, CurrencyParser.ParseError.unrecognized, IntParser.ParseError())
    )

    customTest(
      Regex {
        CurrencyParser()
        Capture { IntParser() }
      },
      ("USD100", ("USD100", 100), nil, nil),
      ("NTD305.5", nil, nil, IntParser.ParseError()),
      ("DEM200", ("DEM200", 200), CurrencyParser.ParseError.deprecated, nil),
      ("XXX", nil, CurrencyParser.ParseError.unrecognized, IntParser.ParseError())
    )

    // One capture, two errors: Both errors are thrown from inside the capture
    customTest(
      Regex {
        Capture {
          CurrencyParser()
          IntParser()
        }
      },
      ("USD100", ("USD100", "USD100"), nil, nil),
      ("NTD305.5", nil, nil, IntParser.ParseError()),
      ("DEM200", ("DEM200", "DEM200"), CurrencyParser.ParseError.deprecated, nil),
      ("XXX", nil, CurrencyParser.ParseError.unrecognized, IntParser.ParseError())
    )

    // Two captures, two errors: Different erros are thrown from inside captures
    customTest(
      Regex {
        Capture(CurrencyParser())
        Capture(IntParser())
      },
      ("USD100", ("USD100", .usd, 100), nil, nil),
      ("NTD500", ("NTD500", .ntd, 500), nil, nil),
      ("XXX20", nil, CurrencyParser.ParseError.unrecognized, IntParser.ParseError()),
      ("DEM500", nil, CurrencyParser.ParseError.deprecated, nil),
      ("DEM500.345", nil, CurrencyParser.ParseError.deprecated, IntParser.ParseError()),
      ("NTD100.345", nil, nil, IntParser.ParseError())
    )

  }


  func testMatchVarients() {
    func customTest<Match: Equatable>(
      _ regex: Regex<Match>,
      _ input: Concat,
      expected: (wholeMatch: Match?, firstMatch: Match?, prefixMatch: Match?),
      file: StaticString = #file, line: UInt = #line
    ) {
      let wholeResult = input.wholeMatch(of: regex)?.output
      let firstResult = input.firstMatch(of: regex)?.output
      let prefixResult = input.prefixMatch(of: regex)?.output
      XCTAssertEqual(wholeResult, expected.wholeMatch, file: file, line: line)
      XCTAssertEqual(firstResult, expected.firstMatch, file: file, line: line)
      XCTAssertEqual(prefixResult, expected.prefixMatch, file: file, line: line)
    }

    typealias CaptureMatch1 = (Substring, Int?)
    func customTest(
      _ regex: Regex<CaptureMatch1>,
      _ input: Concat,
      expected: (wholeMatch: CaptureMatch1?, firstMatch: CaptureMatch1?, prefixMatch: CaptureMatch1?),
      file: StaticString = #file, line: UInt = #line
    ) {
      let wholeResult = input.wholeMatch(of: regex)?.output
      let firstResult = input.firstMatch(of: regex)?.output
      let prefixResult = input.prefixMatch(of: regex)?.output
      XCTAssertEqual(wholeResult?.0, expected.wholeMatch?.0, file: file, line: line)
      XCTAssertEqual(wholeResult?.1, expected.wholeMatch?.1, file: file, line: line)

      XCTAssertEqual(firstResult?.0, expected.firstMatch?.0, file: file, line: line)
      XCTAssertEqual(firstResult?.1, expected.firstMatch?.1, file: file, line: line)

      XCTAssertEqual(prefixResult?.0, expected.prefixMatch?.0, file: file, line: line)
      XCTAssertEqual(prefixResult?.1, expected.prefixMatch?.1, file: file, line: line)
    }

    var regex = Regex {
      OneOrMore(.digit)
    }

    customTest(regex, Concat("amy", 2023), expected:(nil, "2023", nil)) // amy2023
    customTest(regex, Concat("amy2023", nil), expected:(nil, "2023", nil))
    customTest(regex, Concat("amy", nil), expected:(nil, nil, nil))
    customTest(regex, Concat("", 2023), expected:("2023", "2023", "2023")) // 2023
    customTest(regex, Concat("bob012b", 2023), expected:(nil, "012", nil)) // b012b2023
    customTest(regex, Concat("bob012b", nil), expected:(nil, "012", nil))
    customTest(regex, Concat("007bob", 2023), expected:(nil, "007", "007"))
    customTest(regex, Concat("", nil), expected:(nil, nil, nil))

    regex = Regex {
      OneOrMore(CharacterClass("a"..."z"))
    }

    customTest(regex, Concat("amy", 2023), expected:(nil, "amy", "amy")) // amy2023
    customTest(regex, Concat("amy", nil), expected:("amy", "amy", "amy"))
    customTest(regex, Concat("amy2022-bob", 2023), expected:(nil, "amy", "amy")) // amy2023
    customTest(regex, Concat("", 2023), expected:(nil, nil, nil)) // 2023
    customTest(regex, Concat("bob012b", 2023), expected:(nil, "bob", "bob")) // b012b2023
    customTest(regex, Concat("bob012b", nil), expected:(nil, "bob", "bob"))
    customTest(regex, Concat("007bob", 2023), expected:(nil, "bob", nil))
    customTest(regex, Concat("", nil), expected:(nil, nil, nil))

    regex = Regex {
      OneOrMore {
        CharacterClass("A"..."Z")
        OneOrMore(CharacterClass("a"..."z"))
        Repeat(.digit, count: 2)
      }
    }

    customTest(regex, Concat("Amy12345", nil), expected:(nil, "Amy12", "Amy12"))
    customTest(regex, Concat("Amy", 2023), expected:(nil, "Amy20", "Amy20"))
    customTest(regex, Concat("Amy", 23), expected:("Amy23", "Amy23", "Amy23"))
    customTest(regex, Concat("", 2023), expected:(nil, nil, nil)) // 2023
    customTest(regex, Concat("Amy23 Boba17", nil), expected:(nil, "Amy23", "Amy23"))
    customTest(regex, Concat("amy23 Boba17", nil), expected:(nil, "Boba17", nil))
    customTest(regex, Concat("Amy23 boba17", nil), expected:(nil, "Amy23", "Amy23"))
    customTest(regex, Concat("amy23 Boba", 17), expected:(nil, "Boba17", nil))
    customTest(regex, Concat("Amy23Boba17", nil), expected:("Amy23Boba17", "Amy23Boba17", "Amy23Boba17"))
    customTest(regex, Concat("Amy23Boba", 17), expected:("Amy23Boba17", "Amy23Boba17", "Amy23Boba17"))
    customTest(regex, Concat("23 Boba", 17), expected:(nil, "Boba17", nil))

    let twoDigitRegex = Regex {
      OneOrMore {
        CharacterClass("A"..."Z")
        OneOrMore(CharacterClass("a"..."z"))
        Capture<(Substring, Int?)>(Repeat(.digit, count: 2)) { Int($0) }
      }
    }

    customTest(twoDigitRegex, Concat("Amy12345", nil), expected: (nil, ("Amy12", 12), ("Amy12", 12)))
    customTest(twoDigitRegex, Concat("Amy", 12345), expected: (nil, ("Amy12", 12), ("Amy12", 12)))
    customTest(twoDigitRegex, Concat("Amy", 12), expected: (("Amy12", 12), ("Amy12", 12), ("Amy12", 12)))
    customTest(twoDigitRegex, Concat("Amy23 Boba", 17), expected: (nil, firstMatch: ("Amy23", 23), prefixMatch: ("Amy23", 23)))
    customTest(twoDigitRegex, Concat("amy23 Boba20", 23), expected:(nil, ("Boba20", 20), nil))
    customTest(twoDigitRegex, Concat("Amy23Boba17", nil), expected:(("Amy23Boba17", 17), ("Amy23Boba17", 17), ("Amy23Boba17", 17)))
    customTest(twoDigitRegex, Concat("Amy23Boba", 17), expected:(("Amy23Boba17", 17), ("Amy23Boba17", 17), ("Amy23Boba17", 17)))

    let millennium = Regex {
      CharacterClass("A"..."Z")
      OneOrMore(CharacterClass("a"..."z"))
      Capture { Repeat(.digit, count: 4) } transform: { v -> Int? in
        guard let year = Int(v) else { return nil }
        return year > 2000 ? year : nil
      }
    }

    customTest(millennium, Concat("Amy2025", nil), expected: (("Amy2025", 2025), ("Amy2025", 2025), ("Amy2025", 2025)))
    customTest(millennium, Concat("Amy", 2025), expected: (("Amy2025", 2025), ("Amy2025", 2025), ("Amy2025", 2025)))
    customTest(millennium, Concat("Amy1995", nil), expected: (("Amy1995", nil), ("Amy1995", nil), ("Amy1995", nil)))
    customTest(millennium, Concat("Amy", 1995), expected: (("Amy1995", nil), ("Amy1995", nil), ("Amy1995", nil)))
    customTest(millennium, Concat("amy2025", nil), expected: (nil, nil, nil))
    customTest(millennium, Concat("amy", 2025), expected: (nil, nil, nil))
  }
}

