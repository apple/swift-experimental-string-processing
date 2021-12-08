@testable import _MatchingEngine

import XCTest
@testable import _StringProcessing

extension AST: ExpressibleByExtendedGraphemeClusterLiteral {
  public typealias ExtendedGraphemeClusterLiteralType = Character
  public init(extendedGraphemeClusterLiteral value: Character) {
    self = .atom(.char(value))
  }
}
extension Atom: ExpressibleByExtendedGraphemeClusterLiteral {
  public typealias ExtendedGraphemeClusterLiteralType = Character
  public init(extendedGraphemeClusterLiteral value: Character) {
    self = .char(value)
  }
}
extension CustomCharacterClass.Member: ExpressibleByExtendedGraphemeClusterLiteral {
  public typealias ExtendedGraphemeClusterLiteralType = Character
  public init(extendedGraphemeClusterLiteral value: Character) {
    self = .atom(.char(value))
  }
}


class RegexTests: XCTestCase {}

func parseTest(
  _ input: String, _ expecting: AST,
  syntax: SyntaxOptions = .traditional
) {
  let orig = try! parse(input, syntax)
  let ast = orig.strippingTrivia!
  guard ast == expecting
          || ast._dump() == expecting._dump() // EQ workaround
  else {
    XCTFail("""

              Expected: \(expecting)
              Found:    \(ast)
              """)
    return
  }
}

extension RegexTests {
  func testParse() {
    parseTest(
      "abc", concat("a", "b", "c"))
    parseTest(
      #"abc\+d*"#,
      concat("a", "b", "c", "+", zeroOrMore(.greedy, "d")))
    parseTest(
      "a(b)", concat("a", capture("b")))
    parseTest(
      "abc(?:de)+fghi*k|j",
      alt(
        concat(
          "a", "b", "c",
          oneOrMore(
            .greedy, nonCapture(concat("d", "e"))),
          "f", "g", "h", zeroOrMore(.greedy, "i"), "k"),
        "j"))
    parseTest(
      "a(?:b|c)?d",
      concat("a", zeroOrOne(
        .greedy, nonCapture(alt("b", "c"))), "d"))
    parseTest(
      "a?b??c+d+?e*f*?",
      concat(
        zeroOrOne(.greedy, "a"), zeroOrOne(.reluctant, "b"),
        oneOrMore(.greedy, "c"), oneOrMore(.reluctant, "d"),
        zeroOrMore(.greedy, "e"), zeroOrMore(.reluctant, "f")))
    parseTest(
      "a|b?c",
      alt("a", concat(zeroOrOne(.greedy, "b"), "c")))
    parseTest(
      "(a|b)c",
      concat(capture(alt("a", "b")), "c"))
    parseTest(
      "(.)*(.*)",
      concat(
        zeroOrMore(.greedy, capture(.any)),
        capture(zeroOrMore(.greedy, .any))))
    parseTest(
      #"abc\d"#,
      concat("a", "b", "c", .atom(.escaped(.decimalDigit))))
    parseTest(
      #"a\u0065b\u{00000065}c\x65d\U00000065"#,
      concat("a", .atom(.scalar("e")),
             "b", .atom(.scalar("e")),
             "c", .atom(.scalar("e")),
             "d", .atom(.scalar("e"))))

    parseTest(
      "[-|$^:?+*())(*-+-]",
      charClass(
        "-", "|", "$", "^", ":", "?", "+", "*", "(", ")", ")",
        "(", .range("*", "+"), "-"))

    parseTest(
      "[a-b-c]", charClass(.range("a", "b"), "-", "c"))

    parseTest("[-a-]", charClass("-", "a", "-"))

    parseTest("[a-z]", charClass(.range("a", "z")))

    parseTest("[a-d--a-c]", charClass(
      .setOperation([.range("a", "d")], .subtraction, [.range("a", "c")])
    ))

    parseTest("[-]", charClass("-"))

    // These are metacharacters in certain contexts, but normal characters
    // otherwise.
    parseTest(
      ":-]", concat(":", "-", "]"))

    parseTest(
      "[^abc]", charClass("a", "b", "c", inverted: true))
    parseTest(
      "[a^]", charClass("a", "^"))

    parseTest(
      #"\D\S\W"#,
      concat(
        .atom(.escaped(.notDecimalDigit)),
        .atom(.escaped(.notWhitespace)),
        .atom(.escaped(.notWordCharacter))))

    parseTest(
      #"[\dd]"#, charClass(.atom(.escaped(.decimalDigit)), "d"))

    parseTest(
      #"[^[\D]]"#,
      charClass(charClass(.atom(.escaped(.notDecimalDigit))),
                inverted: true))
    parseTest(
      "[[ab][bc]]",
      charClass(charClass("a", "b"), charClass("b", "c")))
    parseTest(
      "[[ab]c[de]]",
      charClass(charClass("a", "b"), "c", charClass("d", "e")))

    typealias POSIX = Atom.POSIXSet
    parseTest(#"[ab[:space:]\d[:^upper:]cd]"#,
              charClass("a", "b", .atom(posixSet(.space)),
                        .atom(.escaped(.decimalDigit)),
                        .atom(posixSet(.upper, inverted: true)), "c", "d"))

    parseTest("[[[:space:]]]",
              charClass(charClass(.atom(posixSet(.space)))))

    parseTest(
      #"[a[bc]de&&[^bc]\d]+"#,
      oneOrMore(.greedy, charClass(
        .setOperation(
          ["a", charClass("b", "c"), "d", "e"],
          .intersection,
          [charClass("b", "c", inverted: true), .atom(.escaped(.decimalDigit))]
        ))))

    parseTest(
      "[a&&b]",
      charClass(
        .setOperation(["a"], .intersection, ["b"])))

    parseTest(
      "[abc--def]",
      charClass(.setOperation(["a", "b", "c"], .subtraction, ["d", "e", "f"])))

    // We left-associate for chained operators.
    parseTest(
      "[ab&&b~~cd]",
      charClass(
        .setOperation(
          [.setOperation(["a", "b"], .intersection, ["b"])],
          .symmetricDifference,
          ["c", "d"])))

    // Operators are only valid in custom character classes.
    parseTest(
      "a&&b", concat("a", "&", "&", "b"))
    parseTest(
      "&?", zeroOrOne(.greedy, "&"))
    parseTest(
      "&&?", concat("&", zeroOrOne(.greedy, "&")))
    parseTest(
      "--+", concat("-", oneOrMore(.greedy, "-")))
    parseTest(
      "~~*", concat("~", zeroOrMore(.greedy, "~")))

    parseTest(
      #"a\Q .\Eb"#,
      concat("a", .quote(" ."), "b"))
    parseTest(
      #"a\Q \Q \\.\Eb"#,
      concat("a", .quote(#" \Q \\."#), "b"))

    parseTest(
      #"a(?#. comment)b"#,
      concat("a", "b"))

    parseTest(
      #"a{1,2}"#,
      .quantification(.range(.greedy, 1...2), "a"))
    parseTest(
      #"a{,2}"#,
      .quantification(.upToN(.greedy, 2), "a"))
    parseTest(
      #"a{1,}"#,
      .quantification(.nOrMore(.greedy, 1), "a"))
    parseTest(
      #"a{1}"#,
      .quantification(.exactly(.greedy, 1), "a"))
    parseTest(
      #"a{1,2}?"#,
      .quantification(.range(.reluctant, 1...2), "a"))

    // Named captures
    parseTest(
      #"a(?<label>b)c"#,
      concat("a", namedCapture("label", "b"), "c"))
    parseTest(
      #"a(?'label'b)c"#,
      concat("a", namedCapture("label", "b"), "c"))
    parseTest(
      #"a(?P<label>b)c"#,
      concat("a", namedCapture("label", "b"), "c"))
    parseTest(
      #"a(?P<label>b)c"#,
      concat("a", namedCapture("label", "b"), "c"))

    // Other groups
    parseTest(
      #"a(?:b)c"#,
      concat("a", nonCapture("b"), "c"))
    parseTest(
      #"a(?|b)c"#,
      concat("a", nonCaptureReset("b"), "c"))
    parseTest(
      #"a(?>b)c"#,
      concat("a", atomicNonCapturing("b"), "c"))



    // TODO: failure tests
  }

  func testParseErrors() {

    func performErrorTest(_ input: String, _ expecting: String) {
      //      // Quick pattern match against AST to extract error nodes
      //      let ast = parse2(input)
      //      print(ast)
    }

    performErrorTest("(", "")


  }

}

