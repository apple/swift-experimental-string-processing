
import _StringProcessing
import XCTest

// Test that our existential capture and concrete captures are
// the same
private func checkSame(
  _ aro: AnyRegexOutput,
  _ concrete: (Substring, fieldA: Substring, fieldB: Substring)
) {
  XCTAssertEqual(aro[0].substring, concrete.0)

  XCTAssertEqual(aro["fieldA"]!.substring, concrete.1)
  XCTAssertEqual(aro["fieldA"]!.substring, concrete.fieldA)

  XCTAssertEqual(aro[1].substring, concrete.1)

  XCTAssertEqual(aro["fieldB"]!.substring, concrete.2)
  XCTAssertEqual(aro["fieldB"]!.substring, concrete.fieldB)

  XCTAssertEqual(aro[2].substring, concrete.2)

}
private func checkSame(
  _ aro: Regex<AnyRegexOutput>.Match,
  _ concrete: Regex<(Substring, fieldA: Substring, fieldB: Substring)>.Match
) {
  checkSame(aro.output, concrete.output)

  XCTAssertEqual(aro.0, concrete.0)
  XCTAssertEqual(aro[0].substring, concrete.0)

  XCTAssertEqual(aro["fieldA"]!.substring, concrete.1)
  XCTAssertEqual(aro["fieldA"]!.substring, concrete.fieldA)
  XCTAssertEqual(aro[1].substring, concrete.1)

  XCTAssertEqual(aro["fieldB"]!.substring, concrete.2)
  XCTAssertEqual(aro["fieldB"]!.substring, concrete.fieldB)
  XCTAssertEqual(aro[2].substring, concrete.2)
}
private func checkSame(
  _ aro: Regex<AnyRegexOutput>,
  _ concrete: Regex<(Substring, fieldA: Substring, fieldB: Substring)>
) {
  XCTAssertEqual(
    aro.contains(captureNamed: "fieldA"),
    concrete.contains(captureNamed: "fieldA"))
  XCTAssertEqual(
    aro.contains(captureNamed: "fieldB"),
    concrete.contains(captureNamed: "fieldB"))
  XCTAssertEqual(
    aro.contains(captureNamed: "notAField"),
    concrete.contains(captureNamed: "notAField"))
}

extension RegexTests {
  func testAnyRegexOutput() {
    let regex = try! Regex(#"""
    (?x)
    (?<fieldA> [^,]*)
    ,
    (?<fieldB> [^,]*)
    """#)

    let match = "abc,def".wholeMatch(of: regex)!
    XCTAssertEqual(match.0, "abc,def")
    XCTAssertEqual(match[0].substring, "abc,def")

    XCTAssertEqual(match["fieldA"]!.substring, "abc")
    XCTAssertEqual(match.output["fieldA"]!.substring, "abc")
    XCTAssertEqual(match[1].substring, "abc")

    XCTAssertEqual(match["fieldB"]!.substring, "def")
    XCTAssertEqual(match.output["fieldB"]!.substring, "def")
    XCTAssertEqual(match[2].substring, "def")

    XCTAssertNil(match["notACapture"])
    XCTAssertNil(match.output["notACapture"])
    XCTAssertEqual(match.count, 3)

    XCTAssert(regex.contains(captureNamed: "fieldA"))
    XCTAssert(regex.contains(captureNamed: "fieldB"))
    XCTAssertFalse(regex.contains(captureNamed: "notAField"))

    // MARK: Check equivalence with concrete

    let regexConcrete:
      Regex<(Substring, fieldA: Substring, fieldB: Substring)>
    = try! Regex(#"""
    (?x)
    (?<fieldA> [^,]*)
    ,
    (?<fieldB> [^,]*)
    """#)
    checkSame(regex, regexConcrete)

    let matchConcrete = "abc,def".wholeMatch(of: regexConcrete)!
    checkSame(match, matchConcrete)

    let output = match.output
    let concreteOutput = matchConcrete.output
    checkSame(output, concreteOutput)

    // TODO: ARO init from concrete match tuple

    let concreteOutputCasted = output.extractValues(
      as: (Substring, fieldA: Substring, fieldB: Substring).self
    )!
    checkSame(output, concreteOutputCasted)

    var concreteOutputCopy = concreteOutput
    concreteOutputCopy = output.extractValues()!
    checkSame(output, concreteOutputCopy)

    // TODO: Regex<ARO>.Match: init from tuple match and as to tuple match

    // TODO: Regex<ARO>: init from tuple regex and as cast to tuple regex

  }

  func testDynamicCaptures() throws {
    do {
      let regex = try Regex("aabcc.")
      let line = "aabccd"
      let match = try XCTUnwrap(line.wholeMatch(of: regex))
      XCTAssertEqual(match.0, line[...])
      let output = match.output
      XCTAssertEqual(output[0].substring, line[...])
    }
    do {
      let regex = try Regex(
          #"""
          (?<lower>[0-9A-F]+)(?:\.\.(?<upper>[0-9A-F]+))?\s+;\s+(?<desc>\w+).*
          """#)
      let line = """
        A6F0..A6F1    ; Extend # Mn   [2] BAMUM COMBINING MARK KOQNDON..BAMUM \
        COMBINING MARK TUKWENTIS
        """
      let match = try XCTUnwrap(line.wholeMatch(of: regex))
      XCTAssertEqual(match.0, line[...])
      let output = match.output
      XCTAssertEqual(output[0].substring, line[...])
      XCTAssertTrue(output[1].substring == "A6F0")
      XCTAssertTrue(output["lower"]?.substring == "A6F0")
      XCTAssertTrue(output[2].substring == "A6F1")
      XCTAssertTrue(output["upper"]?.substring == "A6F1")
      XCTAssertTrue(output[3].substring == "Extend")
      XCTAssertTrue(output["desc"]?.substring == "Extend")
      let typedOutput = try XCTUnwrap(
        output.extractValues(
          as: (Substring, lower: Substring, upper: Substring?, Substring).self))
      XCTAssertEqual(typedOutput.0, line[...])
      XCTAssertTrue(typedOutput.lower == "A6F0")
      XCTAssertTrue(typedOutput.upper == "A6F1")
      XCTAssertTrue(typedOutput.3 == "Extend")

      // Extracting as different argument labels is allowed
      let typedOutput2 = try XCTUnwrap(
        output.extractValues(
          as: (Substring, first: Substring, Substring?, third: Substring).self))
      XCTAssertEqual(typedOutput2.0, line[...])
      XCTAssertTrue(typedOutput2.first == "A6F0")
      XCTAssertTrue(typedOutput2.2 == "A6F1")
      XCTAssertTrue(typedOutput2.third == "Extend")

    }
  }

  func testCaptureNames() {
    let particle = try! Regex(#"(?<name>particle)-(?<id>\d+)"#)
    let particleInput = "particle-123"

    let uuid = try! Regex(#"(?<name>uuid): (?<id>[-a-f\d]+)"#)
    let uuidInput = "uuid: 1234-abcd-5678"

    let digitID = try! Regex(#"(?<id>\d+): (?<name>\w+)"#)
    let digitInput = "1234: insert_name_here"

    func expect(
      _ regex: Regex<AnyRegexOutput>,
      _ input: String,
      capture name: String,
      _ expected: String?
    ) {
      guard let match = input.wholeMatch(of: regex),
            let cap = match[name]?.substring
      else {
        XCTAssertNil(expected)
        return
      }
      XCTAssertEqual(String(cap), expected)
    }

    expect(particle, particleInput, capture: "id", "123")
    expect(particle, particleInput, capture: "name", "particle")
    expect(uuid, particleInput, capture: "id", nil)
    expect(uuid, particleInput, capture: "name", nil)
    expect(digitID, particleInput, capture: "id", nil)
    expect(digitID, particleInput, capture: "name", nil)

    expect(particle, uuidInput, capture: "id", nil)
    expect(particle, uuidInput, capture: "name", nil)
    expect(uuid, uuidInput, capture: "id", "1234-abcd-5678")
    expect(uuid, uuidInput, capture: "name", "uuid")
    expect(digitID, uuidInput, capture: "id", nil)
    expect(digitID, uuidInput, capture: "name", nil)

    expect(particle, digitInput, capture: "id", nil)
    expect(particle, digitInput, capture: "name", nil)
    expect(uuid, digitInput, capture: "id", nil)
    expect(uuid, digitInput, capture: "name", nil)
    expect(digitID, digitInput, capture: "id", "1234")
    expect(digitID, digitInput, capture: "name", "insert_name_here")
  }
}
