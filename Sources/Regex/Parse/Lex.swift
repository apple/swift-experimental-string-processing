/*

 Lexically, regular expressions are two langauges, one for inside
 a custom character class and one for outside.

 Outside of a custom character class, regexes have the following
 lexical structure:

 TODO

 Inside a custom character class:

 TODO

 Our currently-matched lexical structure of a regular expression:

 Regex     -> Token*
 Token     -> '\' Escaped | _SetOperator_ | Terminal
 Escaped   -> UniScalar | Terminal
 Terminal  -> `MetaCharacter` | `Character`

 UniScalar -> 'u{' HexDigit{1, 8}
            | 'u' HexDigit{4}
            | 'x{' HexDigit{1, 8}
            | 'x' HexDigit{2}
            | 'U' HexDigit{8}
 HexDigit  -> 0-9A-Fa-f

 _SetOperator_ is valid if we're inside a custom character set,
 otherwise it's just characters.

*/

/// The lexer produces a stream of `Token`s for the parser to consume
struct Lexer {
  var source: Source // TODO: fileprivate after diags

  /// The lexer manages a fixed-length buffer of tokens on behalf of the parser.
  /// Currently, the parser uses a lookahead of 1.
  ///
  /// We're choosing encapsulation here for our buffer-management strategy, as
  /// the lexer is at the end of the assembly line.
  fileprivate var nextTokenStorage: TokenStorage? = nil

  var nextToken: Token? {
    nextTokenStorage?.token
  }

  /// The number of parent custom character classes we're lexing within.
  ///
  /// Nested custom character classes are possible in some engines,
  /// and regex lexes differently inside and outside custom char classes.
  /// Tracking which language we're lexing is technically the job of the parser.
  /// But, we want the lexer to provide rich lexical information and let the parser
  /// just handle parsing. We could have a `setIsInCustomCC(_:Bool)` called by
  /// the parser, which would save/restore via the call stack, but it's
  /// far simpler to just have the lexer count the `[` and `]`s.
  fileprivate var customCharacterClassDepth = 0

  init(_ source: Source) { self.source = source }
}

// MARK: - Intramodule Programming Interface (IPI?)

extension Lexer: _Peekable {
  typealias Output = Token

  /// Whether we're done
  var isEmpty: Bool { nextToken == nil && source.isEmpty }

  /// Grab the next token without consuming it, if there is one
  mutating func peek() -> Token? {
    if let tok = nextToken { return tok }
    guard !source.isEmpty else { return nil }
    advance()
    return nextToken.unsafelyUnwrapped
  }

  mutating func advance() {
    nextTokenStorage = lexToken()
  }
}

// MARK: - Richer lexical analysis IPI

extension Lexer {
  mutating func tryConsumeNumber() -> Int? {
    func tryConsNum() -> Character? {
      switch peek() {
      case .character(let c, false)? where c.isNumber:
        eat()
        return c
      default: return nil
      }
    }

    var num = ""
    while let c = tryConsNum() { num.append(c) }

    guard !num.isEmpty else { return nil }

    guard let i = Int(num) else {
      fatalError("ERROR: overflow on \(num)")
    }
    return i
  }

  mutating func tryEatQuantification() -> Quantifier? {
    guard !isEmpty else { return nil }

    func consumeQuantKind() -> Quantifier.Kind {
      // TODO: possessive
      tryEat(.question) ? .reluctant : .greedy
    }

    // TODO: just lex directly, for now we bootstrap
    switch peek()! {
    case .star:
      eat()
      return .zeroOrMore(consumeQuantKind())
    case .plus:
      eat()
      return .oneOrMore(consumeQuantKind())
    case .question:
      eat()
      return .zeroOrOne(consumeQuantKind())
    case .leftCurlyBracket:
      // TODO: diagnostics
      eat()

      let lower = tryConsumeNumber()

      let closedRange: Bool?
      if tryEat(.comma) {
        closedRange = true
      } else if tryEat(.dot) {
        eat(asserting: .dot) // TODO: diagnose
        if tryEat(.dot) {
          closedRange = true
        } else if tryEat(.leftAngle) {
          closedRange = false
        } else {
          fatalError("TODO: diagnose bad range")
        }
      } else {
        closedRange = nil
      }

      let upper = tryConsumeNumber()
      eat(asserting: .rightCurlyBracket)
      let kind = consumeQuantKind()

      switch (lower, closedRange, upper) {
      case let (l?, nil, nil):
        return .exactly(kind, l)
      case let (l?, true, nil):
        return .nOrMore(kind, l)
      case let (l, false, nil) where l != nil:
        fatalError("TODO: diagnose 5..<")

      case let (nil, closed?, u?):
        return .upToN(kind, closed ? u : u-1)

      case let (l?, closed?, u?):
        return .range(kind, l...(closed ? u : u-1))

      case let (nil, nil, u) where u != nil:
        fatalError("Not possible")
      default:
        fatalError("TODO: diagnose")
      }

    default:
      return nil
    }
  }

  mutating func tryEatGroupStart() -> Group? {
    // TODO: just lex directly, for now we bootstrap
    guard tryEat(.leftParen) else { return nil }

    if tryEat(.question) {
      // (?:...)
      if tryEat(.colon) { return .nonCapture() }

      // (?|...)
      if tryEat(.pipe) { return .nonCaptureReset() }

      // (?>...)
      if tryEat(.rightAngle) { return .atomicNonCapturing() }

      // (?=...)
      if tryEat(.equals) { return .lookahead(inverted: false) }

      // (?!...)
      if tryEat(.character("!", isEscaped: false)) {
        return .lookahead(inverted: true)
      }

      func named(_ terminator: QuoteEnd) -> Group {
        // HACK HACK HACK
        let nameFirst: Character
        switch nextToken {
        case .character(let c, isEscaped: false):
          nameFirst = c
        default: fatalError("Fix the lexer...")
        }
        nextTokenStorage = nil

        // (?<name>...)
        let name = consumeQuoted(terminator)
        return .named("\(nameFirst)\(name)")        
      }

      if tryEat(.leftAngle) {
        // (?<=...)
        if tryEat(.equals) {
          return .lookbehind(inverted: false)
        }

        // (?<!...)
        if tryEat(.character("!", isEscaped: false)) {
          return .lookbehind(inverted: true)
        }

        // (?<name>...)
        return named(.rightAngle)
      }

      // (?'name'...)
      if tryEat(.character("'", isEscaped: false)) {
        return named(.singleQuote)
      }

      // (?P<name>...)
      if tryEat(.character("P", isEscaped: false)) {
        eat(asserting: .leftAngle)
        return named(.rightAngle)
      }

      fatalError("diagnostics")
    }

    // (_:), (name:)
    if syntax.contains(.modernCaptures) {
      // FIXME: this is ridiculous to do on top of
      // lookahead-1 tokens, and yet is purely lexical.
      // So, refactor lexical analysis soon...

      // TODO: `(name:)` on top of better analysis

      // (_:)
      if tryEat(.meta(.underscore)) {
        // FIXME: The lexer caching next token breaks the
        // ability for the lexer to know where in the input
        // it is reliably. We don't have "reset" points either,
        // though we could add those and take/reset tokens if
        // needed. We could have a way to save/restore lexical
        // state, but why not just have the lexer be sane
        // instead?

        if tryEat(.colon) {
          return .nonCapture()
        } else {
          fatalError("FIXME: information lost...")
        }
      }
    }

    return .capture()
  }

  /// Try to eat a token, throwing if we don't see what we're expecting.
  mutating func eat(expecting tok: Token) throws {
    guard tryEat(tok) else { throw "Expected \(tok)" }
  }

  /// Try to eat a token, asserting we saw what we expected
  mutating func eat(asserting tok: Token) {
    let expected = tryEat(tok)
    assert(expected)
  }

  /// TODO: Consider a variant that will produce the requested token, but also
  /// produce diagnostics/fixit if that's not what's really there.
}

// MARK: - Implementation

extension Lexer {
  var syntax: SyntaxOptions { source.syntax }

  private mutating func lexToken() -> TokenStorage? {
    guard !source.isEmpty else { return nil }

    let startLoc = source.currentLoc
    func tok(_ kind: Token) -> TokenStorage {
      TokenStorage(
        kind: kind,
        loc: startLoc..<source.currentLoc,
        fromCustomCharacterClass: isInCustomCharacterClass)
    }

    let current = source.eat()

    // Lex:  Token -> '\' Escaped | _SetOperator | Terminal
    if current.isEscape {
      return tok(consumeEscaped())
    }

    // `"` for modern quoting
    if syntax.contains(.modernQuotes), current == "\"" {
      return tok(.quote(consumeQuoted(.doubleQuote)))
    }

    // `(?#.` for comments, `/*` for modern comments
    if current == "(", source.tryEat(sequence: "?#.") {
      return tok(.comment(consumeQuoted(.rightParen)))
    }
    if syntax.contains(.modernComments),
       current == "/",
       source.tryEat("*")
    {
      return tok(.comment(consumeQuoted(.starSlash)))
    }

    if isInCustomCharacterClass,
       let op = tryConsumeSetOperator(current)
    {
      return tok(op)
    }

    // Track the custom character class depth. We can increment it every time
    // we see a `[`, and decrement every time we see a `]`, though we don't
    // decrement if we see `]` outside of a custom character class, as that
    // should be treated as a literal character.
    if current == "[" {
      customCharacterClassDepth += 1
    }
    if current == "]" && isInCustomCharacterClass {
      customCharacterClassDepth -= 1
    }

    return tok(classifyTerminal(current, fromEscape: false))
  }

  /// Whether the lexer is currently lexing within a custom character class.
  private var isInCustomCharacterClass: Bool {
    customCharacterClassDepth > 0
  }

  // TODO: plumb diagnostics
  private mutating func consumeEscaped() -> Token {
    assert(!source.isEmpty, "TODO: diagnostic for this")
    /*

    Escaped   -> UniScalar | Terminal
    UniScalar -> 'u{' HexDigit{1, 8}
               | 'u' HexDigit{4}
               | 'x{' HexDigit{1, 8}
               | 'x' HexDigit{2}
               | 'U' HexDigit{8}
    */
    switch source.eat() {
    case "u":
      return consumeUniScalar(
        allowBracketVariant: true, unbracketedNumDigits: 4)
    case "x":
      return consumeUniScalar(
        allowBracketVariant: true, unbracketedNumDigits: 2)
    case "U":
      return consumeUniScalar(
        allowBracketVariant: false, unbracketedNumDigits: 8)

    // Quoting
    case "Q":
      return .quote(consumeQuoted(.backE))
    case "E":
      // TODO: diagnostics
      fatalError("Error: End-quote without open quote")

    case let c:
      return classifyTerminal(c, fromEscape: true)
    }
  }

  // TODO: plumb diagnostic info
  private mutating func consumeUniScalar(
    allowBracketVariant: Bool,
    unbracketedNumDigits: Int
  ) -> Token {
    if allowBracketVariant, source.tryEat("{") {
      return .unicodeScalar(consumeBracketedUnicodeScalar())
    }
    return .unicodeScalar(consumeUnicodeScalar(
      digits: unbracketedNumDigits))
  }

  private mutating func consumeUnicodeScalar(
    digits digitCount: Int
  ) -> UnicodeScalar {
    var digits = ""
    for _ in digits.count ..< digitCount {
      assert(!source.isEmpty, "Exactly \(digitCount) hex digits required")
      digits.append(source.eat())
    }

    guard let value = UInt32(digits, radix: 16),
          let scalar = UnicodeScalar(value)
    else { fatalError("Invalid unicode sequence") }

    return scalar
  }

  private mutating func consumeBracketedUnicodeScalar() -> UnicodeScalar {
    var digits = ""
    // Eat a maximum of 9 characters, the last of which must be the terminator
    for _ in 0..<9 {
      assert(!source.isEmpty, "Unterminated unicode value")
      let next = source.eat()
      if next == "}" { break }
      digits.append(next)
      assert(digits.count <= 8, "Maximum 8 hex values required")
    }

    guard let value = UInt32(digits, radix: 16),
          let scalar = UnicodeScalar(value)
    else { fatalError("Invalid unicode sequence") }

    return scalar
  }

  private mutating func tryConsumeSetOperator(_ ch: Character) -> Token? {
    // Can only occur in a custom character class. Otherwise, the operator
    // characters are treated literally.
    assert(isInCustomCharacterClass)
    switch ch {
    case "-" where source.tryEat("-"):
      return .setOperator(.doubleDash)
    case "~" where source.tryEat("~"):
      return .setOperator(.doubleTilda)
    case "&" where source.tryEat("&"):
      return .setOperator(.doubleAmpersand)
    default:
      return nil
    }
  }

  // TODO: Probably just want to be string or character based...
  private enum QuoteEnd {
    case backE       // \E
    case doubleQuote // "
    case starSlash   // */
    case rightParen  // )
    case rightAngle  // >
    case singleQuote // '
  }

  // Consume a quoted or commented portion.
  private mutating func consumeQuoted(_ end: QuoteEnd) -> String {
    // FIXME: token-based is wrong, don't want escapes here...
    // In all of this I would write it against `source`, except
    // that `nextToken` cached screws that up.

    // FIXME: character classes for quoted content (e.g. named capture names
    // wouldn't have parenthesis, but \Q...\E can)

    // FIXME: But we have to backup...
    var result = ""
    while true {
      let c = source.eat()
      switch (end, c) {
      case (.doubleQuote, "\""):  return result
      case (.singleQuote, "'"):  return result
      case (.rightParen, ")"):    return result
      case (.rightAngle, ">"):    return result
      case (.backE, "\\") where source.tryEat("E"):
        return result
      case (.starSlash, "*") where source.tryEat("/"):
        return result
      default:
        result.append(c)
      }
    }
  }
}


// Can also be viewed as just a sequence of tokens. Useful for
// testing
extension Lexer: Sequence, IteratorProtocol {
  typealias Element = Token

  mutating func next() -> Element? {
    defer { advance() }
    return peek()
  }
}

extension Lexer {
  /// Classify a given terminal character
  func classifyTerminal(
    _ t: Character,
    fromEscape escaped: Bool
  ) -> Token {
    assert(!t.isEscape || escaped)
    if !escaped {
      // TODO: figure out best way to organize options logic...
      if syntax.ignoreWhitespace, t == " " {
        return .trivia
      }

      if let mc = Token.MetaCharacter(rawValue: t) {
        return .meta(mc)
      }
    }

    return .character(t, isEscaped: escaped)
  }
}
