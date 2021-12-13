@testable import _MatchingEngine

import XCTest
@testable import _StringProcessing

func diagnose(
  _ input: String,
  expecting expected: ParseError,
  _ syntax: SyntaxOptions = .traditional,
  _ f: (inout Source) throws -> ()
) {
  var src = Source(input, syntax)
  do {
    try f(&src)
    XCTFail("""
      Passed, but expected error: \(expected)
    """)
  } catch let e as Source.LocatedError<ParseError> {
    guard e.error == expected else {
      XCTFail("""

        Expected: \(expected)
        Actual: \(e.error)")
      """)
      return
    }
  } catch let e {
    fatalError("Should be unreachable: \(e)")
  }
}

extension RegexTests {
  func testLexicalAnalysis() {
    diagnose("a", expecting: .expected("b")) { src in
      try src.expect("b")
    }

    diagnose("", expecting: .unexpectedEndOfInput) { src in
      try src.expectNonEmpty()
    }
    diagnose("a", expecting: .unexpectedEndOfInput) { src in
      try src.expect("a") // Ok
      try src.expectNonEmpty() // Error
    }

    let bigNum = "12345678901234567890"
    diagnose(bigNum, expecting: .numberOverflow(bigNum)) { src in
      _ = try src.lexNumber()
    }

    func diagnoseUniScalarOverflow(_ input: String, base: Character) {
      let scalars = input.first == "{"
                  ? String(input.dropFirst().dropLast())
                  : input
      diagnose(
        input,
        expecting: .numberOverflow(scalars)
      ) { src in
        _ = try src.expectUnicodeScalar(escapedCharacter: base)
      }
    }
    func diagnoseUniScalar(
      _ input: String,
      base: Character,
      expectedDigits numDigits: Int
    ) {
      let scalars = input.first == "{"
                  ? String(input.dropFirst().dropLast())
                  : input
      diagnose(
        input,
        expecting: .expectedNumDigits(scalars, numDigits)
      ) { src in
        _ = try src.expectUnicodeScalar(escapedCharacter: base)
      }
      _ = scalars
    }

// FIXME:
//    diagnoseUniScalar(
//      "12ab", base: "x", expectedDigits: 2)
    diagnoseUniScalar(
      "12", base: "u", expectedDigits: 4)
    diagnoseUniScalar(
      "12", base: "U", expectedDigits: 8)
    diagnoseUniScalarOverflow("{123456789}", base: "u")
    diagnoseUniScalarOverflow("{123456789}", base: "x")
    
    // TODO: want to dummy print out source ranges, etc, test that.
  }

}
