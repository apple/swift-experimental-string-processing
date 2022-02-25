import _StringProcessing
import XCTest

// A nibbler processes a single character from a string
private protocol Nibbler: CustomRegexComponent {
  func nibble(_: Character) -> Match?
}

extension Nibbler {
  // Default implementation, just feed the character in
  func match(
    _ input: String,
    startingAt index: String.Index,
    in bounds: Range<String.Index>
  ) -> (upperBound: String.Index, match: Match)? {
    guard index != bounds.upperBound, let res = nibble(input[index]) else {
      return nil
    }
    return (input.index(after: index), res)
  }
}


// A number nibbler
private struct Numbler: Nibbler {
  typealias Match = Int
  func nibble(_ c: Character) -> Int? {
    c.wholeNumberValue
  }
}

// An ASCII value nibbler
private struct Asciibbler: Nibbler {
  typealias Match = UInt8
  func nibble(_ c: Character) -> UInt8? {
    c.asciiValue
  }
}

enum MatchCall {
  case match
  case firstMatch
}

func customTest<Match: Equatable>(
  _ regex: Regex<Match>,
  _ tests: (input: String, call: MatchCall, match: Match?)...
) {
  for (input, call, match) in tests {
    let result: Match?
    switch call {
    case .match:
      result = input.match(regex)?.match
    case .firstMatch:
      result = input.firstMatch(of: regex)?.result
    }
    XCTAssertEqual(result, match)
  }
}

extension RegexTests {

  // TODO: Refactor below into more exhaustive, declarative
  // tests.
  func testCustomRegexComponents() {
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
        oneOrMore { Numbler() }
      },
      ("ab123c", .firstMatch, "123"),
      ("abc", .firstMatch, nil),
      ("55z", .match, nil),
      ("55z", .firstMatch, "55"))

    // FIXME: Requires we return a value instead of a range
//    customTest(
//      Regex {
//        Numbler()
//      },
//      ("ab123c", .firstMatch, 1),
//      ("abc", .firstMatch, nil),
//      ("55z", .match, nil),
//      ("55z", .firstMatch, 5))

    // TODO: Convert below tests to better infra. Right now
    // it's hard because `Match` is constrained to be
    // `Equatable` which tuples cannot be.

    let regex3 = Regex {
      capture {
        oneOrMore {
          Numbler()
        }
      }
    }

    guard let res3 = "ab123c".firstMatch(of: regex3) else {
      XCTFail()
      return
    }

    XCTAssertEqual(res3.match, "123")
    XCTAssertEqual(res3.result.0, "123")
    XCTAssertEqual(res3.result.1, "123")

    let regex4 = Regex {
      oneOrMore {
        capture { Numbler() }
      }
    }

    guard let res4 = "ab123c".firstMatch(of: regex4) else {
      XCTFail()
      return
    }

    XCTAssertEqual(res4.result.0, "123")
    XCTAssertEqual(res4.result.1, 3)
  }

}
