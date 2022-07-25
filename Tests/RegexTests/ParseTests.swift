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

@testable @_spi(CompilerInterface) import _RegexParser

import XCTest
@testable import _StringProcessing

extension AST.Node: ExpressibleByExtendedGraphemeClusterLiteral {
  public typealias ExtendedGraphemeClusterLiteralType = Character
  public init(extendedGraphemeClusterLiteral value: Character) {
    self = _StringProcessing.atom(.char(value))
  }
}
extension AST.Atom: ExpressibleByExtendedGraphemeClusterLiteral {
  public typealias ExtendedGraphemeClusterLiteralType = Character
  public init(extendedGraphemeClusterLiteral value: Character) {
    self = atom_a(.char(value))
  }
}
extension AST.CustomCharacterClass.Member: ExpressibleByExtendedGraphemeClusterLiteral {
  public typealias ExtendedGraphemeClusterLiteralType = Character
  public init(extendedGraphemeClusterLiteral value: Character) {
    self = atom_m((.char(value)))
  }
}

class RegexTests: XCTestCase {}

func parseTest(
  _ input: String, _ expectedAST: AST.Node,
  throwsError expectedErrors: ParseError..., unsupported: Bool = false,
  uncheckedErrors: Bool = false, syntax: SyntaxOptions = .traditional,
  captures expectedCaptures: CaptureList = [],
  file: StaticString = #file,
  line: UInt = #line
) {
  parseTest(
    input, .init(expectedAST, globalOptions: nil, diags: Diagnostics()),
    throwsError: expectedErrors, unsupported: unsupported,
    uncheckedErrors: uncheckedErrors, syntax: syntax,
    captures: expectedCaptures, file: file, line: line
  )
}

func parseTest(
  _ input: String, _ expectedAST: AST,
  throwsError expectedErrors: [ParseError] = [], unsupported: Bool = false,
  uncheckedErrors: Bool = false,
  syntax: SyntaxOptions = .traditional,
  captures expectedCaptures: CaptureList = [],
  file: StaticString = #file,
  line: UInt = #line
) {
  let ast = parseWithRecovery(input, syntax)
  matchDiagnostics(
    expectedErrors, for: ast, unsupported: unsupported,
    unchecked: uncheckedErrors, file: file, line: line
  )
  guard ast == expectedAST
          || ast._dump() == expectedAST._dump() // EQ workaround
  else {
    XCTFail("""

              Expected: \(expectedAST._dump())
              Found:    \(ast._dump())
              """,
            file: file, line: line)
    return
  }
  var captures = ast.captureList.withoutLocs
  // Peel off the whole match.
  captures.captures.removeFirst()
  guard captures == expectedCaptures else {
    XCTFail("""

              Expected captures: \(expectedCaptures)
              Found:             \(captures)
              """,
            file: file, line: line)
    return
  }

  // Test capture structure round trip serialization.
  let capStruct = captures._captureStructure
  let serializedCapturesSize = CaptureStructure.serializationBufferSize(
    forInputUTF8CodeUnitCount: input.utf8.count)
  let serializedCaptures = UnsafeMutableRawBufferPointer.allocate(
    byteCount: serializedCapturesSize,
    alignment: MemoryLayout<Int8>.alignment)

  capStruct.encode(to: serializedCaptures)
  guard let decodedCaptures = CaptureStructure(
    decoding: UnsafeRawBufferPointer(serializedCaptures)
  ) else {
    XCTFail("""
      Malformed capture structure serialization
      Captures: \(captures)
      Serialization: \(Array(serializedCaptures))
      """)
    return
  }
  guard decodedCaptures == capStruct else {
    XCTFail("""

              Expected captures:  \(expectedCaptures)
              Decoded:            \(decodedCaptures)
              """,
            file: file, line: line)
    return
  }
  serializedCaptures.deallocate()
}

/// Test delimiter lexing. Takes an input string that starts with a regex
/// literal. If `ignoreTrailing` is true, there may be additional characters
/// that follow the literal that are not considered part of it.
@discardableResult
func delimiterLexingTest(
  _ input: String, ignoreTrailing: Bool = false,
  file: StaticString = #file, line: UInt = #line
) -> String {
  input.withCString(encodedAs: UTF8.self) { ptr in
    let endPtr = ptr + input.utf8.count
    let (contents, delim, end) = try! lexRegex(
      start: ptr, end: endPtr, delimiters: Delimiter.allDelimiters)
    if ignoreTrailing {
      XCTAssertNotEqual(end, endPtr, file: file, line: line)
    } else {
      XCTAssertEqual(end, endPtr, file: file, line: line)
    }

    let rawPtr = UnsafeRawPointer(ptr)
    let buffer = UnsafeRawBufferPointer(start: rawPtr, count: end - rawPtr)
    let literal = String(decoding: buffer, as: UTF8.self)

    let (parseContents, parseDelim) = droppingRegexDelimiters(literal)
    XCTAssertEqual(contents, parseContents, file: file, line: line)
    XCTAssertEqual(delim, parseDelim, file: file, line: line)
    return literal
  }
}

/// Test parsing an input string with regex delimiters. If `ignoreTrailing` is
/// true, there may be additional characters that follow the literal that are
/// not considered part of it.
func parseWithDelimitersTest(
  _ input: String, _ expecting: AST.Node,
  throwsError expectedErrors: ParseError..., unsupported: Bool = false,
  uncheckedErrors: Bool = false, ignoreTrailing: Bool = false,
  file: StaticString = #file, line: UInt = #line
) {
  // First try lexing.
  let literal = delimiterLexingTest(
    input, ignoreTrailing: ignoreTrailing, file: file, line: line)

  let ast = parseWithDelimitersWithRecovery(literal)
  matchDiagnostics(
    expectedErrors, for: ast, unsupported: unsupported,
    unchecked: uncheckedErrors, file: file, line: line
  )
  guard ast.root == expecting
          || ast.root._dump() == expecting._dump() // EQ workaround
  else {
    XCTFail("""
              Expected: \(expecting._dump())
              Found:    \(ast.root._dump())
              """,
            file: file, line: line)
    return
  }
}

/// Make sure the AST for two regex strings get compared differently.
func parseNotEqualTest(
  _ lhs: String, _ rhs: String,
  syntax: SyntaxOptions = .traditional,
  file: StaticString = #file, line: UInt = #line
) {
  let lhsAST = parseWithRecovery(lhs, syntax)
  let rhsAST = parseWithRecovery(rhs, syntax)
  if lhsAST == rhsAST || lhsAST._dump() == rhsAST._dump() {
    XCTFail("""
              AST: \(lhsAST._dump())
              Should not be equal to: \(rhsAST._dump())
              """,
            file: file, line: line)
  }
}

func rangeTest(
  _ input: String, syntax: SyntaxOptions = .traditional,
  _ expectedRange: (String) -> Range<Int>,
  at locFn: (AST.Node) -> SourceLocation = \.location,
  file: StaticString = #file, line: UInt = #line
) {
  let ast = parseWithRecovery(input, syntax).root
  let range = input.offsets(of: locFn(ast).range)
  let expected = expectedRange(input)

  guard range == expected else {
    XCTFail("""
            Expected range: "\(expected)"
            Found range: "\(range)"
            """,
            file: file, line: line)
    return
  }
}

func matchDiagnostics(
  _ expected: [ParseError], for ast: AST, unsupported: Bool, unchecked: Bool,
  file: StaticString, line: UInt
) {
  guard !unchecked else { return }

  var errors = Set<ParseError>()
  for diag in ast.diags.diags where diag.isAnyError {
    guard let underlying = diag.underlyingParseError else {
      XCTFail(
        "Unknown error emitted: '\(diag.message)'", file: file, line: line)
      continue
    }
    // TODO: We should be uniquing based on source location, and failing if we
    // emit duplicate diagnostics at the same location.
    errors.insert(underlying)
  }

  // Filter out any unsupported errors if needed.
  if unsupported {
    errors = errors.filter {
      if case .unsupported = $0 { return false } else { return true }
    }
  }
  for mismatched in errors.symmetricDifference(expected) {
    if errors.contains(mismatched) {
      XCTFail("""
        Unexpected error: \(mismatched)
      """, file: file, line: line)
    } else {
      XCTFail("""

        Expected error not emitted: \(mismatched)
        for AST: \(ast)
      """, file: file, line: line)
    }
  }
}

func diagnosticTest(
  _ input: String, _ expectedErrors: ParseError..., unsupported: Bool = false,
  syntax: SyntaxOptions = .traditional,
  file: StaticString = #file, line: UInt = #line
) {
  let ast = parseWithRecovery(input, syntax)
  matchDiagnostics(
    expectedErrors, for: ast, unsupported: unsupported, unchecked: false,
    file: file, line: line
  )
}

func diagnosticWithDelimitersTest(
  _ input: String, _ expectedErrors: ParseError..., unsupported: Bool = false,
  ignoreTrailing: Bool = false, file: StaticString = #file, line: UInt = #line
) {
  // First try lexing.
  let literal = delimiterLexingTest(
    input, ignoreTrailing: ignoreTrailing, file: file, line: line)

  let ast = parseWithDelimitersWithRecovery(literal)
  matchDiagnostics(
    expectedErrors, for: ast, unsupported: unsupported, unchecked: false,
    file: file, line: line
  )
}

func delimiterLexingDiagnosticTest(
  _ input: String, _ expected: DelimiterLexError.Kind,
  syntax: SyntaxOptions = .traditional,
  file: StaticString = #file, line: UInt = #line
) {
  do {
    _ = try input.withCString { ptr in
      try lexRegex(
        start: ptr, end: ptr + input.count, delimiters: Delimiter.allDelimiters)
    }
    XCTFail("""
      Passed, but expected error: \(expected)
    """, file: file, line: line)
  } catch let e as DelimiterLexError {
    guard e.kind == expected else {
      XCTFail("""

        Expected: \(expected)
        Actual: \(e.kind)
      """, file: file, line: line)
      return
    }
  } catch let e {
    XCTFail("Unexpected error type: \(e)", file: file, line: line)
  }
}

func compilerInterfaceDiagnosticMessageTest(
  _ input: String, _ expectedErr: String,
  file: StaticString = #file, line: UInt = #line
) {
  do {
    let captureBuffer = UnsafeMutableRawBufferPointer(start: nil, count: 0)
    _ = try swiftCompilerParseRegexLiteral(
      input, captureBufferOut: captureBuffer)
    XCTFail("Expected parse error", file: file, line: line)
  } catch let error as CompilerParseError {
    XCTAssertNotNil(error.location, "Error without location", file: file, line: line)
    XCTAssertEqual(expectedErr, error.message, file: file, line: line)
  } catch {
    fatalError("Expected CompilerParseError")
  }
}

extension RegexTests {
  func testParse() {
    parseTest(
      "abc", concat("a", "b", "c"))
    parseTest(
      #"abc\+d*"#,
      concat("a", "b", "c", "+", zeroOrMore(of: "d")))
    parseTest(
      "a(b)", concat("a", capture("b")),
      captures: [.cap])
    parseTest(
      "abc(?:de)+fghi*k|j",
      alt(
        concat(
          "a", "b", "c",
          oneOrMore(
            of: nonCapture(concat("d", "e"))),
          "f", "g", "h", zeroOrMore(of: "i"), "k"),
        "j"))
    parseTest(
      "a(?:b|c)?d",
      concat("a", zeroOrOne(
        of: nonCapture(alt("b", "c"))), "d"))
    parseTest(
      "a?b??c+d+?e*f*?",
      concat(
        zeroOrOne(of: "a"), zeroOrOne(.reluctant, of: "b"),
        oneOrMore(of: "c"), oneOrMore(.reluctant, of: "d"),
        zeroOrMore(of: "e"), zeroOrMore(.reluctant, of: "f")))

    parseTest(
      "(.)*(.*)",
      concat(
        zeroOrMore(of: capture(atom(.dot))),
        capture(zeroOrMore(of: atom(.dot)))),
      captures: [.opt, .cap])
    parseTest(
      "((.))*((.)?)",
      concat(
        zeroOrMore(of: capture(capture(atom(.dot)))),
        capture(zeroOrOne(of: capture(atom(.dot))))),
      captures: [.opt, .opt, .cap, .opt])
    parseTest(
      #"abc\d"#,
      concat("a", "b", "c", escaped(.decimalDigit)))

    // MARK: Allowed combining characters

    parseTest("1\u{358}", "1\u{358}")
    parseTest(#"\ \#u{361}"#, " \u{361}")

    parseTest("e\u{301}", "e\u{301}")
    parseTest("[e\u{301}]", charClass("e\u{301}"))
    parseTest("\u{E9}", "e\u{301}")
    parseTest("[\u{E9}]", charClass("e\u{301}"))

    parseTest(
      "\\e\u{301}", "e\u{301}", throwsError: .invalidEscape("e\u{301}"))
    parseTest(
      "[\\e\u{301}]", charClass("e\u{301}"),
      throwsError: .invalidEscape("e\u{301}")
    )

    // MARK: Alternations

    parseTest(
      "a|b?c",
      alt("a", concat(zeroOrOne(of: "b"), "c")))
    parseTest(
      "(a|b)c",
      concat(capture(alt("a", "b")), "c"),
      captures: [.cap])
    parseTest(
      "(a)|b",
      alt(capture("a"), "b"),
      captures: [.opt])
    parseTest(
      "(a)|(b)|c",
      alt(capture("a"), capture("b"), "c"),
      captures: [.opt, .opt])
    parseTest(
      "((a|b))c",
      concat(capture(capture(alt("a", "b"))), "c"),
      captures: [.cap, .cap])
    parseTest(
      "(?:((a|b)))*?c",
      concat(quant(
        .zeroOrMore, .reluctant,
        nonCapture(capture(capture(alt("a", "b"))))), "c"),
      captures: [.opt, .opt])
    parseTest(
      "(a)|b|(c)d",
      alt(capture("a"), "b", concat(capture("c"), "d")),
      captures: [.opt, .opt])

    // Alternations with empty branches are permitted.
    parseTest("|", alt(empty(), empty()))
    parseTest("(|)", capture(alt(empty(), empty())), captures: [.cap])
    parseTest("a|", alt("a", empty()))
    parseTest("|b", alt(empty(), "b"))
    parseTest("|b|", alt(empty(), "b", empty()))
    parseTest("a|b|", alt("a", "b", empty()))
    parseTest("||c|", alt(empty(), empty(), "c", empty()))
    parseTest("|||", alt(empty(), empty(), empty(), empty()))
    parseTest("a|||d", alt("a", empty(), empty(), "d"))

    // MARK: Unicode scalars

    parseTest(
      #"a\u0065b\u{00000065}c\x65d\U00000065"#,
      concat("a", scalar("e"),
             "b", scalar("e"),
             "c", scalar("e"),
             "d", scalar("e")))

    parseTest(#"\u{00000000000000000000000000A}"#, scalar("\u{A}"))
    parseTest(#"\x{00000000000000000000000000A}"#, scalar("\u{A}"))
    parseTest(#"\o{000000000000000000000000007}"#, scalar("\u{7}"))

    parseTest(#"\o{70}"#, scalar("\u{38}"))
    parseTest(#"\0"#, scalar("\u{0}"))
    parseTest(#"\01"#, scalar("\u{1}"))
    parseTest(#"\070"#, scalar("\u{38}"))
    parseTest(#"\07A"#, concat(scalar("\u{7}"), "A"))
    parseTest(#"\08"#, concat(scalar("\u{0}"), "8"))
    parseTest(#"\0707"#, scalar("\u{1C7}"))

    parseTest(#"[\0]"#, charClass(scalar_m("\u{0}")))
    parseTest(#"[\01]"#, charClass(scalar_m("\u{1}")))
    parseTest(#"[\070]"#, charClass(scalar_m("\u{38}")))

    parseTest(#"[\07A]"#, charClass(scalar_m("\u{7}"), "A"))
    parseTest(#"[\08]"#, charClass(scalar_m("\u{0}"), "8"))
    parseTest(#"[\0707]"#, charClass(scalar_m("\u{1C7}")))

    // We take *up to* the first two valid digits for \x. No valid digits is 0.
    parseTest(#"\x"#, scalar("\u{0}"))
    parseTest(#"\x5"#, scalar("\u{5}"))
    parseTest(#"\xX"#, concat(scalar("\u{0}"), "X"))
    parseTest(#"\x5X"#, concat(scalar("\u{5}"), "X"))
    parseTest(#"\x12ab"#, concat(scalar("\u{12}"), "a", "b"))

    parseTest(#"\u{    a   }"#, scalar("\u{A}"))
    parseTest(#"\u{  a  }\u{ B }"#, concat(scalar("\u{A}"), scalar("\u{B}")))

    parseTest(#"[\u{301}]"#, charClass(scalar_m("\u{301}")))

    // MARK: Scalar sequences

    parseTest(#"\u{A bC}"#, scalarSeq("\u{A}", "\u{BC}"))
    parseTest(#"\u{ A bC }"#, scalarSeq("\u{A}", "\u{BC}"))
    parseTest(#"\u{A bC }"#, scalarSeq("\u{A}", "\u{BC}"))
    parseTest(#"\u{ A bC}"#, scalarSeq("\u{A}", "\u{BC}"))
    parseTest(#"\u{  A   b C }"#, scalarSeq("\u{A}", "\u{B}", "\u{C}"))

    parseTest(
      #"\u{3b1 3b3 3b5 3b9}"#,
      scalarSeq("\u{3b1}", "\u{3b3}", "\u{3b5}", "\u{3b9}")
    )

    // MARK: Character classes

    parseTest(#"abc\d"#, concat("a", "b", "c", escaped(.decimalDigit)))

    // FIXME: '\N' should be emitted through 'emitDot', not through the
    // _CharacterClassModel model.
    parseTest(#"\N"#, escaped(.notNewline), unsupported: true)

    parseTest(#"\R"#, escaped(.newlineSequence))

    parseTest(
      "[-|$^:?+*())(*-+-]",
      charClass(
        "-", "|", "$", "^", ":", "?", "+", "*", "(", ")", ")",
        "(", range_m("*", "+"), "-"))

    parseTest(
      "[a-b-c]", charClass(range_m("a", "b"), "-", "c"))
    parseTest(
      "[a-b-c-d]", charClass(range_m("a", "b"), "-", range_m("c", "d")))

    parseTest("[a-c---]", charClass(
      setOp(range_m("a", "c"), op: .subtraction, "-")
    ))

    parseTest("(?x)[a-c -- -]", concat(
      changeMatchingOptions(matchingOptions(adding: .extended)),
      charClass(setOp(range_m("a", "c"), op: .subtraction, "-"))
    ))

    parseTest("(?x)[a-c - - -]", concat(
      changeMatchingOptions(matchingOptions(adding: .extended)),
      charClass(range_m("a", "c"), range_m("-", "-"))
    ))

    parseTest("[-a-]", charClass("-", "a", "-"))
    parseTest("[[a]-]", charClass(charClass("a"), "-"))
    parseTest("[-[a]]", charClass("-", charClass("a")))

    parseTest(#"(?x)[ -[b]]"#, concat(
      changeMatchingOptions(matchingOptions(adding: .extended)),
      charClass("-", charClass("b"))
    ))

    parseTest(#"[ - [ ]]"#, charClass(range_m(" ", " "), charClass(" ")))
    parseTest(#"[ - [ ] ]"#, charClass(range_m(" ", " "), charClass(" "), " "))

    parseTest(#"[a-c-\Qd\E]"#, charClass(range_m("a", "c"), "-", quote_m("d")))

    parseTest("[a-z]", charClass(range_m("a", "z")))
    parseTest("[a-a]", charClass(range_m("a", "a")))
    parseTest("[B-a]", charClass(range_m("B", "a")))

    parseTest("[a-d--a-c]", charClass(
      setOp(range_m("a", "d"), op: .subtraction, range_m("a", "c"))
    ))

    parseTest("[-]", charClass("-"))
    parseTest(#"[\]]"#, charClass("]"))

    // These are metacharacters in certain contexts, but normal characters
    // otherwise.
    parseTest(
      ":-]", concat(":", "-", "]"))

    parseTest(
      "[^abc]", charClass("a", "b", "c", inverted: true))
    parseTest(
      "[a^]", charClass("a", "^"))

    // These are custom character classes, not invalid POSIX character classes.
    // TODO: This behavior is subtle, we ought to warn.
    parseTest("[[:space]]", charClass(charClass(":", "s", "p", "a", "c", "e")))
    parseTest("[:a]", charClass(":", "a"))
    parseTest("[a:]", charClass("a", ":"))
    parseTest("[:]", charClass(":"))
    parseTest("[[:]]", charClass(charClass(":")))
    parseTest("[[:a=b=c:]]", charClass(charClass(":", "a", "=", "b", "=", "c", ":")))

    parseTest(#"[[:a[b]:]]"#, charClass(charClass(":", "a", charClass("b"), ":")))
    parseTest(#"[[:a]][:]"#, concat(charClass(charClass(":", "a")), charClass(":")))
    parseTest(#"[[:a]]"#, charClass(charClass(":", "a")))
    parseTest(#"[[:}]]"#, charClass(charClass(":", "}")))
    parseTest(#"[[:{]]"#, charClass(charClass(":", "{")))
    parseTest(#"[[:}:]]"#, charClass(charClass(":", "}", ":")))

    parseTest(
      #"[:[:space:]:]"#,
      charClass(":", posixProp_m(.binary(.whitespace)), ":")
    )
    parseTest(
      #"[:a[:space:]b:]"#,
      charClass(":", "a", posixProp_m(.binary(.whitespace)), "b", ":")
    )

    // ICU parses a custom character class if it sees any of its known escape
    // sequences in a POSIX character property (though it appears to exclude
    // character class escapes e.g '\d'). We do so for any escape sequence as
    // '\' is not a valid character property character.
    parseTest(#"[:\Q:]\E]"#, charClass(":", quote_m(":]")))
    parseTest(#"[:\a:]"#, charClass(":", atom_m(.escaped(.alarm)), ":"))
    parseTest(#"[:\d:]"#, charClass(":", atom_m(.escaped(.decimalDigit)), ":"))
    parseTest(#"[:\\:]"#, charClass(":", "\\", ":"))
    parseTest(#"[:\:]"#, charClass(":", ":"))

    parseTest(
      #"\D\S\W"#,
      concat(
        escaped(.notDecimalDigit),
        escaped(.notWhitespace),
        escaped(.notWordCharacter)))

    parseTest(
      #"[\dd]"#, charClass(atom_m(.escaped(.decimalDigit)), "d"))

    parseTest(
      #"[^[\D]]"#,
      charClass(charClass(atom_m(.escaped(.notDecimalDigit))),
                inverted: true))
    parseTest(
      "[[ab][bc]]",
      charClass(charClass("a", "b"), charClass("b", "c")))
    parseTest(
      "[[ab]c[de]]",
      charClass(charClass("a", "b"), "c", charClass("d", "e")))

    parseTest(#"[ab[:space:]\d[:^upper:]cd]"#,
              charClass("a", "b",
                        posixProp_m(.binary(.whitespace)),
                        atom_m(.escaped(.decimalDigit)),
                        posixProp_m(.binary(.uppercase), inverted: true),
                        "c", "d"))

    // Like ICU, we allow POSIX character properties outside of custom character
    // classes. This also appears to be suggested by UTS#18.
    // TODO: We should likely emit a warning.
    parseTest("[:space:]", posixProp(.binary(.whitespace)))
    parseTest("[:script=Greek:]", posixProp(.script(.greek)))

    parseTest("[[[:space:]]]", charClass(charClass(
      posixProp_m(.binary(.whitespace))
    )))

    parseTest("[[:alnum:]]", charClass(posixProp_m(.posix(.alnum))))
    parseTest("[[:blank:]]", charClass(posixProp_m(.posix(.blank))))
    parseTest("[[:graph:]]", charClass(posixProp_m(.posix(.graph))))
    parseTest("[[:print:]]", charClass(posixProp_m(.posix(.print))))
    parseTest("[[:word:]]", charClass(posixProp_m(.posix(.word))))
    parseTest("[[:xdigit:]]", charClass(posixProp_m(.posix(.xdigit))))

    parseTest("[[:ascii:]]", charClass(posixProp_m(.ascii)))
    parseTest("[[:cntrl:]]", charClass(posixProp_m(.generalCategory(.control))))
    parseTest("[[:digit:]]", charClass(posixProp_m(.generalCategory(.decimalNumber))))
    parseTest("[[:lower:]]", charClass(posixProp_m(.binary(.lowercase))))
    parseTest("[[:punct:]]", charClass(posixProp_m(.generalCategory(.punctuation))))
    parseTest("[[:space:]]", charClass(posixProp_m(.binary(.whitespace))))
    parseTest("[[:upper:]]", charClass(posixProp_m(.binary(.uppercase))))

    parseTest("[[:UPPER:]]", charClass(posixProp_m(.binary(.uppercase))))

    parseTest("[[:isALNUM:]]", charClass(posixProp_m(.posix(.alnum))))
    parseTest("[[:AL_NUM:]]", charClass(posixProp_m(.posix(.alnum))))
    parseTest("[[:script=Greek:]]", charClass(posixProp_m(.script(.greek))))

    parseTest("[*]", charClass("*"))
    parseTest("[{0}]", charClass("{", "0", "}"))

    parseTest(#"[\f-\e]"#, charClass(
      range_m(.escaped(.formfeed), .escaped(.escape))))
    parseTest(#"[\a-\b]"#, charClass(
      range_m(.escaped(.alarm), .escaped(.backspace))))
    parseTest(#"[\n-\r]"#, charClass(
      range_m(.escaped(.newline), .escaped(.carriageReturn))))
    parseTest(#"[\t-\t]"#, charClass(
      range_m(.escaped(.tab), .escaped(.tab))))

    parseTest(#"[\cX-\cY\C-A-\C-B\M-\C-A-\M-\C-B\M-A-\M-B]"#, charClass(
      range_m(.keyboardControl("X"), .keyboardControl("Y")),
      range_m(.keyboardControl("A"), .keyboardControl("B")),
      range_m(.keyboardMetaControl("A"), .keyboardMetaControl("B")),
      range_m(.keyboardMeta("A"), .keyboardMeta("B"))
    ), unsupported: true)

    parseTest(
      #"[\N{DOLLAR SIGN}-\N{APOSTROPHE}]"#, charClass(
        range_m(.namedCharacter("DOLLAR SIGN"), .namedCharacter("APOSTROPHE"))),
      unsupported: true)

    parseTest(
      #"[\u{AA}-\u{BB}]"#,
      charClass(range_m(scalar_a("\u{AA}"), scalar_a("\u{BB}")))
    )

    // Not currently supported, we need to figure out what their semantics are.
    parseTest(
      #"[\u{AA BB}-\u{CC}]"#,
      charClass(range_m(scalarSeq_a("\u{AA}", "\u{BB}"), scalar_a("\u{CC}"))),
      unsupported: true
    )
    parseTest(
      #"[\u{CC}-\u{AA BB}]"#,
      charClass(range_m(scalar_a("\u{CC}"), scalarSeq_a("\u{AA}", "\u{BB}"))),
      unsupported: true
    )
    parseTest(
      #"[\u{a b c}]"#,
      charClass(scalarSeq_m("\u{A}", "\u{B}", "\u{C}")),
      unsupported: true
    )

    parseTest(#"(?x)[  a -  b  ]"#, concat(
      changeMatchingOptions(matchingOptions(adding: .extended)),
      charClass(range_m("a", "b"))
    ))

    parseTest(#"(?x)[a - b]"#, concat(
      changeMatchingOptions(matchingOptions(adding: .extended)),
      charClass(range_m("a", "b"))
    ))

    // MARK: Operators

    parseTest(
      #"[a[bc]de&&[^bc]\d]+"#,
      oneOrMore(of: charClass(setOp(
        "a", charClass("b", "c"), "d", "e",
        op: .intersection,
        charClass("b", "c", inverted: true), atom_m(.escaped(.decimalDigit))
      )))
    )

    parseTest(
      "[a&&b]", charClass(setOp("a", op: .intersection, "b"))
    )

    parseTest(
      "[abc--def]",
      charClass(setOp("a", "b", "c", op: .subtraction, "d", "e", "f"))
    )

    // We left-associate for chained operators.
    parseTest(
      "[ab&&b~~cd]",
      charClass(setOp(
        setOp("a", "b", op: .intersection, "b"),
        op: .symmetricDifference,
        "c", "d"
      ))
    )

    // Operators are only valid in custom character classes.
    parseTest(
      "a&&b", concat("a", "&", "&", "b"))
    parseTest(
      "&?", zeroOrOne(of: "&"))
    parseTest(
      "&&?", concat("&", zeroOrOne(of: "&")))
    parseTest(
      "--+", concat("-", oneOrMore(of: "-")))
    parseTest(
      "~~*", concat("~", zeroOrMore(of: "~")))

    parseTest(
      "[ &&  ]",
      charClass(setOp(" ", op: .intersection, " ", " "))
    )
    parseTest("(?x)[ a && b ]", concat(
      changeMatchingOptions(matchingOptions(adding: .extended)),
      charClass(setOp("a", op: .intersection, "b"))
    ))

    // MARK: Quotes

    parseTest(
      #"a\Q .\Eb"#,
      concat("a", quote(" ."), "b"))
    parseTest(
      #"a\Q \Q \\.\Eb"#,
      concat("a", quote(#" \Q \\."#), "b"))

    // This follows the PCRE behavior.
    parseTest(#"\Q\\E"#, quote("\\"))

    // ICU allows quotes to be empty outside of custom character classes.
    parseTest(#"\Q\E"#, quote(""))

    // Quotes may be unterminated.
    parseTest(#"\Qab"#, quote("ab"))
    parseTest(#"\Q"#, quote(""))
    parseTest("\\Qab\\", quote("ab\\"))

    parseTest(#"a" ."b"#, concat("a", quote(" ."), "b"),
              syntax: .experimental)
    parseTest(#"a" .""b""#, concat("a", quote(" ."), quote("b")),
              syntax: .experimental)
    parseTest(#"a" .\"\"b""#, concat("a", quote(" .\"\"b")),
              syntax: .experimental)
    parseTest(#""\"""#, quote("\""), syntax: .experimental)

    parseTest(#"(abc)"#, capture(concat("a", "b", "c")),
              syntax: .experimental, captures: [.cap])

    // Quotes in character classes.
    parseTest(#"[\Q-\E]"#, charClass(quote_m("-")))
    parseTest(#"[\Qa-b[[*+\\E]"#, charClass(quote_m("a-b[[*+\\")))

    parseTest(#"["-"]"#, charClass(quote_m("-")), syntax: .experimental)
    parseTest(#"["a-b[[*+\""]"#, charClass(quote_m(#"a-b[[*+""#)),
              syntax: .experimental)

    parseTest(#"["-"]"#, charClass(range_m("\"", "\"")))

    // MARK: Escapes

    // Not metachars, but we allow their escape as ASCII.
    parseTest(#"\<"#, "<")
    parseTest(#"\ "#, " ")
    parseTest(#"\\"#, "\\")

    // Escaped U+3000 IDEOGRAPHIC SPACE.
    parseTest(#"\\#u{3000}"#, "\u{3000}")

    // Control and meta controls.
    parseTest(#"\c "#, atom(.keyboardControl(" ")), unsupported: true)
    parseTest(#"\c!"#, atom(.keyboardControl("!")), unsupported: true)
    parseTest(#"\c~"#, atom(.keyboardControl("~")), unsupported: true)
    parseTest(#"\C--"#, atom(.keyboardControl("-")), unsupported: true)
    parseTest(#"\M-\C-a"#, atom(.keyboardMetaControl("a")), unsupported: true)
    parseTest(#"\M-\C--"#, atom(.keyboardMetaControl("-")), unsupported: true)
    parseTest(#"\M-a"#, atom(.keyboardMeta("a")), unsupported: true)

    parseTest(#"\O"#, escaped(.trueAnychar), unsupported: true)

    // MARK: Comments

    parseTest(
      #"a(?#comment)b"#,
      concat("a", "b"))
    parseTest(
      #"a(?#. comment)b"#,
      concat("a", "b"))

    // MARK: Interpolation

    // These are literal as there's no closing '}>'
    parseTest("<{", concat("<", "{"))
    parseTest("<{a", concat("<", "{", "a"))
    parseTest("<{a}", concat("<", "{", "a", "}"))
    parseTest("<{<{}", concat("<", "{", "<", "{", "}"))

    // Literal as escaped
    parseTest(#"\<{}>"#, concat("<", "{", "}", ">"))

    // A quantification
    parseTest(#"<{2}"#, exactly(2, of: "<"))

    // MARK: Quantification

    parseTest("a*", zeroOrMore(of: "a"))
    parseTest(" +", oneOrMore(of: " "))

    parseTest(
      #"a{1,2}"#,
      quantRange(1...2, of: "a"))
    parseTest(
      #"a{,2}"#,
      upToN(2, of: "a"))
    parseTest(
      #"a{2,}"#,
      nOrMore(2, of: "a"))
    parseTest(
      #"a{1}"#,
      exactly(1, of: "a"))
    parseTest(
      #"a{1,2}?"#,
      quantRange(1...2, .reluctant, of: "a"))
    parseTest(
      #"a{0}"#,
      exactly(0, of: "a"))
    parseTest(
      #"a{0,0}"#,
      quantRange(0...0, of: "a"))
    parseTest(
      #"a{1,1}"#,
      quantRange(1...1, of: "a"))

    parseTest("x{3, 5}", quantRange(3 ... 5, of: "x"))
    parseTest("x{ 3 , 5  }", quantRange(3 ... 5, of: "x"))
    parseTest("x{3 }", exactly(3, of: "x"))

    // Make sure ranges get treated as literal if invalid.
    parseTest("{", "{")
    parseTest("{,", concat("{", ","))
    parseTest("{}", concat("{", "}"))
    parseTest("{,}", concat("{", ",", "}"))
    parseTest("{,6", concat("{", ",", "6"))
    parseTest("{6", concat("{", "6"))
    parseTest("{6,", concat("{", "6", ","))
    parseTest("{+", oneOrMore(of: "{"))
    parseTest("{6,+", concat("{", "6", oneOrMore(of: ",")))
    parseTest("x{", concat("x", "{"))
    parseTest("x{}", concat("x", "{", "}"))
    parseTest("x{,}", concat("x", "{", ",", "}"))
    parseTest("x{,6", concat("x", "{", ",", "6"))
    parseTest("x{6", concat("x", "{", "6"))
    parseTest("x{6,", concat("x", "{", "6", ","))
    parseTest("x{+", concat("x", oneOrMore(of: "{")))
    parseTest("x{6,+", concat("x", "{", "6", oneOrMore(of: ",")))

    // MARK: Groups

    // Named captures
    parseTest(
      #"a(?<label>b)c"#,
      concat("a", namedCapture("label", "b"), "c"),
      captures: [.named("label")])
    parseTest(
      #"a(?<label1>b)c(?<label2>d)"#,
      concat(
        "a", namedCapture("label1", "b"), "c", namedCapture("label2", "d")),
      captures: [.named("label1"), .named("label2")])
    parseTest(
      #"a(?'label'b)c"#,
      concat("a", namedCapture("label", "b"), "c"),
      captures: [.named("label")])
    parseTest(
      #"a(?P<label>b)c"#,
      concat("a", namedCapture("label", "b"), "c"),
      captures: [.named("label")])
    parseTest(
      #"a(?P<label>b)c"#,
      concat("a", namedCapture("label", "b"), "c"),
      captures: [.named("label")])

    // Balanced captures
    parseTest(#"(?<a-c>)"#, balancedCapture(name: "a", priorName: "c", empty()),
              unsupported: true, captures: [.named("a")])
    parseTest(#"(?<-c>)"#, balancedCapture(name: nil, priorName: "c", empty()),
              unsupported: true, captures: [.cap])
    parseTest(#"(?'a-b'c)"#, balancedCapture(name: "a", priorName: "b", "c"),
              unsupported: true, captures: [.named("a")])

    // Capture resets.
    // FIXME: The captures in each branch should be unified. For now, we don't
    // treat any capture reset as semantically valid.
    parseTest(
      "(?|(a)|(b))",
      nonCaptureReset(alt(capture("a"), capture("b"))),
      unsupported: true, captures: [.opt, .opt]
    )
    parseTest(
      "(?|(?<x>a)|(b))",
      nonCaptureReset(alt(namedCapture("x", "a"), capture("b"))),
      unsupported: true, captures: [.named("x", opt: 1), .opt]
    )
    parseTest(
      "(?|(a)|(?<x>b))",
      nonCaptureReset(alt(capture("a"), namedCapture("x", "b"))),
      unsupported: true, captures: [.opt, .named("x", opt: 1)]
    )
    parseTest(
      "(?|(?<x>a)|(?<x>b))",
      nonCaptureReset(alt(namedCapture("x", "a"), namedCapture("x", "b"))),
      throwsError: .duplicateNamedCapture("x"), unsupported: true,
      captures: [.named("x", opt: 1), .named("x", opt: 1)]
    )

    // TODO: Reject mismatched names?
    parseTest(
      "(?|(?<x>a)|(?<y>b))",
      nonCaptureReset(alt(namedCapture("x", "a"), namedCapture("y", "b"))),
      unsupported: true, captures: [.named("x", opt: 1), .named("y", opt: 1)]
    )

    // Other groups
    parseTest(
      #"a(?:b)c"#,
      concat("a", nonCapture("b"), "c"))
    parseTest(
      #"a(?|b)c"#,
      concat("a", nonCaptureReset("b"), "c"), unsupported: true)
    parseTest(
      #"a(?>b)c"#,
      concat("a", atomicNonCapturing("b"), "c"))
    parseTest(
      "a(*atomic:b)c",
      concat("a", atomicNonCapturing("b"), "c"))

    parseTest("a(?=b)c", concat("a", lookahead("b"), "c"))
    parseTest("a(*pla:b)c", concat("a", lookahead("b"), "c"))
    parseTest("a(*positive_lookahead:b)c", concat("a", lookahead("b"), "c"))

    parseTest("a(?!b)c", concat("a", negativeLookahead("b"), "c"))
    parseTest("a(*nla:b)c", concat("a", negativeLookahead("b"), "c"))
    parseTest("a(*negative_lookahead:b)c",
              concat("a", negativeLookahead("b"), "c"))

    parseTest("a(?<=b)c",
              concat("a", lookbehind("b"), "c"), unsupported: true)
    parseTest("a(*plb:b)c",
              concat("a", lookbehind("b"), "c"), unsupported: true)
    parseTest("a(*positive_lookbehind:b)c",
              concat("a", lookbehind("b"), "c"), unsupported: true)

    parseTest("a(?<!b)c",
              concat("a", negativeLookbehind("b"), "c"), unsupported: true)
    parseTest("a(*nlb:b)c",
              concat("a", negativeLookbehind("b"), "c"), unsupported: true)
    parseTest("a(*negative_lookbehind:b)c",
              concat("a", negativeLookbehind("b"), "c"), unsupported: true)

    parseTest("a(?*b)c",
              concat("a", nonAtomicLookahead("b"), "c"), unsupported: true)
    parseTest("a(*napla:b)c",
              concat("a", nonAtomicLookahead("b"), "c"), unsupported: true)
    parseTest("a(*non_atomic_positive_lookahead:b)c",
              concat("a", nonAtomicLookahead("b"), "c"), unsupported: true)

    parseTest("a(?<*b)c",
              concat("a", nonAtomicLookbehind("b"), "c"), unsupported: true)
    parseTest("a(*naplb:b)c",
              concat("a", nonAtomicLookbehind("b"), "c"), unsupported: true)
    parseTest("a(*non_atomic_positive_lookbehind:b)c",
              concat("a", nonAtomicLookbehind("b"), "c"), unsupported: true)

    parseTest("a(*sr:b)c", concat("a", scriptRun("b"), "c"), unsupported: true)
    parseTest("a(*script_run:b)c",
              concat("a", scriptRun("b"), "c"), unsupported: true)

    parseTest("a(*asr:b)c",
              concat("a", atomicScriptRun("b"), "c"), unsupported: true)
    parseTest("a(*atomic_script_run:b)c",
              concat("a", atomicScriptRun("b"), "c"), unsupported: true)

    // Matching option changing groups.
    parseTest("(?)", changeMatchingOptions(
      matchingOptions()
    ))
    parseTest("(?-)", changeMatchingOptions(
      matchingOptions()
    ))
    parseTest("(?i)", changeMatchingOptions(
      matchingOptions(adding: .caseInsensitive)
    ))
    parseTest("(?m)", changeMatchingOptions(
      matchingOptions(adding: .multiline)
    ))
    parseTest("(?x)", changeMatchingOptions(
      matchingOptions(adding: .extended)
    ))
    parseTest("(?xx)", changeMatchingOptions(
      matchingOptions(adding: .extraExtended)
    ))
    parseTest("(?xxx)", changeMatchingOptions(
      matchingOptions(adding: .extraExtended, .extended)
    ))
    parseTest("(?P)", changeMatchingOptions(
      matchingOptions(adding: .asciiOnlyPOSIXProps)
    ))
    parseTest("(?-i)", changeMatchingOptions(
      matchingOptions(removing: .caseInsensitive)
    ))
    parseTest("(?i-s)", changeMatchingOptions(
      matchingOptions(adding: .caseInsensitive, removing: .singleLine)
    ))
    parseTest("(?i-is)", changeMatchingOptions(
      matchingOptions(adding: .caseInsensitive,
                      removing: .caseInsensitive, .singleLine)
    ))

    parseTest("(?:)", nonCapture(empty()))
    parseTest("(?-:)", changeMatchingOptions(
      matchingOptions(), empty()
    ))
    parseTest("(?i:)", changeMatchingOptions(
      matchingOptions(adding: .caseInsensitive), empty()
    ))
    parseTest("(?-i:)", changeMatchingOptions(
      matchingOptions(removing: .caseInsensitive), empty()
    ))
    parseTest("(?P:)", changeMatchingOptions(
      matchingOptions(adding: .asciiOnlyPOSIXProps), empty()
    ))

    parseTest("(?^)", changeMatchingOptions(
      unsetMatchingOptions()
    ))
    parseTest("(?^:)", changeMatchingOptions(
      unsetMatchingOptions(), empty()
    ))
    parseTest("(?^ims:)", changeMatchingOptions(
      unsetMatchingOptions(adding: .caseInsensitive, .multiline, .singleLine),
      empty()
    ))
    parseTest("(?^J:)", changeMatchingOptions(
      unsetMatchingOptions(adding: .allowDuplicateGroupNames), empty()
    ), unsupported: true)
    parseTest("(?^y{w}:)", changeMatchingOptions(
      unsetMatchingOptions(adding: .textSegmentWordMode), empty()
    ), unsupported: true)

    let allOptions: [AST.MatchingOption.Kind] = [
      .caseInsensitive, .allowDuplicateGroupNames, .multiline, .namedCapturesOnly,
      .singleLine, .reluctantByDefault, .extraExtended, .extended,
      .unicodeWordBoundaries, .asciiOnlyDigit, .asciiOnlyPOSIXProps,
      .asciiOnlySpace, .asciiOnlyWord, .textSegmentGraphemeMode,
      .textSegmentWordMode,
      .graphemeClusterSemantics, .unicodeScalarSemantics,
      .byteSemantics
    ]
    
    parseTest("(?iJmnsUxxxwDPSWy{g}y{w}Xub-iJmnsUxxxwDPSW)", changeMatchingOptions(
      matchingOptions(adding: allOptions, removing: allOptions.dropLast(5))
    ), unsupported: true)
    parseTest("(?iJmnsUxxxwDPSWy{g}y{w}Xub-iJmnsUxxxwDPSW:)", changeMatchingOptions(
      matchingOptions(adding: allOptions, removing: allOptions.dropLast(5)), empty()
    ), unsupported: true)

    parseTest(
      "a(b(?i)c)d", concat(
        "a",
        capture(concat(
          "b",
          changeMatchingOptions(matchingOptions(adding: .caseInsensitive)),
          "c"
        )),
        "d"
      ),
      captures: [.cap]
    )
    parseTest(
      "(a(?i)b(c)d)", capture(concat(
        "a",
        changeMatchingOptions(matchingOptions(adding: .caseInsensitive)),
        "b",
        capture("c"),
        "d"
      )),
      captures: [.cap, .cap]
    )
    parseTest(
      "(a(?i)b(?#hello)c)", capture(concat(
        "a",
        changeMatchingOptions(matchingOptions(adding: .caseInsensitive)),
        "b",
        "c"
      )),
      captures: [.cap]
    )

    parseTest("ab(?i)c|def|gh", alt(
      concat(
        "a",
        "b",
        changeMatchingOptions(matchingOptions(adding: .caseInsensitive)),
        "c"
      ),
      concat("d", "e", "f"),
      concat("g", "h")
    ))

    parseTest("(a|b(?i)c|d)", capture(alt(
      "a",
      concat(
        "b",
        changeMatchingOptions(matchingOptions(adding: .caseInsensitive)),
        "c"
      ),
      "d"
    )), captures: [.cap])

    parseTest("(?n)(?^:())(?<x>)()", concat(
      changeMatchingOptions(matchingOptions(adding: .namedCapturesOnly)),
      changeMatchingOptions(unsetMatchingOptions(), capture(empty())),
      namedCapture("x", empty()),
      nonCapture(empty())
    ), captures: [.cap, .named("x")])

    // MARK: References

    // \1 ... \9 are always backreferences.
    for i in 1 ... 9 {
      parseTest("\\\(i)", backreference(ref(i)), throwsError: .invalidReference(i))
      parseTest(
        "()()()()()()()()()\\\(i)",
        concat(Array(repeating: capture(empty()), count: 9)
               + [backreference(ref(i))]),
        captures: .caps(count: 9)
      )
    }

    parseTest(#"\10"#, backreference(ref(10)), throwsError: .invalidReference(10))
    parseTest(#"\18"#, backreference(ref(18)), throwsError: .invalidReference(18))
    parseTest(#"\7777"#, backreference(ref(7777)), throwsError: .invalidReference(7777))
    parseTest(#"\91"#, backreference(ref(91)), throwsError: .invalidReference(91))

    parseTest(
      #"()()()()()()()()()()\10"#,
      concat(Array(repeating: capture(empty()), count: 10)
             + [backreference(ref(10))]),
      captures: .caps(count: 10)
    )
    parseTest(
      #"()()()()()()()()()\10()"#,
      concat(Array(repeating: capture(empty()), count: 9)
             + [backreference(ref(10)), capture(empty())]),
      captures: .caps(count: 10)
    )
    parseTest(#"()()\10"#, concat(
      capture(empty()), capture(empty()), backreference(ref(10))),
              throwsError: .invalidReference(10), captures: [.cap, .cap]
    )

    // A capture of three empty captures.
    let fourCaptures = capture(
      concat(capture(empty()), capture(empty()), capture(empty()))
    )
    parseTest(
      // There are 9 capture groups in total here.
      #"((()()())(()()()))\10"#, concat(capture(concat(
        fourCaptures, fourCaptures)), backreference(ref(10))),
      throwsError: .invalidReference(10), captures: .caps(count: 9)
    )
    parseTest(
      // There are 10 capture groups in total here.
      #"((()()())()(()()()))\10"#,
      concat(capture(concat(fourCaptures, capture(empty()), fourCaptures)),
             backreference(ref(10))),
      captures: .caps(count: 10)
    )
    parseTest(
      // There are 10 capture groups in total here.
      #"((((((((((\10))))))))))"#,
      capture(capture(capture(capture(capture(capture(capture(capture(capture(
        capture(backreference(ref(10)))))))))))),
      captures: .caps(count: 10)
    )

    // The cases from http://pcre.org/current/doc/html/pcre2pattern.html#digitsafterbackslash:
    parseTest(#"\040"#, scalar(" "))
    parseTest(
      String(repeating: "()", count: 40) + #"\040"#,
      concat(Array(repeating: capture(empty()), count: 40) + [scalar(" ")]),
      captures: .caps(count: 40)
    )
    parseTest(#"\40"#, backreference(ref(40)), throwsError: .invalidReference(40))
    parseTest(
      String(repeating: "()", count: 40) + #"\40"#,
      concat(Array(repeating: capture(empty()), count: 40)
             + [backreference(ref(40))]),
      captures: .caps(count: 40)
    )

    parseTest(#"\7"#, backreference(ref(7)), throwsError: .invalidReference(7))

    parseTest(#"\11"#, backreference(ref(11)), throwsError: .invalidReference(11))
    parseTest(
      String(repeating: "()", count: 12) + #"\11"#,
      concat(Array(repeating: capture(empty()), count: 12)
             + [backreference(ref(11))]),
      captures: .caps(count: 12)
    )
    parseTest(#"\011"#, scalar("\u{9}"))
    parseTest(
      String(repeating: "()", count: 11) + #"\011"#,
      concat(Array(repeating: capture(empty()), count: 11) + [scalar("\u{9}")]),
      captures: .caps(count: 11)
    )

    parseTest(#"\0113"#, scalar("\u{4B}"))
    parseTest(#"\113"#, backreference(ref(113)), throwsError: .invalidReference(113))
    parseTest(#"\377"#, backreference(ref(377)), throwsError: .invalidReference(377))
    parseTest(#"\81"#, backreference(ref(81)), throwsError: .invalidReference(81))

    parseTest(#"\g1"#, backreference(ref(1)), throwsError: .invalidReference(1))
    parseTest(#"\g001"#, backreference(ref(1)), throwsError: .invalidReference(1))
    parseTest(#"\g52"#, backreference(ref(52)), throwsError: .invalidReference(52))
    parseTest(#"\g-01"#, backreference(ref(minus: 1)), unsupported: true)
    parseTest(#"\g+30"#, backreference(ref(plus: 30)), unsupported: true)

    parseTest(#"\g{1}"#, backreference(ref(1)), throwsError: .invalidReference(1))
    parseTest(#"\g{001}"#, backreference(ref(1)), throwsError: .invalidReference(1))
    parseTest(#"\g{52}"#, backreference(ref(52)), throwsError: .invalidReference(52))
    parseTest(#"\g{-01}"#, backreference(ref(minus: 1)), unsupported: true)
    parseTest(#"\g{+30}"#, backreference(ref(plus: 30)), unsupported: true)
    parseTest(#"\k<+4>"#, backreference(ref(plus: 4)), unsupported: true)
    parseTest(#"\k<2>"#, backreference(ref(2)), throwsError: .invalidReference(2))
    parseTest(#"\k'-3'"#, backreference(ref(minus: 3)), unsupported: true)
    parseTest(#"\k'1'"#, backreference(ref(1)), throwsError: .invalidReference(1))

    parseTest(
      #"(?<a>)\k<a>"#, concat(
        namedCapture("a", empty()), backreference(.named("a"))
      ), captures: [.named("a")]
    )
    parseTest(
      #"(?<a>)\k{a}"#, concat(
        namedCapture("a", empty()), backreference(.named("a"))
      ), captures: [.named("a")]
    )
    parseTest(
      #"(?<a>)\g{a}"#, concat(
        namedCapture("a", empty()), backreference(.named("a"))
      ), captures: [.named("a")]
    )
    parseTest(
      #"(?<a>)(?P=a)"#, concat(
        namedCapture("a", empty()), backreference(.named("a"))
      ), captures: [.named("a")]
    )

    parseTest(#"\k{a0}"#, backreference(.named("a0")), throwsError: .invalidNamedReference("a0"))
    parseTest(#"\k<bc>"#, backreference(.named("bc")), throwsError: .invalidNamedReference("bc"))
    parseTest(#"\g{abc}"#, backreference(.named("abc")), throwsError: .invalidNamedReference("abc"))
    parseTest(#"(?P=abc)"#, backreference(.named("abc")), throwsError: .invalidNamedReference("abc"))

    // Oniguruma recursion levels.
    parseTest(#"\k<bc-0>"#, backreference(.named("bc"), recursionLevel: 0),
              throwsError: .invalidNamedReference("bc"), unsupported: true)
    parseTest(#"\k<a+0>"#, backreference(.named("a"), recursionLevel: 0),
              throwsError: .invalidNamedReference("a"), unsupported: true)
    parseTest(#"\k<1+1>"#, backreference(ref(1), recursionLevel: 1),
              throwsError: .invalidReference(1), unsupported: true)
    parseTest(#"\k<3-8>"#, backreference(ref(3), recursionLevel: -8),
              throwsError: .invalidReference(3), unsupported: true)
    parseTest(#"\k'-3-8'"#, backreference(ref(minus: 3), recursionLevel: -8),
              unsupported: true)
    parseTest(#"\k'bc-8'"#, backreference(.named("bc"), recursionLevel: -8),
              throwsError: .invalidNamedReference("bc"), unsupported: true)
    parseTest(#"\k'+3-8'"#, backreference(ref(plus: 3), recursionLevel: -8),
              unsupported: true)
    parseTest(#"\k'+3+8'"#, backreference(ref(plus: 3), recursionLevel: 8),
              unsupported: true)

    parseTest(#"(?R)"#, subpattern(ref(0)), unsupported: true)
    parseTest(#"(?0)"#, subpattern(ref(0)), unsupported: true)
    parseTest(#"(?1)"#, subpattern(ref(1)), unsupported: true)
    parseTest(#"(?+12)"#, subpattern(ref(plus: 12)), unsupported: true)
    parseTest(#"(?-2)"#, subpattern(ref(minus: 2)), unsupported: true)
    parseTest(#"(?&hello)"#, subpattern(.named("hello")), unsupported: true)
    parseTest(#"(?P>P)"#, subpattern(.named("P")), unsupported: true)

    parseTest(#"[(?R)]"#, charClass("(", "?", "R", ")"))
    parseTest(#"[(?&a)]"#, charClass("(", "?", "&", "a", ")"))
    parseTest(#"[(?1)]"#, charClass("(", "?", "1", ")"))

    parseTest(#"\g<1>"#, subpattern(ref(1)), unsupported: true)
    parseTest(#"\g<001>"#, subpattern(ref(1)), unsupported: true)
    parseTest(#"\g'52'"#, subpattern(ref(52)), unsupported: true)
    parseTest(#"\g'-01'"#, subpattern(ref(minus: 1)), unsupported: true)
    parseTest(#"\g'+30'"#, subpattern(ref(plus: 30)), unsupported: true)
    parseTest(#"\g'abc'"#, subpattern(.named("abc")), unsupported: true)

    // These are valid references.
    parseTest(#"()\1"#, concat(
      capture(empty()), backreference(ref(1))
    ), captures: [.cap])
    parseTest(#"\1()"#, concat(
      backreference(ref(1)), capture(empty())
    ), captures: [.cap])
    parseTest(#"()()\2"#, concat(
      capture(empty()), capture(empty()), backreference(ref(2))
    ), captures: [.cap, .cap])
    parseTest(#"()\2()"#, concat(
      capture(empty()), backreference(ref(2)), capture(empty())
    ), captures: [.cap, .cap])

    // MARK: Character names.

    parseTest(#"\N{abc}"#, atom(.namedCharacter("abc")))
    parseTest(#"[\N{abc}]"#, charClass(atom_m(.namedCharacter("abc"))))
    parseTest(#"\N{abc}+"#, oneOrMore(of: atom(.namedCharacter("abc"))))
    parseTest(
      #"\N {2}"#,
      concat(atom(.escaped(.notNewline)), exactly(2, of: " ")), unsupported: true
    )

    parseTest(#"\N{AA}"#, atom(.namedCharacter("AA")))
    parseTest(#"\N{U+AA}"#, scalar("\u{AA}"))
    parseTest(#"\N{U+0123A}"#, scalar("\u{123A}"))
    parseTest(#"\N{U+0000FFFF}"#, scalar("\u{FFFF}"))

    // MARK: Character properties.

    parseTest(#"\p{L}"#,
              prop(.generalCategory(.letter)))
    parseTest(#"\p{gc=L}"#,
              prop(.generalCategory(.letter)))
    parseTest(#"\p{Lu}"#,
              prop(.generalCategory(.uppercaseLetter)))
    parseTest(#"\P{Cc}"#,
              prop(.generalCategory(.control), inverted: true))
    parseTest(#"\P{Z}"#,
              prop(.generalCategory(.separator), inverted: true))

    parseTest(#"[\p{C}]"#, charClass(prop_m(.generalCategory(.other))))
    parseTest(
      #"\p{C}+"#,
      oneOrMore(of: prop(.generalCategory(.other))))

    // L& defined by PCRE.
    parseTest(#"\p{L&}"#, prop(.generalCategory(.casedLetter)))

    // UAX44-LM3 means all of the below are equivalent.
    let lowercaseLetter = prop(.generalCategory(.lowercaseLetter))
    parseTest(#"\p{ll}"#, lowercaseLetter)
    parseTest(#"\p{gc=ll}"#, lowercaseLetter)
    parseTest(#"\p{General_Category=Ll}"#, lowercaseLetter)
    parseTest(#"\p{General-Category=isLl}"#, lowercaseLetter)
    parseTest(#"\p{  __l_ l  _ }"#, lowercaseLetter)
    parseTest(#"\p{ g_ c =-  __l_ l  _ }"#, lowercaseLetter)
    parseTest(#"\p{ general ca-tegory =  __l_ l  _ }"#, lowercaseLetter)
    parseTest(#"\p{- general category =  is__l_ l  _ }"#, lowercaseLetter)
    parseTest(#"\p{ general category -=  IS__l_ l  _ }"#, lowercaseLetter)

    parseTest(#"\p{Any}"#, prop(.any))
    parseTest(#"\p{Assigned}"#, prop(.assigned))
    parseTest(#"\p{ascii}"#, prop(.ascii))
    parseTest(#"\p{isAny}"#, prop(.any))

    parseTest(#"\p{sc=grek}"#, prop(.script(.greek)))
    parseTest(#"\p{sc=isGreek}"#, prop(.script(.greek)))
    parseTest(#"\p{Greek}"#, prop(.scriptExtension(.greek)))
    parseTest(#"\p{isGreek}"#, prop(.scriptExtension(.greek)))
    parseTest(#"\P{Script=Latn}"#, prop(.script(.latin), inverted: true))
    parseTest(#"\p{script=zzzz}"#, prop(.script(.unknown)))
    parseTest(#"\p{ISscript=iszzzz}"#, prop(.script(.unknown)))
    parseTest(#"\p{scx=bamum}"#, prop(.scriptExtension(.bamum)))
    parseTest(#"\p{ISBAMUM}"#, prop(.scriptExtension(.bamum)))

    parseTest(#"\p{alpha}"#, prop(.binary(.alphabetic)))
    parseTest(#"\p{DEP}"#, prop(.binary(.deprecated)))
    parseTest(#"\P{DEP}"#, prop(.binary(.deprecated), inverted: true))
    parseTest(#"\p{alphabetic=True}"#, prop(.binary(.alphabetic)))
    parseTest(#"\p{emoji=t}"#, prop(.binary(.emoji)))
    parseTest(#"\p{Alpha=no}"#, prop(.binary(.alphabetic, value: false)))
    parseTest(#"\P{Alpha=no}"#, prop(.binary(.alphabetic, value: false), inverted: true))
    parseTest(#"\p{isAlphabetic}"#, prop(.binary(.alphabetic)))
    parseTest(#"\p{isAlpha=isFalse}"#, prop(.binary(.alphabetic, value: false)))

    parseTest(#"\p{In_Runic}"#, prop(.block(.runic)), unsupported: true)

    parseTest(#"\p{Hebrew}"#, prop(.scriptExtension(.hebrew)))
    parseTest(#"\p{Is_Hebrew}"#, prop(.scriptExtension(.hebrew)))
    parseTest(#"\p{In_Hebrew}"#, prop(.block(.hebrew)), unsupported: true)
    parseTest(#"\p{Blk=Is_Hebrew}"#, prop(.block(.hebrew)), unsupported: true)

    // These are the shorthand properties with an "in" prefix we currently
    // recognize. Make sure they don't clash with block properties.
    parseTest(#"\p{initialpunctuation}"#, prop(.generalCategory(.initialPunctuation)))
    parseTest(#"\p{inscriptionalpahlavi}"#, prop(.scriptExtension(.inscriptionalPahlavi)))
    parseTest(#"\p{inscriptionalparthian}"#, prop(.scriptExtension(.inscriptionalParthian)))
    parseTest(#"\p{inherited}"#, prop(.scriptExtension(.inherited)))

    // Make sure these are round-trippable.
    for s in Unicode.Script.allCases {
      parseTest(#"\p{\#(s.rawValue)}"#, prop(.scriptExtension(s)))
      parseTest(#"\p{is\#(s.rawValue)}"#, prop(.scriptExtension(s)))
    }
    for g in Unicode.ExtendedGeneralCategory.allCases {
      parseTest(#"\p{\#(g.rawValue)}"#, prop(.generalCategory(g)))
      parseTest(#"\p{is\#(g.rawValue)}"#, prop(.generalCategory(g)))
    }
    for p in Unicode.POSIXProperty.allCases {
      parseTest(#"\p{\#(p.rawValue)}"#, prop(.posix(p)))
      parseTest(#"\p{is\#(p.rawValue)}"#, prop(.posix(p)))
    }
    for b in Unicode.BinaryProperty.allCases {
      // Some of these are unsupported, so don't check for errors.
      parseTest(#"\p{\#(b.rawValue)}"#, prop(.binary(b, value: true)), uncheckedErrors: true)
      parseTest(#"\p{is\#(b.rawValue)}"#, prop(.binary(b, value: true)), uncheckedErrors: true)
    }

    for j in AST.Atom.CharacterProperty.JavaSpecial.allCases {
      parseTest(#"\p{\#(j.rawValue)}"#, prop(.javaSpecial(j)), unsupported: true)
    }

    // Try prefixing each block property with "in" to make sure we don't stomp
    // on any other property shorthands.
    for b in Unicode.Block.allCases {
      parseTest(#"\p{in\#(b.rawValue)}"#, prop(.block(b)), unsupported: true)
    }

    parseTest(#"\p{ASCII}"#, prop(.ascii))
    parseTest(#"\p{isASCII}"#, prop(.ascii))
    parseTest(#"\p{inASCII}"#, prop(.block(.basicLatin)), unsupported: true)

    parseTest(#"\p{inBasicLatin}"#, prop(.block(.basicLatin)), unsupported: true)
    parseTest(#"\p{In_Basic_Latin}"#, prop(.block(.basicLatin)), unsupported: true)
    parseTest(#"\p{Blk=Basic_Latin}"#, prop(.block(.basicLatin)), unsupported: true)
    parseTest(#"\p{Blk=Is_Basic_Latin}"#, prop(.block(.basicLatin)), unsupported: true)

    parseTest(#"\p{isAny}"#, prop(.any))
    parseTest(#"\p{isAssigned}"#, prop(.assigned))

    parseTest(#"\p{Xan}"#, prop(.pcreSpecial(.alphanumeric)), unsupported: true)
    parseTest(#"\p{Xps}"#, prop(.pcreSpecial(.posixSpace)), unsupported: true)
    parseTest(#"\p{Xsp}"#, prop(.pcreSpecial(.perlSpace)), unsupported: true)
    parseTest(#"\p{Xuc}"#, prop(.pcreSpecial(.universallyNamed)), unsupported: true)
    parseTest(#"\p{Xwd}"#, prop(.pcreSpecial(.perlWord)), unsupported: true)

    parseTest(#"\p{alnum}"#, prop(.posix(.alnum)))
    parseTest(#"\p{is_alnum}"#, prop(.posix(.alnum)))
    parseTest(#"\p{blank}"#, prop(.posix(.blank)))
    parseTest(#"\p{graph}"#, prop(.posix(.graph)))
    parseTest(#"\p{print}"#, prop(.posix(.print)))
    parseTest(#"\p{word}"#,  prop(.posix(.word)))
    parseTest(#"\p{xdigit}"#, prop(.posix(.xdigit)))

    parseTest(#"\p{name=A}"#, prop(.named("A")))
    parseTest(#"\p{Name=B}"#, prop(.named("B")))
    parseTest(#"\p{isName=C}"#, prop(.named("C")))
    parseTest(#"\p{na=D}"#, prop(.named("D")))
    parseTest(#"\p{NA=E}"#, prop(.named("E")))
    parseTest(#"\p{na=isI}"#, prop(.named("isI")))

    // MARK: Conditionals

    parseTest(#"(?(1))"#, conditional(
      .groupMatched(ref(1)), trueBranch: empty(), falseBranch: empty()), unsupported: true)
    parseTest(#"(?(1)|)"#, conditional(
      .groupMatched(ref(1)), trueBranch: empty(), falseBranch: empty()), unsupported: true)
    parseTest(#"(?(1)a)"#, conditional(
      .groupMatched(ref(1)), trueBranch: "a", falseBranch: empty()), unsupported: true)
    parseTest(#"(?(1)a|)"#, conditional(
      .groupMatched(ref(1)), trueBranch: "a", falseBranch: empty()), unsupported: true)
    parseTest(#"(?(1)|b)"#, conditional(
      .groupMatched(ref(1)), trueBranch: empty(), falseBranch: "b"), unsupported: true)
    parseTest(#"(?(1)a|b)"#, conditional(
      .groupMatched(ref(1)), trueBranch: "a", falseBranch: "b"), unsupported: true)

    parseTest(#"(?(1)(a|b|c)|d)"#, conditional(
      .groupMatched(ref(1)),
      trueBranch: capture(alt("a", "b", "c")),
      falseBranch: "d"
    ), unsupported: true, captures: [.opt])

    parseTest(#"(?(+3))"#, conditional(
      .groupMatched(ref(plus: 3)), trueBranch: empty(), falseBranch: empty()), unsupported: true)
    parseTest(#"(?(-21))"#, conditional(
      .groupMatched(ref(minus: 21)), trueBranch: empty(), falseBranch: empty()), unsupported: true)

    // Oniguruma recursion levels.
    parseTest(#"(?(1+1))"#, conditional(
      .groupMatched(ref(1, recursionLevel: 1)),
      trueBranch: empty(), falseBranch: empty()), unsupported: true
    )
    parseTest(#"(?(-1+1))"#, conditional(
      .groupMatched(ref(minus: 1, recursionLevel: 1)),
      trueBranch: empty(), falseBranch: empty()), unsupported: true
    )
    parseTest(#"(?(1-3))"#, conditional(
      .groupMatched(ref(1, recursionLevel: -3)),
      trueBranch: empty(), falseBranch: empty()), unsupported: true
    )
    parseTest(#"(?(+1-3))"#, conditional(
      .groupMatched(ref(plus: 1, recursionLevel: -3)),
      trueBranch: empty(), falseBranch: empty()), unsupported: true
    )
    parseTest(
      #"(?<a>)(?(a+5))"#,
      concat(namedCapture("a", empty()), conditional(
        .groupMatched(ref("a", recursionLevel: 5)),
        trueBranch: empty(), falseBranch: empty()
      )),
      unsupported: true, captures: [.named("a")]
    )
    parseTest(
      #"(?<a1>)(?(a1-5))"#,
      concat(namedCapture("a1", empty()), conditional(
        .groupMatched(ref("a1", recursionLevel: -5)),
        trueBranch: empty(), falseBranch: empty()
      )),
      unsupported: true, captures: [.named("a1")]
    )

    parseTest(#"(?(1))?"#, zeroOrOne(of: conditional(
      .groupMatched(ref(1)), trueBranch: empty(), falseBranch: empty())), unsupported: true)

    parseTest(#"(?(R)a|b)"#, conditional(
      .recursionCheck, trueBranch: "a", falseBranch: "b"), unsupported: true)
    parseTest(#"(?(R1))"#, conditional(
      .groupRecursionCheck(ref(1)), trueBranch: empty(), falseBranch: empty()), unsupported: true)
    parseTest(#"(?(R&abc)a|b)"#, conditional(
      .groupRecursionCheck(ref("abc")), trueBranch: "a", falseBranch: "b"), unsupported: true)

    parseTest(#"(?(<abc>)a|b)"#, conditional(
      .groupMatched(ref("abc")), trueBranch: "a", falseBranch: "b"), unsupported: true)
    parseTest(#"(?('abc')a|b)"#, conditional(
      .groupMatched(ref("abc")), trueBranch: "a", falseBranch: "b"), unsupported: true)

    parseTest(#"(?(abc)a|b)"#, conditional(
      groupCondition(.capture, concat("a", "b", "c")),
      trueBranch: "a", falseBranch: "b"
    ), unsupported: true, captures: [.cap])

    parseTest(#"(?(?:abc)a|b)"#, conditional(
      groupCondition(.nonCapture, concat("a", "b", "c")),
      trueBranch: "a", falseBranch: "b"
    ), unsupported: true)

    parseTest(#"(?(?=abc)a|b)"#, conditional(
      groupCondition(.lookahead, concat("a", "b", "c")),
      trueBranch: "a", falseBranch: "b"
    ), unsupported: true)
    parseTest(#"(?(?!abc)a|b)"#, conditional(
      groupCondition(.negativeLookahead, concat("a", "b", "c")),
      trueBranch: "a", falseBranch: "b"
    ), unsupported: true)
    parseTest(#"(?(?<=abc)a|b)"#, conditional(
      groupCondition(.lookbehind, concat("a", "b", "c")),
      trueBranch: "a", falseBranch: "b"
    ), unsupported: true)
    parseTest(#"(?(?<!abc)a|b)"#, conditional(
      groupCondition(.negativeLookbehind, concat("a", "b", "c")),
      trueBranch: "a", falseBranch: "b"
    ), unsupported: true)

    parseTest(#"(?((a)?(b))(a)+|b)"#, conditional(
      groupCondition(.capture, concat(
        zeroOrOne(of: capture("a")), capture("b")
      )),
      trueBranch: oneOrMore(of: capture("a")),
      falseBranch: "b"
    ), unsupported: true, captures: [.cap, .opt, .cap, .opt])

    parseTest(#"(?(?:(a)?(b))(a)+|b)"#, conditional(
      groupCondition(.nonCapture, concat(
        zeroOrOne(of: capture("a")), capture("b")
      )),
      trueBranch: oneOrMore(of: capture("a")),
      falseBranch: "b"
    ), unsupported: true, captures: [.opt, .cap, .opt])

    parseTest(#"(?<xxx>y)(?(xxx)a|b)"#, concat(
      namedCapture("xxx", "y"),
      conditional(.groupMatched(ref("xxx")), trueBranch: "a", falseBranch: "b")
    ), unsupported: true, captures: [.named("xxx")])

    parseTest(#"(?(1)(?(2)(?(3)))|a)"#, conditional(
      .groupMatched(ref(1)),
      trueBranch: conditional(.groupMatched(ref(2)),
                              trueBranch: conditional(.groupMatched(ref(3)),
                                                      trueBranch: empty(),
                                                      falseBranch: empty()),
                              falseBranch: empty()),
      falseBranch: "a"), unsupported: true)

    parseTest(#"(?(DEFINE))"#, conditional(
      .defineGroup, trueBranch: empty(), falseBranch: empty()), unsupported: true)

    parseTest(#"(?(VERSION>=3.1))"#, conditional(
      pcreVersionCheck(.greaterThanOrEqual, 3, 1),
      trueBranch: empty(), falseBranch: empty()), unsupported: true
    )
    parseTest(#"(?(VERSION=0.1))"#, conditional(
      pcreVersionCheck(.equal, 0, 1),
      trueBranch: empty(), falseBranch: empty()), unsupported: true
    )

    // MARK: Callouts

    // PCRE callouts

    parseTest(#"(?C)"#, pcreCallout(number: 0), unsupported: true)
    parseTest(#"(?C0)"#, pcreCallout(number: 0), unsupported: true)
    parseTest(#"(?C20)"#, pcreCallout(number: 20), unsupported: true)
    parseTest("(?C{abc})", pcreCallout(string: "abc"), unsupported: true)

    for delim in ["`", "'", "\"", "^", "%", "#", "$"] {
      parseTest("(?C\(delim)hello\(delim))", pcreCallout(string: "hello"),
                unsupported: true)
    }

    // Oniguruma named callouts

    parseTest("(*X)", onigurumaNamedCallout("X"), unsupported: true)
    parseTest("(*foo[t])", onigurumaNamedCallout("foo", tag: "t"), unsupported: true)
    parseTest("(*foo[a0]{b})", onigurumaNamedCallout("foo", tag: "a0", args: "b"), unsupported: true)
    parseTest("(*foo{b})", onigurumaNamedCallout("foo", args: "b"), unsupported: true)
    parseTest("(*foo[a]{a,b,c})", onigurumaNamedCallout("foo", tag: "a", args: "a", "b", "c"), unsupported: true)
    parseTest("(*foo{a,b,c})", onigurumaNamedCallout("foo", args: "a", "b", "c"), unsupported: true)
    parseTest("(*foo{%%$,!!,>>})", onigurumaNamedCallout("foo", args: "%%$", "!!", ">>"), unsupported: true)
    parseTest("(*foo{a, b, c})", onigurumaNamedCallout("foo", args: "a", " b", " c"), unsupported: true)

    // Oniguruma 'of contents' callouts

    parseTest("(?{x})", onigurumaCalloutOfContents("x"), unsupported: true)
    parseTest("(?{{{x}}y}}})", onigurumaCalloutOfContents("x}}y"), unsupported: true)
    parseTest("(?{{{x}}})", onigurumaCalloutOfContents("x"), unsupported: true)
    parseTest("(?{x}[tag])", onigurumaCalloutOfContents("x", tag: "tag"), unsupported: true)
    parseTest("(?{x}[tag]<)", onigurumaCalloutOfContents("x", tag: "tag", direction: .inRetraction), unsupported: true)
    parseTest("(?{x}X)", onigurumaCalloutOfContents("x", direction: .both), unsupported: true)
    parseTest("(?{x}>)", onigurumaCalloutOfContents("x"), unsupported: true)
    parseTest("(?{\\x})", onigurumaCalloutOfContents("\\x"), unsupported: true)
    parseTest("(?{\\})", onigurumaCalloutOfContents("\\"), unsupported: true)

    // MARK: Backtracking directives

    parseTest("(*ACCEPT)?", zeroOrOne(of: backtrackingDirective(.accept)), unsupported: true)
    parseTest(
      "(*ACCEPT:a)??",
      zeroOrOne(.reluctant, of: backtrackingDirective(.accept, name: "a")),
      unsupported: true
    )
    parseTest("(*:a)", backtrackingDirective(.mark, name: "a"), unsupported: true)
    parseTest("(*MARK:a)", backtrackingDirective(.mark, name: "a"), unsupported: true)
    parseTest("(*F)", backtrackingDirective(.fail), unsupported: true)
    parseTest("(*COMMIT)", backtrackingDirective(.commit), unsupported: true)
    parseTest("(*SKIP)", backtrackingDirective(.skip), unsupported: true)
    parseTest("(*SKIP:SKIP)", backtrackingDirective(.skip, name: "SKIP"), unsupported: true)
    parseTest("(*PRUNE)", backtrackingDirective(.prune), unsupported: true)
    parseTest("(*THEN)", backtrackingDirective(.then), unsupported: true)

    // MARK: Oniguruma absent functions

    parseTest("(?~)", absentRepeater(empty()), unsupported: true)
    parseTest("(?~abc)", absentRepeater(concat("a", "b", "c")), unsupported: true)
    parseTest("(?~a+)", absentRepeater(oneOrMore(of: "a")), unsupported: true)
    parseTest("(?~~)", absentRepeater("~"), unsupported: true)
    parseTest("(?~a|b|c)", absentRepeater(alt("a", "b", "c")), unsupported: true)
    parseTest("(?~(a))", absentRepeater(capture("a")), unsupported: true, captures: [])
    parseTest("(?~)*", zeroOrMore(of: absentRepeater(empty())), unsupported: true)

    parseTest("(?~|abc)", absentStopper(concat("a", "b", "c")), unsupported: true)
    parseTest("(?~|a+)", absentStopper(oneOrMore(of: "a")), unsupported: true)
    parseTest("(?~|~)", absentStopper("~"), unsupported: true)
    parseTest("(?~|(a))", absentStopper(capture("a")), unsupported: true, captures: [])
    parseTest("(?~|a){2}", exactly(2, of: absentStopper("a")), unsupported: true)

    parseTest("(?~|a|b)", absentExpression("a", "b"), unsupported: true)
    parseTest("(?~|~|~)", absentExpression("~", "~"), unsupported: true)
    parseTest("(?~|(a)|(?:b))", absentExpression(capture("a"), nonCapture("b")),
              unsupported: true, captures: [])
    parseTest("(?~|(a)|(?:(b)|c))", absentExpression(
      capture("a"), nonCapture(alt(capture("b"), "c"))
    ), unsupported: true, captures: [.opt])
    parseTest("(?~|a|b)?", zeroOrOne(of: absentExpression("a", "b")), unsupported: true)

    parseTest("(?~|)", absentRangeClear(), unsupported: true)

    // TODO: It's not really clear what this means, but Oniguruma parses it...
    // Maybe we should diagnose it?
    parseTest("(?~|)+", oneOrMore(of: absentRangeClear()), unsupported: true)

    // MARK: Global matching options

    parseTest("(*CR)(*UTF)(*LIMIT_DEPTH=3)", ast(
      empty(), opts: .newlineMatching(.carriageReturnOnly), .utfMode,
      .limitDepth(.init(3, at: .fake))
    ), unsupported: true)

    parseTest(
      "(*BSR_UNICODE)3", ast("3", opts: .newlineSequenceMatching(.anyUnicode)),
      unsupported: true)
    parseTest(
      "(*BSR_ANYCRLF)", ast(
        empty(), opts: .newlineSequenceMatching(.anyCarriageReturnOrLinefeed)),
      unsupported: true)

    // TODO: Diagnose on multiple line matching modes?
    parseTest(
      "(*CR)(*LF)(*CRLF)(*ANYCRLF)(*ANY)(*NUL)",
      ast(empty(), opts: [
        .carriageReturnOnly, .linefeedOnly, .carriageAndLinefeedOnly,
        .anyCarriageReturnOrLinefeed, .anyUnicode, .nulCharacter
      ].map { .newlineMatching($0) }), unsupported: true)

    parseTest(
      """
      (*LIMIT_DEPTH=3)(*LIMIT_HEAP=1)(*LIMIT_MATCH=2)(*NOTEMPTY)\
      (*NOTEMPTY_ATSTART)(*NO_AUTO_POSSESS)(*NO_DOTSTAR_ANCHOR)(*NO_JIT)\
      (*NO_START_OPT)(*UTF)(*UCP)a
      """,
      ast("a", opts:
        .limitDepth(.init(3, at: .fake)), .limitHeap(.init(1, at: .fake)),
        .limitMatch(.init(2, at: .fake)), .notEmpty, .notEmptyAtStart,
        .noAutoPossess, .noDotStarAnchor, .noJIT, .noStartOpt, .utfMode,
        .unicodeProperties
      ), unsupported: true
    )

    parseTest("[(*CR)]", charClass("(", "*", "C", "R", ")"))

    // MARK: Trivia

    parseTest("[(?#abc)]", charClass("(", "?", "#", "a", "b", "c", ")"))
    parseTest("# abc", concat("#", " ", "a", "b", "c"))

    parseTest("(?#)", empty())
    parseTest("/**/", empty(), syntax: .experimental)

    // MARK: Matching option changing

    parseTest(
      "(?x) # hello",
      changeMatchingOptions(matchingOptions(adding: .extended))
    )
    parseTest(
      "(?xx) # hello",
      changeMatchingOptions(matchingOptions(adding: .extraExtended))
    )
    parseTest("(?x) \\# abc", concat(
      changeMatchingOptions(matchingOptions(adding: .extended)),
      "#", "a", "b", "c"
    ))
    parseTest("(?xx) \\ ", concat(
      changeMatchingOptions(matchingOptions(adding: .extraExtended)), " "
    ))

    parseTest(
      "(?x) a (?^) b", concat(
        changeMatchingOptions(matchingOptions(adding: .extended)),
        "a",
        changeMatchingOptions(unsetMatchingOptions()),
        " ", "b"
      )
    )
    parseTest(
      "(?x) a (?^: b)", concat(
        changeMatchingOptions(matchingOptions(adding: .extended)),
        "a",
        changeMatchingOptions(unsetMatchingOptions(), concat(" ", "b"))
      )
    )

    parseTest("[ # abc]", charClass(" ", "#", " ", "a", "b", "c"))
    parseTest("[#]", charClass("#"))

    parseTest("(?x)a b c[d e f]", concat(
      changeMatchingOptions(matchingOptions(adding: .extended)),
      "a", "b", "c", charClass("d", "e", "f")
    ))
    parseTest("(?xx)a b c[d e f]", concat(
      changeMatchingOptions(matchingOptions(adding: .extraExtended)),
      "a", "b", "c", charClass("d", "e", "f")
    ))
    parseTest("(?x)a b c(?-x)d e f", concat(
      changeMatchingOptions(matchingOptions(adding: .extended)),
      "a", "b", "c",
      changeMatchingOptions(matchingOptions(removing: .extended)),
      "d", " ", "e", " ", "f"
    ))
    parseTest("(?x)a b c(?-xx)d e f", concat(
      changeMatchingOptions(matchingOptions(adding: .extended)),
      "a", "b", "c",
      changeMatchingOptions(matchingOptions(removing: .extraExtended)),
      "d", " ", "e", " ", "f"
    ))
    parseTest("(?xx)a b c(?-x)d e f", concat(
      changeMatchingOptions(matchingOptions(adding: .extraExtended)),
      "a", "b", "c",
      changeMatchingOptions(matchingOptions(removing: .extended)),
      "d", " ", "e", " ", "f"
    ))
    parseTest("(?x)a b c(?^i)d e f", concat(
      changeMatchingOptions(matchingOptions(adding: .extended)),
      "a", "b", "c",
      changeMatchingOptions(unsetMatchingOptions(adding: .caseInsensitive)),
      "d", " ", "e", " ", "f"
    ))
    parseTest("(?x)a b c(?^x)d e f", concat(
      changeMatchingOptions(matchingOptions(adding: .extended)),
      "a", "b", "c",
      changeMatchingOptions(unsetMatchingOptions(adding: .extended)),
      "d", "e", "f"
    ))
    parseTest("(?:(?x)a b c)d e f", concat(
      nonCapture(concat(
        changeMatchingOptions(matchingOptions(adding: .extended)),
        "a", "b", "c"
      )),
      "d", " ", "e", " ", "f"
    ))
    parseTest("(?x:a b c)# hi", concat(changeMatchingOptions(
      matchingOptions(adding: .extended),
      concat("a", "b", "c")), "#", " ", "h", "i")
    )

    parseTest("(?x-x)a b c", concat(
      changeMatchingOptions(
        matchingOptions(adding: .extended, removing: .extended)
      ),
      "a", " ", "b", " ", "c"
    ))
    parseTest("(?xxx-x)a b c", concat(
      changeMatchingOptions(
        matchingOptions(adding: .extraExtended, .extended, removing: .extended)
      ),
      "a", " ", "b", " ", "c"
    ))
    parseTest("(?xx-i)a b c", concat(
      changeMatchingOptions(
        matchingOptions(adding: .extraExtended, removing: .caseInsensitive)
      ),
      "a", "b", "c"
    ))

    // PCRE states that whitespace seperating quantifiers is permitted under
    // extended syntax http://pcre.org/current/doc/html/pcre2api.html#SEC20
    parseTest("(?x)a *", concat(
      changeMatchingOptions(matchingOptions(adding: .extended)),
      zeroOrMore(of: "a")
    ))
    parseTest("(?x)a + ?", concat(
      changeMatchingOptions(matchingOptions(adding: .extended)),
      oneOrMore(.reluctant, of: "a")
    ))
    parseTest("(?x)a {2,4}", concat(
      changeMatchingOptions(matchingOptions(adding: .extended)),
      quantRange(2 ... 4, of: "a")
    ))

    // PCRE states that whitespace won't be ignored within a range.
    // http://pcre.org/current/doc/html/pcre2api.html#SEC20
    // We however do ignore it.
    parseTest("(?x)a{1, 3}", concat(
      changeMatchingOptions(matchingOptions(adding: .extended)),
      quantRange(1 ... 3, of: "a")
    ))

    // Test that we cover the list of whitespace characters covered by PCRE.
    parseTest(
      "(?x)a\t\u{A}\u{B}\u{C}\u{D}\u{85}\u{200E}\u{200F}\u{2028}\u{2029} b",
      concat(
        changeMatchingOptions(matchingOptions(adding: .extended)),
        "a", "b"
      ))
    parseTest(
      "(?x)[a\t\u{A}\u{B}\u{C}\u{D}\u{85}\u{200E}\u{200F}\u{2028}\u{2029} b]",
      concat(
        changeMatchingOptions(matchingOptions(adding: .extended)),
        charClass("a", "b")
      ))

    parseTest(#"(?i:)?"#, zeroOrOne(of: changeMatchingOptions(
      matchingOptions(adding: .caseInsensitive), empty()
    )))

    // Test multi-line comment handling.
    parseTest(
      """
      # a
      bc # d
      ef# g
      # h
      """,
      concat("b", "c", "e", "f"),
      syntax: .extendedSyntax
    )
    parseTest(
      """
      # a\r\
      bc # d\r\
      ef# g\r\
      # h\r
      """,
      concat("b", "c", "e", "f"),
      syntax: .extendedSyntax
    )
    parseTest(
      """
      # a\r\
      bc # d\r\
      ef# g\r\
      # h\r
      """,
      concat("b", "c", "e", "f"),
      syntax: .extendedSyntax
    )
    parseTest(
      """
      # a\r
      bc # d\r
      ef# g\r
      # h\r
      """,
      concat("b", "c", "e", "f"),
      syntax: .extendedSyntax
    )
    parseTest(
      """
      # a\n\r\
      bc # d\n\r\
      ef# g\n\r\
      # h\n\r
      """,
      concat("b", "c", "e", "f"),
      syntax: .extendedSyntax
    )
    parseTest(
      """
      (*CR)
      # a
      bc # d
      ef# g
      # h
      """,
      ast(empty(), opts: .newlineMatching(.carriageReturnOnly)),
      unsupported: true, syntax: .extendedSyntax
    )
    parseTest(
      """
      (*CR)\r\
      # a\r\
      bc # d\r\
      ef# g\r\
      # h
      """,
      ast(concat("b", "c", "e", "f"), opts: .newlineMatching(.carriageReturnOnly)),
      unsupported: true, syntax: .extendedSyntax
    )
    parseTest(
      """
      (*LF)
      # a
      bc # d
      ef# g
      # h
      """,
      ast(concat("b", "c", "e", "f"), opts: .newlineMatching(.linefeedOnly)),
      unsupported: true, syntax: .extendedSyntax
    )
    parseTest(
      """
      (*CRLF)
      # a
      bc # d
      ef# g
      # h
      """,
      ast(empty(), opts: .newlineMatching(.carriageAndLinefeedOnly)),
      unsupported: true, syntax: .extendedSyntax
    )
    parseTest(
      """
      (*CRLF)
      # a\r
      bc # d\r
      ef# g\r
      # h
      """,
      ast(concat("b", "c", "e", "f"), opts: .newlineMatching(.carriageAndLinefeedOnly)),
      unsupported: true, syntax: .extendedSyntax
    )
    parseTest(
      """
      (*ANYCRLF)
      # a
      bc # d
      ef# g
      # h
      """,
      ast(concat("b", "c", "e", "f"), opts: .newlineMatching(.anyCarriageReturnOrLinefeed)),
      unsupported: true, syntax: .extendedSyntax
    )
    parseTest(
      """
      (*ANYCRLF)
      # a\r\
      bc # d\r\
      ef# g\r\
      # h
      """,
      ast(concat("b", "c", "e", "f"), opts: .newlineMatching(.anyCarriageReturnOrLinefeed)),
      unsupported: true, syntax: .extendedSyntax
    )
    parseTest(
      """
      (*ANYCRLF)
      # a\r
      bc # d\r
      ef# g\r
      # h
      """,
      ast(concat("b", "c", "e", "f"), opts: .newlineMatching(.anyCarriageReturnOrLinefeed)),
      unsupported: true, syntax: .extendedSyntax
    )
    parseTest(
      """
      (*ANY)
      # a
      bc # d
      ef# g
      # h
      """,
      ast(concat("b", "c", "e", "f"), opts: .newlineMatching(.anyUnicode)),
      unsupported: true, syntax: .extendedSyntax
    )
    parseTest(
      """
      # a\u{2028}\
      bc # d
      ef# g\u{2028}\
      # h
      """,
      concat("e", "f"),
      syntax: .extendedSyntax
    )
    parseTest(
      """
      (*ANY)
      # a\u{2028}\
      bc # d\u{2028}\
      ef# g\u{2028}\
      # h
      """,
      ast(concat("b", "c", "e", "f"), opts: .newlineMatching(.anyUnicode)),
      unsupported: true, syntax: .extendedSyntax
    )
    parseTest(
      """
      (*NUL)
      # a
      bc # d\0\
      ef# g
      # h
      """,
      ast(concat("e", "f"), opts: .newlineMatching(.nulCharacter)),
      unsupported: true, syntax: .extendedSyntax
    )
    parseTest(
      """
      (*NUL)
      # a\0\
      bc # d\0\
      ef# g\0\
      # h
      """,
      ast(concat("b", "c", "e", "f"), opts: .newlineMatching(.nulCharacter)),
      unsupported: true, syntax: .extendedSyntax
    )
    parseTest(
      """
      (*CR)(*NUL)
      # a\0\
      bc # d\0\
      ef# g\0\
      # h
      """,
      ast(concat("b", "c", "e", "f"),
          opts: .newlineMatching(.carriageReturnOnly),
                .newlineMatching(.nulCharacter)
         ),
      unsupported: true, syntax: .extendedSyntax
    )

    parseWithDelimitersTest(
      #"""
      #/
        a\
        b\
        c
      /#
      """#,
      concat("a", "\n", "b", "\n", "c")
    )

    // MARK: Parse with delimiters

    parseWithDelimitersTest("/a b/", concat("a", " ", "b"))
    parseWithDelimitersTest("#/a b/#", concat("a", " ", "b"))
    parseWithDelimitersTest("##/a b/##", concat("a", " ", "b"))
    parseWithDelimitersTest("#|a b|#", concat("a", "b"))

    parseWithDelimitersTest("re'a b'", concat("a", " ", "b"))
    parseWithDelimitersTest("rx'a b'", concat("a", "b"))

    parseWithDelimitersTest("#|[a b]|#", charClass("a", "b"))
    parseWithDelimitersTest(
      "#|(?-x)[a b]|#", concat(
        changeMatchingOptions(matchingOptions(removing: .extended)),
        charClass("a", " ", "b")
      ))
    parseWithDelimitersTest("#|[[a ] b]|#", charClass(charClass("a"), "b"))

    // Non-semantic whitespace between quantifier characters for consistency
    // with PCRE.
    parseWithDelimitersTest("#|a * ?|#", zeroOrMore(.reluctant, of: "a"))

    // End-of-line comments aren't enabled by default in experimental syntax.
    parseWithDelimitersTest("#|#abc|#", concat("#", "a", "b", "c"))
    parseWithDelimitersTest("#|(?x)#abc|#", changeMatchingOptions(
      matchingOptions(adding: .extended))
    )

    parseWithDelimitersTest("#|||#", alt(empty(), empty()))
    parseWithDelimitersTest("#||||#", alt(empty(), empty(), empty()))
    parseWithDelimitersTest("#|a||#", alt("a", empty()))

    parseWithDelimitersTest("re'x*'", zeroOrMore(of: "x"))

    parseWithDelimitersTest(#"re'🔥🇩🇰'"#, concat("🔥", "🇩🇰"))
    parseWithDelimitersTest(#"re'🔥✅'"#, concat("🔥", "✅"))

    // Printable ASCII characters.
    delimiterLexingTest(##"re' !"#$%&\'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_`abcdefghijklmnopqrstuvwxyz{|}~'"##)

    // Make sure we can handle a combining accent as first character.
    parseWithDelimitersTest("/\u{301}/", "\u{301}")

    delimiterLexingTest("/a/#", ignoreTrailing: true)

    // MARK: Multiline

    parseWithDelimitersTest("#/\n/#", empty())
    parseWithDelimitersTest("#/\r/#", empty())
    parseWithDelimitersTest("#/\r\n/#", empty())
    parseWithDelimitersTest("#/\n\t\t  /#", empty())
    parseWithDelimitersTest("#/  \t\t\n\t\t  /#", empty())

    parseWithDelimitersTest("#/\n a \n/#", "a")
    parseWithDelimitersTest("#/\r a \r/#", "a")
    parseWithDelimitersTest("#/\r\n a \r\n/#", "a")
    parseWithDelimitersTest("#/\n a \n\t\t  /#", "a")
    parseWithDelimitersTest("#/\t  \n a \n\t\t  /#", "a")

    parseWithDelimitersTest("""
      #/
      a
        b
           c
         /#
      """, concat("a", "b", "c"))

    parseWithDelimitersTest("""
      #/
      a    # comment
        b # another
      #
         /#
      """, concat("a", "b"))

    // (?x) has no effect.
    parseWithDelimitersTest("""
      #/
      (?x)
      # comment
      /#
      """, changeMatchingOptions(matchingOptions(adding: .extended))
    )

    // Scoped removal of extended syntax is allowed as long as it does not span
    // multiple lines.
    parseWithDelimitersTest("""
      #/
      (?-x:a b)
      /#
      """, changeMatchingOptions(
        matchingOptions(removing: .extended),
        concat("a", " ", "b")
      )
    )
    parseWithDelimitersTest("""
      #/
      (?-xx:a b)
      /#
      """, changeMatchingOptions(
        matchingOptions(removing: .extraExtended),
        concat("a", " ", "b")
      )
    )
    parseWithDelimitersTest("""
      #/
      (?^: a b ) # comment
      /#
      """, changeMatchingOptions(unsetMatchingOptions(), concat(" ", "a", " ", "b", " "))
    )

    parseWithDelimitersTest(#"""
      #/
      \p{
        gc
         =
        digit
      }
      /#
      """#, prop(.generalCategory(.decimalNumber)))

    parseWithDelimitersTest(#"""
      #/
      \u{
        aB
          B
      c
      }
      /#
      """#, scalarSeq("\u{AB}", "\u{B}", "\u{C}"))

    parseWithDelimitersTest(#"""
      #/
      [
        a # interesting
      b-c #a
        d]
      /#
      """#, charClass("a", range_m("b", "c"), "d"))

    parseWithDelimitersTest(#"""
      #/
      [
        a # interesting
        -   #a
         b
      ]
      /#
      """#, charClass(range_m("a", "b")))


    // MARK: Delimiter skipping: Make sure we can skip over the ending delimiter
    // if it's clear that it's part of the regex syntax.

    parseWithDelimitersTest(
      #"re'(?'a_bcA0'\')'"#, namedCapture("a_bcA0", "'"))
    parseWithDelimitersTest(
      #"re'(?'a_bcA0-c1A'x*)'"#,
      balancedCapture(name: "a_bcA0", priorName: "c1A", zeroOrMore(of: "x")),
      unsupported: true)

    parseWithDelimitersTest(
      #"rx' (?'a_bcA0' a b)'"#, concat(namedCapture("a_bcA0", concat("a", "b"))))

    parseWithDelimitersTest(
      #"re'(?('a_bcA0')x|y)'"#, conditional(
        .groupMatched(ref("a_bcA0")), trueBranch: "x", falseBranch: "y"),
      unsupported: true
    )
    parseWithDelimitersTest(
      #"re'(?('+20')\')'"#, conditional(
        .groupMatched(ref(plus: 20)), trueBranch: "'", falseBranch: empty()),
      unsupported: true
    )
    parseWithDelimitersTest(
      #"re'a\k'b0A''"#, concat("a", backreference(.named("b0A"))), throwsError: .invalidNamedReference("b0A"))
    parseWithDelimitersTest(
      #"re'\k'+2-1''"#, backreference(ref(plus: 2), recursionLevel: -1),
      unsupported: true
    )

    parseWithDelimitersTest(
      #"re'a\g'b0A''"#, concat("a", subpattern(.named("b0A"))), unsupported: true)
    parseWithDelimitersTest(
      #"re'\g'-1'\''"#, concat(subpattern(ref(minus: 1)), "'"), unsupported: true)

    parseWithDelimitersTest(
      #"re'(?C'a*b\c 🔥_ ;')'"#, pcreCallout(string: #"a*b\c 🔥_ ;"#),
      unsupported: true)

    // Fine, because we don't end up skipping.
    delimiterLexingTest(#"re'(?'"#)
    delimiterLexingTest(#"re'(?('"#)
    delimiterLexingTest(#"re'\k'"#)
    delimiterLexingTest(#"re'\g'"#)
    delimiterLexingTest(#"re'(?C'"#)

    // Not a valid group name, but we can still skip over it.
    delimiterLexingTest(#"re'(?'🔥')'"#)

    // Escaped, so don't skip. These will ignore the ending `'` as we've already
    // closed the literal.
    parseWithDelimitersTest(
      #"re'\(?''"#, zeroOrOne(of: "("), ignoreTrailing: true
    )
    parseWithDelimitersTest(
      #"re'\\k''"#, concat("\\", "k"), ignoreTrailing: true
    )
    parseWithDelimitersTest(
      #"re'\\g''"#, concat("\\", "g"), ignoreTrailing: true
    )
    parseWithDelimitersTest(
      #"re'\(?C''"#, concat(zeroOrOne(of: "("), "C"), ignoreTrailing: true
    )
    delimiterLexingTest(#"re'(\?''"#, ignoreTrailing: true)
    delimiterLexingTest(#"re'\(?(''"#, ignoreTrailing: true)

    // MARK: Parse not-equal

    // Make sure dumping output correctly reflects differences in AST.
    parseNotEqualTest(#"abc"#, #"abd"#)
    parseNotEqualTest(#" "#, #""#)

    parseNotEqualTest(#"a{2}"#, #"a{3}"#)

    parseNotEqualTest(#"[\p{Any}]"#, #"[[:Any:]]"#)

    parseNotEqualTest(#"\u{A}"#, #"\u{B}"#)
    parseNotEqualTest(#"\u{A B}"#, #"\u{B A}"#)
    parseNotEqualTest(#"\u{AB}"#, #"\u{A B}"#)
    parseNotEqualTest(#"[\u{AA BB}-\u{CC}]"#, #"[\u{AA DD}-\u{CC}]"#)
    parseNotEqualTest(#"[\u{AA BB}-\u{DD}]"#, #"[\u{AA BB}-\u{CC}]"#)

    parseNotEqualTest(#"[abc[:space:]\d]+"#,
                      #"[abc[:upper:]\d]+"#)

    parseNotEqualTest(#"[abc[:space:]\d]+"#,
                      #"[ac[:space:]\d]+"#)

    parseNotEqualTest(#"[abc[:space:]\d]+"#,
                      #"[acc[:space:]\s]+"#)

    parseNotEqualTest(#"[abc[:space:]\d]+"#,
                      #"[acc[:space:]\d]*"#)

    parseNotEqualTest(#"([a-c&&e]*)+"#,
                      #"([a-d&&e]*)+"#)

    parseNotEqualTest(#"[abc]"#, #"[a b c]"#)

    parseNotEqualTest("[abc]", "[^abc]")

    parseNotEqualTest(#"\1"#, #"\10"#)

    parseNotEqualTest("(?^:)", ("(?-:)"))
    parseNotEqualTest("(?^i:)", ("(?i:)"))
    parseNotEqualTest("(?i)", ("(?i:)"))
    parseNotEqualTest("(?i)", ("(?m)"))
    parseNotEqualTest("(?i-s)", ("(?i-m)"))
    parseNotEqualTest("(?i-s:)", ("(?i-m:)"))
    parseNotEqualTest("(?y{w}:)", ("(?y{g}:)"))

    parseNotEqualTest("|", "||")
    parseNotEqualTest("a|", "|")
    parseNotEqualTest("a|b", "|")

    parseNotEqualTest(#"\1"#, #"\2"#)
    parseNotEqualTest(#"\k'a'"#, #"\k'b'"#)
    parseNotEqualTest(#"(?1)"#, #"(?2)"#)
    parseNotEqualTest(#"(?+1)"#, #"(?1)"#)
    parseNotEqualTest(#"(?&a)"#, #"(?&b)"#)
    parseNotEqualTest(#"\k<a-1>"#, #"\k<a-2>"#)
    parseNotEqualTest(#"\k<a>"#, #"\k<a-2>"#)

    parseNotEqualTest(#"\Qabc\E"#, #"\Qdef\E"#)
    parseNotEqualTest(#""abc""#, #""def""#)

    parseNotEqualTest(#"(?(1)a|)"#, #"(?(1)b|)"#)
    parseNotEqualTest(#"(?(1)|)"#, #"(?(1)b|)"#)
    parseNotEqualTest(#"(?(1)|a)"#, #"(?(1)|b)"#)
    parseNotEqualTest(#"(?(2)|)"#, #"(?(1)|)"#)
    parseNotEqualTest(#"(?(R1)|)"#, #"(?(R2)|)"#)
    parseNotEqualTest(#"(?(R&abc)|)"#, #"(?(R&def)|)"#)
    parseNotEqualTest(#"(?(VERSION=0.1))"#, #"(?(VERSION=0.2))"#)
    parseNotEqualTest(#"(?(VERSION=0.1))"#, #"(?(VERSION>=0.1))"#)

    parseNotEqualTest("(?C0)", "(?C1)")
    parseNotEqualTest("(?C0)", "(?C'hello')")

    parseNotEqualTest("(*X)", "(*Y)")
    parseNotEqualTest("(*X[a])", "(*X[b])")
    parseNotEqualTest("(*X[a]{a})", "(*X[a]{b})")
    parseNotEqualTest("(*X[a]{a})", "(*X[a])")
    parseNotEqualTest("(*X{a})", "(*X[a]{a})")
    parseNotEqualTest("(*X{a})", "(*X{a,b})")

    parseNotEqualTest("(?{a})", "(?{b})")
    parseNotEqualTest("(?{a}[a])", "(?{a}[b])")
    parseNotEqualTest("(?{a})", "(?{a}[a])")
    parseNotEqualTest("(?{a}X)", "(?{a})")
    parseNotEqualTest("(?{a}<)", "(?{a}X)")

    parseNotEqualTest("(*ACCEPT)", "(*ACCEPT:a)")
    parseNotEqualTest("(*MARK:a)", "(*MARK:b)")
    parseNotEqualTest("(*:a)", "(*:b)")
    parseNotEqualTest("(*FAIL)", "(*SKIP)")

    parseNotEqualTest("(?<a-b>)", "(?<a-c>)")
    parseNotEqualTest("(?<c-b>)", "(?<a-b>)")
    parseNotEqualTest("(?<-b>)", "(?<a-b>)")

    parseNotEqualTest("(?~|)", "(?~|a)")
    parseNotEqualTest("(?~|a)", "(?~|b)")
    parseNotEqualTest("(?~|a)", "(?~|a|)")
    parseNotEqualTest("(?~|a|b)", "(?~|a|)")
    parseNotEqualTest("(?~|a|b)", "(?~|a|c)")
    parseNotEqualTest("(?~)", "(?~|)")
    parseNotEqualTest("(?~a)", "(?~b)")

    parseNotEqualTest("(*CR)", "(*LF)")
    parseNotEqualTest("(*LIMIT_DEPTH=3)", "(*LIMIT_DEPTH=1)")
    parseNotEqualTest("(*UTF)", "(*LF)")
    parseNotEqualTest("(*LF)", "(*BSR_ANYCRLF)")
  }

  func testParseSourceLocations() throws {
    func entireRange(input: String) -> Range<Int> {
      0 ..< input.count
    }
    func insetRange(by i: Int) -> (String) -> Range<Int> {
      { i ..< $0.count - i }
    }
    func range(_ indices: Range<Int>) -> (String) -> Range<Int> {
      { _ in indices }
    }

    // MARK: Alternations

    typealias Alt = AST.Alternation

    let alternations = [
      "|", "a|", "|b", "a|b", "abc|def", "a|b|c|d", "a|b|", "|||", "a|||d",
      "||c|"
    ]

    // Make sure we correctly compute source ranges for alternations.
    for alt in alternations {
      rangeTest(alt, entireRange)
      rangeTest("(\(alt))", insetRange(by: 1), at: \.children![0].location)
    }

    rangeTest("|", entireRange, at: { $0.as(Alt.self)!.pipes[0] })
    rangeTest("a|", range(1 ..< 2), at: { $0.as(Alt.self)!.pipes[0] })
    rangeTest("a|b", range(1 ..< 2), at: { $0.as(Alt.self)!.pipes[0] })
    rangeTest("|||", range(1 ..< 2), at: { $0.as(Alt.self)!.pipes[1] })

    // MARK: Custom character classes

    rangeTest("[a-z]", range(2 ..< 3), at: {
      $0.as(CustomCC.self)!.members[0].as(CustomCC.Range.self)!.dashLoc
    })

    // MARK: Unicode scalars

    rangeTest(#"\u{65}"#, range(3 ..< 5), at: {
      $0.as(AST.Atom.self)!.as(AST.Atom.Scalar.self)!.location
    })

    rangeTest(#"\u{  65 58 }"#, range(5 ..< 7), at: {
      $0.as(AST.Atom.self)!.as(AST.Atom.ScalarSequence.self)!.scalars[0].location
    })

    rangeTest(#"\u{  65 58 }"#, range(8 ..< 10), at: {
      $0.as(AST.Atom.self)!.as(AST.Atom.ScalarSequence.self)!.scalars[1].location
    })

    // MARK: References

    rangeTest(#"\k<a+2>"#, range(3 ..< 6), at: {
      $0.as(AST.Atom.self)!.as(AST.Reference.self)!.innerLoc
    })
    rangeTest(#"\k<-1+2>"#, range(3 ..< 7), at: {
      $0.as(AST.Atom.self)!.as(AST.Reference.self)!.innerLoc
    })

    // MARK: Callout

    typealias Callout = AST.Atom.Callout

    rangeTest(#"(?C0)"#, range(3 ..< 4), at: {
      $0.as(AST.Atom.self)!.as(Callout.self)!
        .as(Callout.PCRE.self)!.arg.location
    })
    rangeTest(#"(?C)"#, range(3 ..< 3), at: {
      $0.as(AST.Atom.self)!.as(Callout.self)!
        .as(Callout.PCRE.self)!.arg.location
    })

    rangeTest(#"(*abc[ta]{a,b})"#, range(2 ..< 5), at: {
      $0.as(AST.Atom.self)!.as(Callout.self)!
        .as(Callout.OnigurumaNamed.self)!.name.location
    })
    rangeTest(#"(*abc[ta]{a,b})"#, range(5 ..< 6), at: {
      $0.as(AST.Atom.self)!.as(Callout.self)!
        .as(Callout.OnigurumaNamed.self)!.tag!.leftBracket
    })
    rangeTest(#"(*abc[ta]{a,b})"#, range(8 ..< 9), at: {
      $0.as(AST.Atom.self)!.as(Callout.self)!
        .as(Callout.OnigurumaNamed.self)!.tag!.rightBracket
    })
    rangeTest(#"(*abc[ta]{a,b})"#, range(9 ..< 10), at: {
      $0.as(AST.Atom.self)!.as(Callout.self)!
        .as(Callout.OnigurumaNamed.self)!.args!.leftBrace
    })
    rangeTest(#"(*abc[ta]{a,b})"#, range(12 ..< 13), at: {
      $0.as(AST.Atom.self)!.as(Callout.self)!
        .as(Callout.OnigurumaNamed.self)!.args!.args[1].location
    })
    rangeTest(#"(*abc[ta]{a,b})"#, range(13 ..< 14), at: {
      $0.as(AST.Atom.self)!.as(Callout.self)!
        .as(Callout.OnigurumaNamed.self)!.args!.rightBrace
    })

    rangeTest(#"(?{{{abc}}}[t]X)"#, range(2 ..< 5), at: {
      $0.as(AST.Atom.self)!.as(Callout.self)!
        .as(Callout.OnigurumaOfContents.self)!.openBraces
    })
    rangeTest(#"(?{{{abc}}}[t]X)"#, range(8 ..< 11), at: {
      $0.as(AST.Atom.self)!.as(Callout.self)!
        .as(Callout.OnigurumaOfContents.self)!.closeBraces
    })
    rangeTest(#"(?{{{abc}}}[t]X)"#, range(11 ..< 12), at: {
      $0.as(AST.Atom.self)!.as(Callout.self)!
        .as(Callout.OnigurumaOfContents.self)!.tag!.leftBracket
    })
    rangeTest(#"(?{{{abc}}}[t]X)"#, range(13 ..< 14), at: {
      $0.as(AST.Atom.self)!.as(Callout.self)!
        .as(Callout.OnigurumaOfContents.self)!.tag!.rightBracket
    })
    rangeTest(#"(?{{{abc}}}[t]X)"#, range(14 ..< 15), at: {
      $0.as(AST.Atom.self)!.as(Callout.self)!
        .as(Callout.OnigurumaOfContents.self)!.direction.location
    })
    rangeTest(#"(?{a})"#, range(5 ..< 5), at: {
      $0.as(AST.Atom.self)!.as(Callout.self)!
        .as(Callout.OnigurumaOfContents.self)!.direction.location
    })

    // MARK: Conditionals

    rangeTest("(?(1))", entireRange)
    rangeTest("(?(1)a|)", entireRange)

    rangeTest("(?(1)|)", range(5 ..< 6), at: {
      $0.as(AST.Conditional.self)!.pipe!
    })

    rangeTest("(?(1))", range(3 ..< 4), at: {
      $0.as(AST.Conditional.self)!.condition.location
    })
    rangeTest("(?(-1+2))", range(3 ..< 7), at: {
      $0.as(AST.Conditional.self)!.condition.location
    })
    rangeTest("(?(VERSION>=4.1))", range(3 ..< 15), at: {
      $0.as(AST.Conditional.self)!.condition.location
    })
    rangeTest("(?(xxx))", range(2 ..< 7), at: {
      $0.as(AST.Conditional.self)!.condition.location
    })

    // MARK: Absent functions

    rangeTest("(?~a)", entireRange)
    rangeTest("(?~|)", entireRange)
    rangeTest("(?~|a)", entireRange)
    rangeTest("(?~|a|b)", entireRange)
  }

  func testParseRecovery() {
    // MARK: Groups

    parseTest(
      "(", capture(empty()),
      throwsError: .expected(")"), captures: [.cap]
    )
    parseTest(
      "(abc", capture(concat("a", "b", "c")),
      throwsError: .expected(")"), captures: [.cap]
    )
    parseTest("(?", nonCapture(empty()), throwsError: .expectedGroupSpecifier, .expected(")"))
    parseTest("(?:", nonCapture(empty()), throwsError: .expected(")"))

    parseTest(
      "(?<", namedCapture("", empty()),
      throwsError: .expectedIdentifier(.groupName), .expected(">"), .expected(")"),
      captures: [.named("")]
    )
    parseTest(
      "(?<a", namedCapture("a", empty()),
      throwsError: .expected(">"), .expected(")"),
      captures: [.named("a")]
    )

    // MARK: Character classes

    parseTest("[", charClass(), throwsError: .expectedCustomCharacterClassMembers, .expected("]"))
    parseTest("[^", charClass(inverted: true), throwsError: .expectedCustomCharacterClassMembers, .expected("]"))
    parseTest("[a", charClass("a"), throwsError: .expected("]"))

    parseTest(
      "[a&&", charClass(setOp("a", op: .intersection)),
      throwsError: .expectedCustomCharacterClassMembers, .expected("]")
    )
    parseTest(
      "[a&&b", charClass(setOp("a", op: .intersection, "b")),
      throwsError: .expected("]")
    )

    diagnosticTest("[:a", .expected("]"))
    diagnosticTest("[:a:", .expected("]"))
    diagnosticTest("[[:a", .expected("]"))
    diagnosticTest("[[:a:", .expected("]"))
    diagnosticTest("[[:a[:]", .expected("]"))

    diagnosticTest("[::]", .emptyProperty)
    diagnosticTest("[:=:]", .emptyProperty)
    diagnosticTest("[[::]]", .emptyProperty)
    diagnosticTest("[[:=:]]", .emptyProperty)

    // MARK: Unicode Scalars

    parseTest(#"\u{"#, scalar("\u{0}"), throwsError: .expectedNumber("", kind: .hex), .expected("}"))
    parseTest(#"\u{ "#, scalar("\u{0}"), throwsError: .expectedNumber("", kind: .hex), .expected("}"))
    parseTest(#"\u{5"#, scalar("\u{5}"), throwsError: .expected("}"))
    parseTest(#"\x{5"#, scalar("\u{5}"), throwsError: .expected("}"))

    parseTest(#"\u{ 5"#, scalar("\u{5}"), throwsError: .expected("}"))
    parseTest(#"\u{ 5 "#, scalar("\u{5}"), throwsError: .expected("}"))
    parseTest(#"\u{ 5 6"#, scalarSeq("\u{5}", "\u{6}"), throwsError: .expected("}"))
    parseTest(#"\u{ 5 6 "#, scalarSeq("\u{5}", "\u{6}"), throwsError: .expected("}"))

    parseTest(#"\x{"#, scalar("\u{0}"), throwsError: .expectedNumber("", kind: .hex), .expected("}"))

    parseTest(#"\u{ A H }"#, scalarSeq("\u{A}", "\u{0}"), throwsError: .expectedNumber("H", kind: .hex))

    parseTest(#"\uABC"#, scalar("\u{ABC}"), throwsError: .expectedNumDigits("ABC", 4))

    // MARK: Named characters

    parseTest(#"\N{"#, atom(.namedCharacter("")), throwsError: .expected("}"))
    parseTest(#"\N{a"#, atom(.namedCharacter("a")), throwsError: .expected("}"))
    parseTest(#"\N{U"#, atom(.namedCharacter("U")), throwsError: .expected("}"))
    parseTest(#"\N{U+"#, scalar("\u{0}"), throwsError: .expectedNumber("", kind: .hex), .expected("}"))
    parseTest(#"\N{U+A"#, scalar("\u{A}"), throwsError: .expected("}"))
    parseTest(#"\N{U+}"#, scalar("\u{0}"), throwsError: .expectedNumber("", kind: .hex))

    // MARK: Character properties

    parseTest(
      #"\p{"#, prop(.invalid(key: nil, value: "")),
      throwsError: .emptyProperty, .expected("}")
    )
    parseTest(
      #"\p{a"#, prop(.invalid(key: nil, value: "a")),
      throwsError: .unknownProperty(key: nil, value: "a"), .expected("}")
    )
    parseTest(
      #"\p{a="#, prop(.invalid(key: "a", value: "")),
      throwsError: .emptyProperty, .expected("}")
    )
    parseTest(
      #"\p{a=b"#, prop(.invalid(key: "a", value: "b")),
      throwsError: .unknownProperty(key: "a", value: "b"), .expected("}")
    )
    parseTest(
      #"\p{sc"#, prop(.generalCategory(.currencySymbol)),
      throwsError: .expected("}")
    )
    parseTest(
      #"\p{sc="#, prop(.invalid(key: "sc", value: "")),
      throwsError: .emptyProperty, .expected("}")
    )
    parseTest(
      #"\p{sc=a"#, prop(.invalid(key: "sc", value: "a")),
      throwsError: .unrecognizedScript("a"), .expected("}")
    )

    // MARK: Matching options

    parseTest(
      #"(?^"#, changeMatchingOptions(unsetMatchingOptions(), empty()),
      throwsError: .expected(")")
    )
    parseTest(
      #"(?x"#, changeMatchingOptions(matchingOptions(adding: .extended), empty()),
      throwsError: .expected(")")
    )
    parseTest(
      #"(?xi"#, changeMatchingOptions(matchingOptions(adding: .extended, .caseInsensitive), empty()),
      throwsError: .expected(")")
    )
    parseTest(
      #"(?xi-"#, changeMatchingOptions(
        matchingOptions(adding: .extended, .caseInsensitive), empty()
      ),
      throwsError: .expected(")")
    )
    parseTest(
      #"(?xi-n"#, changeMatchingOptions(
        matchingOptions(adding: .extended, .caseInsensitive, removing: .namedCapturesOnly),
        empty()
      ),
      throwsError: .expected(")")
    )
    parseTest(
      #"(?xz"#, changeMatchingOptions(matchingOptions(adding: .extended), "z"),
      throwsError: .invalidMatchingOption("z"), .expected(")")
    )
    parseTest(
      #"(?x:"#, changeMatchingOptions(matchingOptions(adding: .extended), empty()),
      throwsError: .expected(")")
    )

    // MARK: Invalid values

    parseTest("a{9999999999999999999999999999}", exactly(nil, of: "a"),
              throwsError: .numberOverflow("9999999999999999999999999999"))
  }

  func testParseErrors() {
    // MARK: Unbalanced delimiters.

    diagnosticTest("(", .expected(")"))
    diagnosticTest(")", .unbalancedEndOfGroup)
    diagnosticTest(")))", .unbalancedEndOfGroup)
    diagnosticTest("())()", .unbalancedEndOfGroup)

    diagnosticTest("[", .expectedCustomCharacterClassMembers, .expected("]"))
    diagnosticTest("[^", .expectedCustomCharacterClassMembers, .expected("]"))

    diagnosticTest(#"\u{5"#, .expected("}"))
    diagnosticTest(#"\x{5"#, .expected("}"))
    diagnosticTest(#"\N{A"#, .expected("}"))
    diagnosticTest(#"\N{U+A"#, .expected("}"))
    diagnosticTest(#"\p{a"#, .unknownProperty(key: nil, value: "a"), .expected("}"))
    diagnosticTest(#"\p{a="#, .emptyProperty, .expected("}"))
    diagnosticTest(#"\p{a=}"#, .emptyProperty)
    diagnosticTest(#"\p{a=b"#, .unknownProperty(key: "a", value: "b"), .expected("}"))
    diagnosticTest(#"\p{aaa[b]}"#, .unknownProperty(key: nil, value: "aaa"), .expected("}"))
    diagnosticTest(#"\p{a=b=c}"#, .unknownProperty(key: "a", value: "b"), .expected("}"))
    diagnosticTest(#"\p{script=Not_A_Script}"#, .unrecognizedScript("Not_A_Script"))
    diagnosticTest(#"\p{scx=Not_A_Script}"#, .unrecognizedScript("Not_A_Script"))
    diagnosticTest(#"\p{gc=Not_A_Category}"#, .unrecognizedCategory("Not_A_Category"))
    diagnosticTest(#"\p{age=3}"#, .invalidAge("3"))
    diagnosticTest(#"\p{age=V3}"#, .invalidAge("V3"))
    diagnosticTest(#"\p{age=3.0.1}"#, .invalidAge("3.0.1"))
    diagnosticTest(#"\p{nv=A}"#, .invalidNumericValue("A"))
    diagnosticTest(#"\p{Numeric_Value=1.2.3.4}"#, .invalidNumericValue("1.2.3.4"))
    diagnosticTest(#"\p{nt=Not_A_NumericType}"#, .unrecognizedNumericType("Not_A_NumericType"))
    diagnosticTest(#"\p{Numeric_Type=Nuemric}"#, .unrecognizedNumericType("Nuemric"))
    diagnosticTest(#"\p{Simple_Lowercase_Mapping}"#, .unknownProperty(key: nil, value: "Simple_Lowercase_Mapping"))
    diagnosticTest(#"\p{Simple_Lowercase_Mapping=}"#, .emptyProperty)
    diagnosticTest(#"\p{ccc=255}"#, .invalidCCC("255"))
    diagnosticTest(#"\p{ccc=Nada}"#, .invalidCCC("Nada"))
    diagnosticTest(#"(?#"#, .expected(")"))
    diagnosticTest(#"(?x"#, .expected(")"))

    diagnosticTest(#"(?"#, .expectedGroupSpecifier, .expected(")"))
    diagnosticTest(#"(?^"#, .expected(")"))
    diagnosticTest(#"(?^i"#, .expected(")"))

    diagnosticTest(#"(?y)"#, .expected("{"), unsupported: true)
    diagnosticTest(#"(?y{)"#, .unknownTextSegmentMatchingOption(")"), .expected("}"), .expected(")"), unsupported: true)
    diagnosticTest(#"(?y{g)"#, .expected("}"), unsupported: true)
    diagnosticTest(#"(?y{x})"#, .unknownTextSegmentMatchingOption("x"), unsupported: true)

    diagnosticTest(#"(?P"#, .expected(")"))
    diagnosticTest(#"(?R"#, .expected(")"), unsupported: true)

    diagnosticTest(#""ab"#, .expected("\""), syntax: .experimental)
    diagnosticTest(#""ab\""#, .expected("\""), syntax: .experimental)
    diagnosticTest("\"ab\\", .expectedEscape, .expected("\""), syntax: .experimental)

    diagnosticTest("(?C", .expected(")"), unsupported: true)

    diagnosticTest("(?<", .expectedIdentifier(.groupName), .expected(">"), .expected(")"))
    diagnosticTest("(?<a", .expected(">"), .expected(")"))
    diagnosticTest("(?<a-", .expectedIdentifier(.groupName), .expected(">"), .expected(")"), unsupported: true)
    diagnosticTest("(?<a--", .identifierMustBeAlphaNumeric(.groupName), .expected(">"), .expected(")"), unsupported: true)
    diagnosticTest("(?<a-b", .expected(">"), .expected(")"), unsupported: true)
    diagnosticTest("(?<a-b>", .expected(")"), unsupported: true)

    // MARK: Character classes

    diagnosticTest("[a", .expected("]"))

    // Character classes may not be empty.
    diagnosticTest("[]", .expectedCustomCharacterClassMembers)
    diagnosticTest("[]]", .expectedCustomCharacterClassMembers)
    diagnosticTest("[]a]", .expectedCustomCharacterClassMembers)
    diagnosticTest("(?x)[  ]", .expectedCustomCharacterClassMembers)
    diagnosticTest("(?x)[ ]  ]", .expectedCustomCharacterClassMembers)
    diagnosticTest("(?x)[ ] a ]", .expectedCustomCharacterClassMembers)
    diagnosticTest("(?xx)[ ] a ]+", .expectedCustomCharacterClassMembers)
    diagnosticTest("(?x)[ ]]", .expectedCustomCharacterClassMembers)

    diagnosticTest("[&&]", .expectedCustomCharacterClassMembers)
    diagnosticTest("[a&&]", .expectedCustomCharacterClassMembers)
    diagnosticTest("[&&a]", .expectedCustomCharacterClassMembers)
    diagnosticTest("(?x)[ && ]", .expectedCustomCharacterClassMembers)
    diagnosticTest("(?x)[ &&a]", .expectedCustomCharacterClassMembers)
    diagnosticTest("(?x)[a&& ]", .expectedCustomCharacterClassMembers)

    diagnosticTest("[:a", .expected("]"))
    diagnosticTest("[:a:", .expected("]"))
    diagnosticTest("[[:a", .expected("]"))
    diagnosticTest("[[:a:", .expected("]"))
    diagnosticTest("[[:a[:]", .expected("]"))

    diagnosticTest("[::]", .emptyProperty)
    diagnosticTest("[:=:]", .emptyProperty)
    diagnosticTest("[[::]]", .emptyProperty)
    diagnosticTest("[[:=:]]", .emptyProperty)

    diagnosticTest(#"|([\d-c])?"#, .invalidCharacterClassRangeOperand)
    diagnosticTest("[[a]-b]", .invalidCharacterClassRangeOperand)

    // .NET subtraction is banned, we require explicit '--'.
    diagnosticTest("[a-[b]]", .unsupportedDotNetSubtraction)
    diagnosticTest(#"[abc-[def]]"#, .unsupportedDotNetSubtraction)
    diagnosticTest(#"[abc-[^def]]"#, .unsupportedDotNetSubtraction)
    diagnosticTest(#"[\d\u{0}[a]-[b-[c]]]"#, .unsupportedDotNetSubtraction, .invalidCharacterClassRangeOperand)
    diagnosticTest("[a-z-[d-w-[m-o]]]", .unsupportedDotNetSubtraction)
    diagnosticTest(#"[a-[:b]]"#, .unsupportedDotNetSubtraction)
    diagnosticTest(#"[[a]-[b]]"#, .invalidCharacterClassRangeOperand)
    diagnosticTest(#"[ -[ ]]"#, .unsupportedDotNetSubtraction)
    diagnosticTest(#"(?x)[a  -  [b]  ]"#, .unsupportedDotNetSubtraction)

    diagnosticTest(#"[a-[]]"#, .expectedCustomCharacterClassMembers, .unsupportedDotNetSubtraction)
    diagnosticTest(#"[-[]]"#, .expectedCustomCharacterClassMembers)
    diagnosticTest(#"(?x)[ - [ ] ]"#, .expectedCustomCharacterClassMembers)
    diagnosticTest(#"(?x)[a-[ ] ]"#, .expectedCustomCharacterClassMembers, .unsupportedDotNetSubtraction)
    diagnosticTest(#"[a-[:digit:]]"#, .invalidCharacterClassRangeOperand)

    diagnosticTest("[--]", .expectedCustomCharacterClassMembers)
    diagnosticTest("[---]", .expectedCustomCharacterClassMembers)
    diagnosticTest("[----]", .expectedCustomCharacterClassMembers)

    // Quoted sequences aren't currently supported as range operands.
    diagnosticTest(#"[a-\Qbc\E]"#, .unsupported("range with quoted sequence"))
    diagnosticTest(#"[\Qbc\E-de]"#, .unsupported("range with quoted sequence"))

    diagnosticTest(#"|([🇦🇫-🇿🇼])?"#, .invalidCharacterClassRangeOperand)
    diagnosticTest(#"|([👨‍👩‍👦-👩‍👩‍👧‍👧])?"#, .invalidCharacterClassRangeOperand)

    // Not single-scalar NFC.
    diagnosticTest("[e\u{301}-e\u{302}]", .invalidCharacterClassRangeOperand)

    // These scalar values expand under NFC.
    let nfcExpandingScalars: [UInt32] = [
      0x344, 0x958, 0x959, 0x95A, 0x95B, 0x95C, 0x95D, 0x95E, 0x95F, 0x9DC,
      0x9DD, 0x9DF, 0xA33, 0xA36, 0xA59, 0xA5A, 0xA5B, 0xA5E, 0xB5C, 0xB5D,
      0xF43, 0xF4D, 0xF52, 0xF57, 0xF5C, 0xF69, 0xF73, 0xF75, 0xF76, 0xF78,
      0xF81, 0xF93, 0xF9D, 0xFA2, 0xFA7, 0xFAC, 0xFB9, 0x2ADC, 0xFB1D, 0xFB1F,
      0xFB2A, 0xFB2B, 0xFB2C, 0xFB2D, 0xFB2E, 0xFB2F, 0xFB30, 0xFB31, 0xFB32,
      0xFB33, 0xFB34, 0xFB35, 0xFB36, 0xFB38, 0xFB39, 0xFB3A, 0xFB3B, 0xFB3C,
      0xFB3E, 0xFB40, 0xFB41, 0xFB43, 0xFB44, 0xFB46, 0xFB47, 0xFB48, 0xFB49,
      0xFB4A, 0xFB4B, 0xFB4C, 0xFB4D, 0xFB4E, 0x1D15E, 0x1D15F, 0x1D160,
      0x1D161, 0x1D162, 0x1D163, 0x1D164, 0x1D1BB, 0x1D1BC, 0x1D1BD, 0x1D1BE,
      0x1D1BF, 0x1D1C0
    ]
    for scalar in nfcExpandingScalars {
      let hex = String(scalar, radix: 16)
      diagnosticTest(
        #"[\u{\#(hex)}-\u{\#(hex)}]"#, .invalidCharacterClassRangeOperand)
    }

    // The NFC form of U+2126 is U+3A9.
    diagnosticTest(#"[\u{2126}-\u{2126}]"#, .invalidCharacterClassRangeOperand)

    diagnosticTest(#"[_-A]"#, .invalidCharacterRange(from: "_", to: "A"))
    diagnosticTest(#"(?i)[_-A]"#, .invalidCharacterRange(from: "_", to: "A"))
    diagnosticTest(#"[c-b]"#, .invalidCharacterRange(from: "c", to: "b"))
    diagnosticTest(#"[\u{66}-\u{65}]"#, .invalidCharacterRange(from: "\u{66}", to: "\u{65}"))

    diagnosticTest(#"[e\u{301}-e\u{302}]"#, .invalidCharacterRange(from: "\u{301}", to: "e"))

    diagnosticTest("(?x)[(?#)]", .expected("]"))
    diagnosticTest("(?x)[(?#abc)]", .expected("]"))

    diagnosticTest("(?x)[#]", .expectedCustomCharacterClassMembers, .expected("]"))
    diagnosticTest("(?x)[ # abc]", .expectedCustomCharacterClassMembers, .expected("]"))

    // MARK: Bad escapes

    diagnosticTest("\\", .expectedEscape)

    diagnosticTest(#"\o"#, .invalidEscape("o"))

    // TODO: Custom diagnostic for control sequence
    diagnosticTest(#"\c"#, .unexpectedEndOfInput)

    // TODO: Custom diagnostic for expected backref
    diagnosticTest(#"\g"#, .invalidEscape("g"))
    diagnosticTest(#"\k"#, .invalidEscape("k"))

    // TODO: Custom diagnostic for backref in custom char class
    diagnosticTest(#"[\g]"#, .invalidEscape("g"))
    diagnosticTest(#"[\g+30]"#, .invalidEscape("g"))
    diagnosticTest(#"[\g{1}]"#, .invalidEscape("g"))
    diagnosticTest(#"[\k'a']"#, .invalidEscape("k"))

    // TODO: Custom diagnostic for missing '\Q'
    diagnosticTest(#"\E"#, .invalidEscape("E"))

    diagnosticTest(#"[\Q\E]"#, .expectedNonEmptyContents)
    diagnosticTest(#"[\Q]"#, .expected("]"))

    // PCRE treats these as octal, but we require a `0` prefix.
    diagnosticTest(#"[\1]"#, .invalidEscape("1"))
    diagnosticTest(#"[\123]"#, .invalidEscape("1"))
    diagnosticTest(#"[\101]"#, .invalidEscape("1"))
    diagnosticTest(#"[\7777]"#, .invalidEscape("7"))
    diagnosticTest(#"[\181]"#, .invalidEscape("1"))

    // Backreferences are not valid in custom character classes.
    diagnosticTest(#"[\8]"#, .invalidEscape("8"))
    diagnosticTest(#"[\9]"#, .invalidEscape("9"))

    // Non-ASCII non-whitespace cases.
    diagnosticTest(#"\🔥"#, .invalidEscape("🔥"))
    diagnosticTest(#"\🇩🇰"#, .invalidEscape("🇩🇰"))
    diagnosticTest(#"\e\#u{301}"#, .invalidEscape("e\u{301}"))
    diagnosticTest(#"\\#u{E9}"#, .invalidEscape("é"))
    diagnosticTest(#"\˂"#, .invalidEscape("˂"))
    diagnosticTest(#"\d\#u{301}"#, .invalidEscape("d\u{301}"))

    // MARK: Confusable characters

    diagnosticTest("[\u{301}]", .confusableCharacter("[\u{301}"))
    diagnosticTest("(\u{358})", .confusableCharacter("(\u{358}"), .unbalancedEndOfGroup)
    diagnosticTest("{\u{35B}}", .confusableCharacter("{\u{35B}"))
    diagnosticTest(#"\\#u{35C}"#, .confusableCharacter(#"\\#u{35C}"#))
    diagnosticTest("^\u{35D}", .confusableCharacter("^\u{35D}"))
    diagnosticTest("$\u{35E}", .confusableCharacter("$\u{35E}"))
    diagnosticTest(".\u{35F}", .confusableCharacter(".\u{35F}"))
    diagnosticTest("|\u{360}", .confusableCharacter("|\u{360}"))
    diagnosticTest(" \u{361}", .confusableCharacter(" \u{361}"))

    // MARK: Interpolation (currently unsupported)

    diagnosticTest("<{}>", .unsupported("interpolation"))
    diagnosticTest("<{...}>", .unsupported("interpolation"))
    diagnosticTest("<{)}>", .unsupported("interpolation"))
    diagnosticTest("<{}}>", .unsupported("interpolation"))
    diagnosticTest("<{<{}>", .unsupported("interpolation"))
    diagnosticTest("(<{)}>", .expected(")"), .unsupported("interpolation"))

    // MARK: Character properties

    diagnosticTest(#"\p{Lx}"#, .unknownProperty(key: nil, value: "Lx"))
    diagnosticTest(#"\p{gcL}"#, .unknownProperty(key: nil, value: "gcL"))
    diagnosticTest(#"\p{x=y}"#, .unknownProperty(key: "x", value: "y"))
    diagnosticTest(#"\p{aaa(b)}"#, .unknownProperty(key: nil, value: "aaa(b)"))
    diagnosticTest("[[:a():]]", .unknownProperty(key: nil, value: "a()"))
    diagnosticTest(#"\p{aaa\p{b}}"#, .unknownProperty(key: nil, value: "aaa"), .expected("}"), .unknownProperty(key: nil, value: "b"))
    diagnosticTest(#"[[:{:]]"#, .unknownProperty(key: nil, value: "{"))

    diagnosticTest(#"\p{Basic_Latin}"#, .unknownProperty(key: nil, value: "Basic_Latin"))
    diagnosticTest(#"\p{Blk=In_Basic_Latin}"#, .unrecognizedBlock("In_Basic_Latin"))

    // We only filter pattern whitespace, which doesn't include things like
    // non-breaking spaces.
    diagnosticTest(#"\p{L\#u{A0}l}"#, .unknownProperty(key: nil, value: "L\u{A0}l"))

    // MARK: Matching options

    diagnosticTest("(?-y{g})", .cannotRemoveTextSegmentOptions, unsupported: true)
    diagnosticTest("(?-y{w})", .cannotRemoveTextSegmentOptions, unsupported: true)

    // FIXME: We need to figure out (?X) and (?u) semantics
    diagnosticTest("(?-X)", .cannotRemoveSemanticsOptions, unsupported: true)
    diagnosticTest("(?-u)", .cannotRemoveSemanticsOptions, unsupported: true)
    diagnosticTest("(?-b)", .cannotRemoveSemanticsOptions, unsupported: true)

    diagnosticTest("(?a)", .unknownGroupKind("?a"))

    // Extended syntax may not be removed in multi-line mode.
    diagnosticWithDelimitersTest("""
      #/
      (?-x)a b
      /#
      """, .cannotRemoveExtendedSyntaxInMultilineMode
    )
    diagnosticWithDelimitersTest("""
      #/
      (?-xx)a b
      /#
      """, .cannotRemoveExtendedSyntaxInMultilineMode
    )

    // Scoped removal of extended syntax may not span multiple lines
    diagnosticWithDelimitersTest("""
      #/
      (?-x:a b
      )
      /#
      """, .unsetExtendedSyntaxMayNotSpanMultipleLines
    )
    diagnosticWithDelimitersTest("""
      #/
      (?-x:a
      b)
      /#
      """, .unsetExtendedSyntaxMayNotSpanMultipleLines
    )
    diagnosticWithDelimitersTest("""
      #/
      (?-xx:
      a b)
      /#
      """, .unsetExtendedSyntaxMayNotSpanMultipleLines
    )
    diagnosticWithDelimitersTest("""
      #/
      (?x-x:
      a b)
      /#
      """, .unsetExtendedSyntaxMayNotSpanMultipleLines
    )
    diagnosticWithDelimitersTest("""
      #/
      (?^)
      # comment
      /#
      """, .cannotResetExtendedSyntaxInMultilineMode
    )
    diagnosticWithDelimitersTest("""
      #/
      (?^:
      # comment
      )
      /#
      """, .unsetExtendedSyntaxMayNotSpanMultipleLines
    )

    diagnosticWithDelimitersTest(#"""
      #/
      \Q
      \E
      /#
      """#, .quoteMayNotSpanMultipleLines)

    diagnosticWithDelimitersTest(#"""
      #/
        \Qabc
          \E
      /#
      """#, .quoteMayNotSpanMultipleLines)

    diagnosticWithDelimitersTest(#"""
      #/
        \Q
      /#
      """#, .quoteMayNotSpanMultipleLines)

    // .NET subtraction
    diagnosticWithDelimitersTest(#"""
      #/
      [
        a # interesting
        -   #a
         [ b] # comment
        ]
      /#
      """#, .unsupportedDotNetSubtraction)

    // MARK: Group specifiers

    diagnosticTest(#"(*"#, .expectedIdentifier(.onigurumaCalloutName), .expected(")"), unsupported: true)

    diagnosticTest(#"(?k)"#, .unknownGroupKind("?k"))
    diagnosticTest(#"(?P#)"#, .invalidMatchingOption("#"))

    diagnosticTest(#"(?<#>)"#, .identifierMustBeAlphaNumeric(.groupName))
    diagnosticTest(#"(?'1A')"#, .identifierCannotStartWithNumber(.groupName))

    // TODO: It might be better if tried to consume up to the closing `'` and
    // diagnosed an invalid group name based on that.
    diagnosticTest(#"(?'abc ')"#, .expected("'"))

    diagnosticTest("(?'🔥')", .identifierMustBeAlphaNumeric(.groupName))

    diagnosticTest(#"(?'-')"#, .expectedIdentifier(.groupName), unsupported: true)
    diagnosticTest(#"(?'--')"#, .identifierMustBeAlphaNumeric(.groupName), unsupported: true)
    diagnosticTest(#"(?'a-b-c')"#, .expected("'"), unsupported: true)

    diagnosticTest("(?x)(? : )", .unknownGroupKind("? "))

    diagnosticTest("(?<x>)(?<x>)", .duplicateNamedCapture("x"))
    diagnosticTest("(?<x>)|(?<x>)", .duplicateNamedCapture("x"))
    diagnosticTest("((?<x>))(?<x>)", .duplicateNamedCapture("x"))
    diagnosticTest("(|(?<x>))(?<x>)", .duplicateNamedCapture("x"))
    diagnosticTest("(?<x>)(?<y>)(?<x>)", .duplicateNamedCapture("x"))

    // MARK: Quantifiers

    diagnosticTest("*", .quantifierRequiresOperand("*"))
    diagnosticTest("+", .quantifierRequiresOperand("+"))
    diagnosticTest("?", .quantifierRequiresOperand("?"))
    diagnosticTest("*?", .quantifierRequiresOperand("*?"))
    diagnosticTest("{5}", .quantifierRequiresOperand("{5}"))
    diagnosticTest("{1,3}", .quantifierRequiresOperand("{1,3}"))
    diagnosticTest("a{3,2}", .invalidQuantifierRange(3, 2))

    diagnosticTest("{3, 5}", .quantifierRequiresOperand("{3, 5}"))
    diagnosticTest("{3 }", .quantifierRequiresOperand("{3 }"))

    // These are not quantifiable.
    diagnosticTest(#"\b?"#, .notQuantifiable)
    diagnosticTest(#"\B*"#, .notQuantifiable)
    diagnosticTest(#"\A+"#, .notQuantifiable)
    diagnosticTest(#"\Z??"#, .notQuantifiable)
    diagnosticTest(#"\G*?"#, .notQuantifiable)
    diagnosticTest(#"\z+?"#, .notQuantifiable)
    diagnosticTest(#"^*"#, .notQuantifiable)
    diagnosticTest(#"$?"#, .notQuantifiable)
    diagnosticTest(#"(?=a)+"#, .notQuantifiable)
    diagnosticTest(#"(?i)*"#, .notQuantifiable)
    diagnosticTest(#"\K{1}"#, .unsupported(#"'\K'"#), .notQuantifiable)
    diagnosticTest(#"\y{2,5}"#, .notQuantifiable)
    diagnosticTest(#"\Y{3,}"#, .notQuantifiable)

    // MARK: Unicode scalars

    diagnosticTest(#"\u{G}"#, .expectedNumber("G", kind: .hex))

    diagnosticTest(#"\u{"#, .expectedNumber("", kind: .hex), .expected("}"))
    diagnosticTest(#"\u{ "#, .expectedNumber("", kind: .hex), .expected("}"))
    diagnosticTest(#"\u{}"#, .expectedNumber("", kind: .hex))
    diagnosticTest(#"\u{ }"#, .expectedNumber("", kind: .hex))
    diagnosticTest(#"\u{  }"#, .expectedNumber("", kind: .hex))
    diagnosticTest(#"\u{ G}"#, .expectedNumber("G", kind: .hex))
    diagnosticTest(#"\u{G }"#, .expectedNumber("G", kind: .hex))
    diagnosticTest(#"\u{ G }"#, .expectedNumber("G", kind: .hex))
    diagnosticTest(#"\u{ GH }"#, .expectedNumber("GH", kind: .hex))
    diagnosticTest(#"\u{ G H }"#, .expectedNumber("G", kind: .hex), .expectedNumber("H", kind: .hex))
    diagnosticTest(#"\u{ ABC G }"#, .expectedNumber("G", kind: .hex))
    diagnosticTest(#"\u{ FFFFFFFFF A }"#, .numberOverflow("FFFFFFFFF"))

    diagnosticTest(#"[\d--\u{a b}]"#, .unsupported("scalar sequence in custom character class"))
    diagnosticTest(#"[\d--[\u{a b}]]"#, .unsupported("scalar sequence in custom character class"))

    diagnosticTest(#"\u12"#, .expectedNumDigits("12", 4))
    diagnosticTest(#"\U12"#, .expectedNumDigits("12", 8))
    diagnosticTest(#"\u{123456789}"#, .numberOverflow("123456789"))
    diagnosticTest(#"\x{123456789}"#, .numberOverflow("123456789"))

    // MARK: Matching options

    diagnosticTest(#"(?^-"#, .cannotRemoveMatchingOptionsAfterCaret, .expected(")"))
    diagnosticTest(#"(?^-)"#, .cannotRemoveMatchingOptionsAfterCaret)
    diagnosticTest(#"(?^i-"#, .cannotRemoveMatchingOptionsAfterCaret, .expected(")"))
    diagnosticTest(#"(?^i-m)"#, .cannotRemoveMatchingOptionsAfterCaret)
    diagnosticTest(#"(?i)?"#, .notQuantifiable)

    // MARK: References

    diagnosticTest(#"\k''"#, .expectedIdentifier(.groupName))
    diagnosticTest(#"(?&)"#, .expectedIdentifier(.groupName), unsupported: true)
    diagnosticTest(#"(?P>)"#, .expectedIdentifier(.groupName), unsupported: true)

    diagnosticTest(#"\g{0}"#, .cannotReferToWholePattern)
    diagnosticTest(#"(?(0))"#, .cannotReferToWholePattern, unsupported: true)

    diagnosticTest(#"(?&&)"#, .identifierMustBeAlphaNumeric(.groupName), unsupported: true)
    diagnosticTest(#"(?&-1)"#, .identifierMustBeAlphaNumeric(.groupName), unsupported: true)
    diagnosticTest(#"(?P>+1)"#, .identifierMustBeAlphaNumeric(.groupName), unsupported: true)
    diagnosticTest(#"(?P=+1)"#, .identifierMustBeAlphaNumeric(.groupName), unsupported: true)
    diagnosticTest(#"\k'#'"#, .identifierMustBeAlphaNumeric(.groupName), unsupported: true)
    diagnosticTest(#"(?&#)"#, .identifierMustBeAlphaNumeric(.groupName), unsupported: true)

    diagnosticTest(#"(?P>1)"#, .identifierCannotStartWithNumber(.groupName), unsupported: true)
    diagnosticTest(#"\k{1}"#, .identifierCannotStartWithNumber(.groupName), .invalidNamedReference("1"))

    diagnosticTest(#"\g<1-1>"#, .expected(">"), unsupported: true)
    diagnosticTest(#"\g{1-1}"#, .expected("}"), .invalidReference(1))
    diagnosticTest(#"\k{a-1}"#, .expected("}"), .invalidNamedReference("a"))
    diagnosticTest(#"\k{a-}"#, .expected("}"), .invalidNamedReference("a"))

    diagnosticTest(#"\k<a->"#, .expectedNumber("", kind: .decimal), .invalidNamedReference("a"))
    diagnosticTest(#"\k<1+>"#, .expectedNumber("", kind: .decimal), .invalidReference(1))
    diagnosticTest(#"()\k<1+1>"#, .unsupported("recursion level"))
    diagnosticTest(#"()\k<1-1>"#, .unsupported("recursion level"))

    diagnosticTest(#"\k<0>"#, .cannotReferToWholePattern)
    diagnosticTest(#"\1"#, .invalidReference(1))
    diagnosticTest(#"(?:)\1"#, .invalidReference(1))
    diagnosticTest(#"()\2"#, .invalidReference(2))
    diagnosticTest(#"\2()"#, .invalidReference(2))
    diagnosticTest(#"(?:)()\2"#, .invalidReference(2))
    diagnosticTest(#"(?:)(?:)\2"#, .invalidReference(2))

    diagnosticTest(#"\k<a>"#, .invalidNamedReference("a"))
    diagnosticTest(#"(?:)\k<a>"#, .invalidNamedReference("a"))
    diagnosticTest(#"()\k<a>"#, .invalidNamedReference("a"))
    diagnosticTest(#"()\k<a>()"#, .invalidNamedReference("a"))
    diagnosticTest(#"(?<b>)\k<a>()"#, .invalidNamedReference("a"))

    // MARK: Conditionals

    diagnosticTest(#"(?(1)a|b|c)"#, .tooManyBranchesInConditional(3), unsupported: true)
    diagnosticTest(#"(?(1)||)"#, .tooManyBranchesInConditional(3), unsupported: true)
    diagnosticTest(#"(?(?i))"#, .unknownGroupKind("?("))

    // MARK: Callouts

    // PCRE callouts
    diagnosticTest("(?C-1)", .unknownCalloutKind("(?C-1)"), unsupported: true)
    diagnosticTest("(?C-1", .unknownCalloutKind("(?C-1)"), .expected(")"), unsupported: true)

    // Oniguruma named callouts
    diagnosticTest("(*bar[", .expectedIdentifier(.onigurumaCalloutTag), .expected("]"), .expected(")"), unsupported: true)
    diagnosticTest("(*bar[%", .identifierMustBeAlphaNumeric(.onigurumaCalloutTag), .expected("]"), .expected(")"), unsupported: true)
    diagnosticTest("(*bar{", .expectedCalloutArgument, .expected("}"), .expected(")"), unsupported: true)
    diagnosticTest("(*bar}", .expected(")"), unsupported: true)
    diagnosticTest("(*bar]", .expected(")"), unsupported: true)

    // Oniguruma 'of contents' callouts
    diagnosticTest("(?{", .expected("}"), .expectedNonEmptyContents, .expected(")"), unsupported: true)
    diagnosticTest("(?{}", .expectedNonEmptyContents, .expected(")"), unsupported: true)
    diagnosticTest("(?{x}", .expected(")"), unsupported: true)
    diagnosticTest("(?{x}}", .expected(")"), unsupported: true)
    diagnosticTest("(?{{x}}", .expected(")"), unsupported: true)

    // TODO: We shouldn't be emitting both 'expected }' and 'expected }}' here.
    diagnosticTest("(?{{x}", .expected("}"), .expected("}}"), .expected(")"), unsupported: true)
    diagnosticTest("(?{x}[", .expectedIdentifier(.onigurumaCalloutTag), .expected("]"), .expected(")"), unsupported: true)
    diagnosticTest("(?{x}[%", .identifierMustBeAlphaNumeric(.onigurumaCalloutTag), .expected("]"), .expected(")"), unsupported: true)
    diagnosticTest("(?{x}[a]", .expected(")"), unsupported: true)
    diagnosticTest("(?{x}[a]K", .expected(")"), unsupported: true)
    diagnosticTest("(?{x}[a]X", .expected(")"), unsupported: true)
    diagnosticTest("(?{{x}y}", .expected("}"), .expected("}}"), .expected(")"), unsupported: true)

    // MARK: Backtracking directives

    diagnosticTest("(*MARK)", .backtrackingDirectiveMustHaveName("MARK"), unsupported: true)
    diagnosticTest("(*:)", .expectedNonEmptyContents, unsupported: true)
    diagnosticTest("(*MARK:a)?", .notQuantifiable, unsupported: true)
    diagnosticTest("(*FAIL)+", .notQuantifiable, unsupported: true)
    diagnosticTest("(*COMMIT:b)*", .notQuantifiable, unsupported: true)
    diagnosticTest("(*PRUNE:a)??", .notQuantifiable, unsupported: true)
    diagnosticTest("(*SKIP:a)*?", .notQuantifiable, unsupported: true)
    diagnosticTest("(*F)+?", .notQuantifiable, unsupported: true)
    diagnosticTest("(*:a){2}", .notQuantifiable, unsupported: true)

    // MARK: Oniguruma absent functions

    diagnosticTest("(?~", .expected(")"), unsupported: true)
    diagnosticTest("(?~|", .expected(")"), unsupported: true)
    diagnosticTest("(?~|a|b|c)", .tooManyAbsentExpressionChildren(3), unsupported: true)
    diagnosticTest("(?~||||)", .tooManyAbsentExpressionChildren(4), unsupported: true)

    // MARK: Global matching options

    diagnosticTest("a(*CR)", .globalMatchingOptionNotAtStart("(*CR)"))
    diagnosticTest("(*CR)a(*LF)", .globalMatchingOptionNotAtStart("(*LF)"), unsupported: true)
    diagnosticTest("(*LIMIT_HEAP)", .expected("="), .expectedNumber("", kind: .decimal), unsupported: true)
    diagnosticTest("(*LIMIT_DEPTH=", .expectedNumber("", kind: .decimal), .expected(")"), unsupported: true)

    // TODO: This diagnostic could be better.
    diagnosticTest("(*LIMIT_DEPTH=-1", .expectedNumber("", kind: .decimal), .expected(")"), unsupported: true)
  }

  func testDelimiterLexingErrors() {

    // MARK: Printable ASCII

    delimiterLexingDiagnosticTest(#"re'\\#n'"#, .unterminated)
    for i: UInt8 in 0x1 ..< 0x20 where i != 0xA && i != 0xD { // U+A & U+D are \n and \r.
      delimiterLexingDiagnosticTest("re'\(UnicodeScalar(i))'", .unprintableASCII)
    }
    delimiterLexingDiagnosticTest("re'\n'", .unterminated)
    delimiterLexingDiagnosticTest("re'\r'", .unterminated)
    delimiterLexingDiagnosticTest("re'\u{7F}'", .unprintableASCII)

    // MARK: Delimiter skipping

    delimiterLexingDiagnosticTest("re'(?''", .unterminated)
    delimiterLexingDiagnosticTest("re'(?'abc'", .unterminated)
    delimiterLexingDiagnosticTest("re'(?('abc'", .unterminated)
    delimiterLexingDiagnosticTest(#"re'\k'ab_c0+-'"#, .unterminated)
    delimiterLexingDiagnosticTest(#"re'\g'ab_c0+-'"#, .unterminated)

    // MARK: Unbalanced extended syntax
    delimiterLexingDiagnosticTest("#/a/", .unterminated)
    delimiterLexingDiagnosticTest("##/a/#", .unterminated)

    // MARK: Multiline

    // Can only be done if pound signs are used.
    delimiterLexingDiagnosticTest("/\n/", .unterminated)

    // Opening and closing delimiters must be on a newline.
    delimiterLexingDiagnosticTest("#/a\n/#", .unterminated)
    delimiterLexingDiagnosticTest("#/\na/#", .multilineClosingNotOnNewline)
    delimiterLexingDiagnosticTest("#/\n#/#", .multilineClosingNotOnNewline)
  }

  func testCompilerInterfaceDiagnostics() {
    compilerInterfaceDiagnosticMessageTest(
      "#/[x*/#", "cannot parse regular expression: expected ']'")
    compilerInterfaceDiagnosticMessageTest(
      "/a{3,2}/", "cannot parse regular expression: range lower bound '3' must be less than or equal to upper bound '2'")
    compilerInterfaceDiagnosticMessageTest(
      #"#/\u{}/#"#, "cannot parse regular expression: expected hexadecimal number")
  }

  func testParserFatalError() {
    do {
      var p = Parser(Source(""), syntax: .traditional)
      p.advance()
      try p.parse().ensureValid()
      XCTFail("Expected unreachable")
    } catch let err {
      if !"\(err)".hasPrefix("UNREACHABLE") {
        XCTFail("Expected unreachable \(err)")
      }
    }

    // Make sure fatal errors are preserved through lookaheads and backtracks.
    do {
      var p = Parser(Source(""), syntax: .traditional)
      p.lookahead { p in
        p.tryEating { p -> Void? in
          p.lookahead { p in
            p.advance()
            p.lookahead { _ in }
            p.tryEating { _ in }
          }
          return nil
        }
      }
      if p.diags.diags.count != 1 {
        XCTFail("Expected single fatal diagnostic")
      }
      try p.diags.throwAnyError()
      XCTFail("Expected unreachable")
    } catch let err {
      if !"\(err)".hasPrefix("UNREACHABLE") {
        XCTFail("Expected unreachable \(err)")
      }
    }
  }
}
