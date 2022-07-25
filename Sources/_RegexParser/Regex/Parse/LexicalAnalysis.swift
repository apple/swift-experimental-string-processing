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

/*

Lexical analysis aids parsing by handling local ("lexical")
concerns upon request.

API convention:

- lexFoo will try to consume a foo and return it if successful, otherwise returns nil
- expectFoo will consume a foo, diagnosing an error if unsuccessful
*/

extension Parser {
  typealias Located = Source.Located
  typealias Location = Source.Location
  typealias LocatedError = Source.LocatedError
  typealias Char = Source.Char

  // MARK: - recordLoc

  /// Attach a source location to the parsed contents of a given function.
  fileprivate mutating func recordLoc<T>(
    _ f: (inout Self) -> T
  ) -> Located<T> {
    let start = src.currentPosition
    let result = f(&self)
    return Located(result, loc(start))
  }

  /// Attach a source location to the parsed contents of a given function.
  fileprivate mutating func recordLoc<T>(
    _ f: (inout Self) -> T?
  ) -> Located<T>? {
    let start = src.currentPosition
    guard let result = f(&self) else { return nil }
    return Located(result, loc(start))
  }

  /// Attach a source location to the parsed contents of a given function.
  @discardableResult
  fileprivate mutating func recordLoc(
    _ f: (inout Self) -> ()
  ) -> SourceLocation {
    let start = src.currentPosition
    f(&self)
    return loc(start)
  }
}

// MARK: Backtracking routines

extension Parser {
  /// Attempt to make a series of lexing steps in `body`, returning `nil` if
  /// unsuccesful, which will revert the parser back to its previous state.
  mutating func tryEating<T>(
    _ body: (inout Self) -> T?
  ) -> T? {
    var current = self
    guard let result = body(&self) else {
      // Fatal errors are always preserved.
      current.diags.appendNewFatalErrors(from: diags)
      self = current
      return nil
    }
    return result
  }

  /// Perform a lookahead using a temporary source. Within the body of the
  /// lookahead, any modifications to the source will not be reflected outside
  /// the body.
  mutating func lookahead<T>(_ body: (inout Self) -> T) -> T {
    var p = self
    let result = body(&p)
    // Fatal errors are always preserved.
    diags.appendNewFatalErrors(from: p.diags)
    return result
  }
}

// MARK: - Consumption routines
extension Parser {
  typealias Quant = AST.Quantification

  /// Expect to eat a given character, diagnosing an error and returning
  /// `false` if unsuccessful, `true` otherwise.
  @discardableResult
  mutating func expect(_ c: Character) -> Bool {
    guard tryEat(c) else {
      errorAtCurrentPosition(.expected(String(c)))
      return false
    }
    return true
  }

  /// Same as `expect`, but with a source location.
  mutating func expectWithLoc(_ c: Character) -> Located<Bool> {
    recordLoc {
      $0.expect(c)
    }
  }

  /// Expect to eat a sequence of characters, diagnosing an error and returning
  /// `false` if unsuccessful, `true` otherwise.
  @discardableResult
  mutating func expect<C: Collection>(
    sequence c: C
  ) -> Bool where C.Element == Character {
    guard tryEat(sequence: c) else {
      errorAtCurrentPosition(.expected(String(c)))
      return false
    }
    return true
  }

  /// Diagnoses an error and returns `false` if the end of input has been
  /// reached. Otherwise returns `true`.
  @discardableResult
  mutating func expectNonEmpty(
    _ error: ParseError = .unexpectedEndOfInput
  ) -> Bool {
    guard !src.isEmpty else {
      errorAtCurrentPosition(error)
      return false
    }
    return true
  }

  /// Attempt to eat a sequence of characters, additionally diagnosing if the
  /// end of the source has been reached.
  mutating func tryEatNonEmpty<C: Collection>(
    sequence c: C
  ) -> Bool where C.Element == Char {
    expectNonEmpty(.expected(String(c))) && tryEat(sequence: c)
  }

  /// Returns the next character, or `nil` if the end of the source has been
  /// reached.
  func peek() -> Char? { src.peek() }

  /// Same as `peek()`, but with the source location of the next character.
  func peekWithLoc() -> Located<Char>? {
    peek().map { c in
      let nextPos = src.input.index(after: src.currentPosition)
      return Located(c, Location(src.currentPosition ..< nextPos))
    }
  }

  /// Advance the input `n` characters ahead.
  mutating func advance(_ n: Int = 1) {
    guard src.tryAdvance(n) else {
      unreachable("Advancing beyond end!")

      // Empty out the remaining characters.
      src.tryAdvance(src._slice.count)
      return
    }
  }

  /// Try to eat any character, returning `nil` if the input has been exhausted.
  mutating func tryEat() -> Char? {
    guard let char = peek() else { return nil }
    advance()
    return char
  }

  /// Same as `tryEat()`, but with the source location of the eaten character.
  mutating func tryEatWithLoc() -> Located<Char>? {
    recordLoc { $0.tryEat() }
  }

  /// Attempt to eat the given character, returning `true` if successful,
  /// `false` otherwise.
  mutating func tryEat(_ c: Char) -> Bool {
    guard peek() == c else { return false }
    advance()
    return true
  }

  /// Attempt to eat the given character, returning its source location if
  /// successful, `nil` otherwise.
  mutating func tryEatWithLoc(_ c: Character) -> SourceLocation? {
    let start = src.currentPosition
    guard tryEat(c) else { return nil }
    return .init(start ..< src.currentPosition)
  }

  /// Attempt to eat a character if it matches a given predicate, returning
  /// `true` if the character was eaten, or `false` if the character did not
  /// meet the predicate.
  mutating func tryEat(where pred: (Char) -> Bool) -> Bool {
    guard let next = peek(), pred(next) else { return false }
    advance()
    return true
  }

  /// Attempt to eat a sequence of characters, returning `true` if successful.
  mutating func tryEat<C: Collection>(
    sequence c: C
  ) -> Bool where C.Element == Char {
    guard src.starts(with: c) else { return false }
    advance(c.count)
    return true
  }

  /// Attempt to eat any of the given characters, returning the one that was
  /// eaten.
  mutating func tryEat<C: Collection>(
    anyOf set: C
  ) -> Char? where C.Element == Char {
    guard let c = peek(), set.contains(c) else { return nil }
    advance()
    return c
  }

  /// Attempt to eat any of the given characters, returning the one that was
  /// eaten.
  mutating func tryEat(anyOf set: Char...) -> Char? {
    tryEat(anyOf: set)
  }

  /// Eat up to `count` characters, returning the range of characters eaten.
  mutating func eat(upToCount count: Int) -> Located<String> {
    recordLoc { $0.src.eat(upToCount: count).string }
  }

  /// Attempt to eat a given prefix that satisfies a given predicate, with the
  /// source location recorded.
  mutating func tryEatPrefix(
    maxLength: Int? = nil,
    _ f: (Char) -> Bool
  ) -> Located<String>? {
    recordLoc { $0.src.tryEatPrefix(maxLength: maxLength, f)?.string }
  }

  /// Attempts to eat an ASCII value, diagnosing an error and returning `nil`
  /// if unsuccessful.
  mutating func expectASCII() -> Located<Character>? {
    recordLoc { p in
      guard let c = p.tryEat() else {
        p.errorAtCurrentPosition(.unexpectedEndOfInput)
        return nil
      }
      guard c.isASCII else {
        p.errorAtCurrentPosition(.expectedASCII(c))
        return nil
      }
      return c
    }
  }
}

enum RadixKind {
  case octal, decimal, hex

  var characterFilter: (Character) -> Bool {
    switch self {
    case .octal:   return \.isOctalDigit
    case .decimal: return \.isNumber
    case .hex:     return \.isHexDigit
    }
  }
  var radix: Int {
    switch self {
    case .octal:   return 8
    case .decimal: return 10
    case .hex:     return 16
    }
  }
}

enum IdentifierKind {
  case groupName
  case onigurumaCalloutName
  case onigurumaCalloutTag
}

extension Parser {
  /// Validate a string of digits as a particular radix, and return the number,
  /// or diagnose an error if the string is malformed or would overflow the
  /// number type.
  private mutating func validateNumber<Num: FixedWidthInteger>(
    _ locStr: Located<String>, _: Num.Type, _ kind: RadixKind
  ) -> Num? {
    let str = locStr.value
    guard !str.isEmpty && str.all(kind.characterFilter) else {
      error(.expectedNumber(str, kind: kind), at: locStr.location)
      return nil
    }
    guard let i = Num(str, radix: kind.radix) else {
      error(.numberOverflow(str), at: locStr.location)
      return nil
    }
    return i
  }

  /// Validate a string of digits as a unicode scalar of a particular radix, and
  /// return the scalar value, or diagnose an error if the string is malformed
  /// or would overflow the scalar.
  private mutating func validateUnicodeScalar(
    _ str: Source.Located<String>, _ kind: RadixKind
  ) -> AST.Atom.Scalar {
    func nullScalar() -> AST.Atom.Scalar {
      // For now, return a null scalar in the case of an error. This should be
      // benign as it shouldn't affect other validation logic.
      // TODO: Should we store nil like we do with regular numbers?
      return .init(UnicodeScalar(0), str.location)
    }
    guard let num = validateNumber(str, UInt32.self, kind) else {
      return nullScalar()
    }
    guard let scalar = Unicode.Scalar(num) else {
      error(.misc("Invalid scalar value U+\(num.hexStr)"), at: str.location)
      return nullScalar()
    }
    return .init(scalar, str.location)
  }

  /// Try to eat a number of a particular type and radix off the front.
  ///
  /// Returns: `nil` if there's no number, otherwise the number
  ///
  /// Diagnoses on overflow
  ///
  mutating func lexNumber(_ kind: RadixKind = .decimal) -> AST.Atom.Number? {
    guard let str = tryEatPrefix(kind.characterFilter) else {
      return nil
    }
    guard let i = Int(str.value, radix: kind.radix) else {
      error(.numberOverflow(str.value), at: str.location)
      return .init(nil, at: str.location)
    }
    return .init(i, at: str.location)
  }

  /// Expect a number of a given `kind`, diagnosing if a number cannot be
  /// parsed.
  mutating func expectNumber(_ kind: RadixKind = .decimal) -> AST.Atom.Number {
    guard let num = lexNumber(kind) else {
      errorAtCurrentPosition(.expectedNumber("", kind: kind))
      return .init(nil, at: loc(src.currentPosition))
    }
    return num
  }

  /// Eat a scalar value from hexadecimal notation off the front
  mutating func expectUnicodeScalar(numDigits: Int) -> AST.Atom.Scalar {
    let str = recordLoc { p -> String in
      let str = p.eat(upToCount: numDigits)
      if str.value.count != numDigits {
        p.error(.expectedNumDigits(str.value, numDigits), at: str.location)
      }
      return str.value
    }
    return validateUnicodeScalar(str, .hex)
  }

  /// Try to lex a seqence of hex digit unicode scalars.
  ///
  ///     UniScalarSequence   -> Whitespace? UniScalarSequencElt+
  ///     UniScalarSequencElt -> HexDigit{1...} Whitespace?
  ///
  mutating func expectUnicodeScalarSequence(
    eating ending: Character
  ) -> AST.Atom.Kind {
    var scalars = [AST.Atom.Scalar]()
    var trivia = [AST.Trivia]()

    // Eat up any leading whitespace.
    if let t = lexWhitespace() { trivia.append(t) }

    while true {
      let str = lexUntil { p in
        // Hit the ending, stop lexing.
        if p.src.isEmpty || p.peek() == ending {
          return true
        }
        // Eat up trailing whitespace, and stop lexing to record the scalar.
        if let t = p.lexWhitespace() {
          trivia.append(t)
          return true
        }
        // Not the ending or trivia, must be a digit of the scalar.
        return false
      }
      guard !str.value.isEmpty else { break }
      scalars.append(validateUnicodeScalar(str, .hex))
    }
    expect(ending)

    if scalars.isEmpty {
      errorAtCurrentPosition(.expectedNumber("", kind: .hex))
      return .scalar(.init(UnicodeScalar(0), loc(src.currentPosition)))
    }
    if scalars.count == 1 {
      return .scalar(scalars[0])
    }
    return .scalarSequence(.init(scalars, trivia: trivia))
  }

  /// Try to eat a scalar off the front, starting from after the backslash and
  /// base character (e.g. `\u` or `\x`).
  ///
  ///     UniScalar -> 'u{' UniScalarSequence '}'
  ///                | 'u'  HexDigit{4}
  ///                | 'x{' HexDigit{1...} '}'
  ///                | 'x'  HexDigit{0...2}
  ///                | 'U'  HexDigit{8}
  ///                | 'o{' OctalDigit{1...} '}'
  ///                | '0' OctalDigit{0...3}
  ///
  mutating func lexUnicodeScalar() -> AST.Atom.Kind? {
    tryEating { p in

      func nullScalar() -> AST.Atom.Scalar {
        .init(UnicodeScalar(0), p.loc(p.src.currentPosition))
      }

      // TODO: PCRE offers a different behavior if PCRE2_ALT_BSUX is set.
      switch p.tryEat() {
        // Hex numbers.
      case "u" where p.tryEat("{"):
        return p.expectUnicodeScalarSequence(eating: "}")

      case "x" where p.tryEat("{"):
        let str = p.lexUntil(eating: "}")
        return .scalar(p.validateUnicodeScalar(str, .hex))

      case "x":
        // \x expects *up to* 2 digits.
        guard let digits = p.tryEatPrefix(maxLength: 2, \.isHexDigit)
        else {
          // In PCRE, \x without any valid hex digits is \u{0}.
          // TODO: This doesn't appear to be followed by ICU or Oniguruma, so
          // could be changed to diagnose an error if we had a parsing mode for
          // them.
          return .scalar(nullScalar())
        }
        return .scalar(p.validateUnicodeScalar(digits, .hex))

      case "u":
        return .scalar(p.expectUnicodeScalar(numDigits: 4))
      case "U":
        return .scalar(p.expectUnicodeScalar(numDigits: 8))

        // Octal numbers.
      case "o" where p.tryEat("{"):
        let str = p.lexUntil(eating: "}")
        return .scalar(p.validateUnicodeScalar(str, .octal))

      case "0":
        // We can read *up to* 3 more octal digits.
        // FIXME: PCRE can only read up to 2 octal digits, if we get a strict
        // PCRE mode, we should limit it here.
        guard let digits = p.tryEatPrefix(maxLength: 3, \.isOctalDigit)
        else {
          return .scalar(nullScalar())
        }
        return .scalar(p.validateUnicodeScalar(digits, .octal))

      default:
        return nil
      }
    }
  }

  /// Try to consume a quantifier
  ///
  ///     Quantifier -> ('*' | '+' | '?' | '{' Range '}') QuantKind?
  ///     QuantKind  -> '?' | '+'
  ///
  mutating func lexQuantifier(
  ) -> (Located<Quant.Amount>, Located<Quant.Kind>, [AST.Trivia])? {
    tryEating { p in
      var trivia: [AST.Trivia] = []

      if let t = p.lexNonSemanticWhitespace() { trivia.append(t) }

      let amt: Located<Quant.Amount>? = p.recordLoc { p in
        if p.tryEat("*") { return .zeroOrMore }
        if p.tryEat("+") { return .oneOrMore }
        if p.tryEat("?") { return .zeroOrOne }

        return p.tryEating { p in
          guard p.tryEat("{"),
                let range = p.lexRange(trivia: &trivia),
                p.tryEat("}")
          else { return nil }
          return range.value
        }
      }
      guard let amt = amt else { return nil }

      // PCRE allows non-semantic whitespace here in extended syntax mode.
      if let t = p.lexNonSemanticWhitespace() { trivia.append(t) }

      let kind: Located<Quant.Kind> = p.recordLoc { p in
        if p.tryEat("?") { return .reluctant  }
        if p.tryEat("+") { return .possessive }
        return .eager
      }

      return (amt, kind, trivia)
    }
  }

  /// Try to consume a range, returning `nil` if unsuccessful.
  ///
  ///     Range       -> ',' <Int> | <Int> ',' <Int>? | <Int>
  ///                  | ExpRange
  ///     ExpRange    -> '..<' <Int> | '...' <Int>
  ///                  | <Int> '..<' <Int> | <Int> '...' <Int>?
  mutating func lexRange(trivia: inout [AST.Trivia]) -> Located<Quant.Amount>? {
    recordLoc { p in
      p.tryEating { p in
        if let t = p.lexWhitespace() { trivia.append(t) }

        let lowerOpt = p.lexNumber()

        if let t = p.lexWhitespace() { trivia.append(t) }

        // ',' or '...' or '..<' or nothing
        let closedRange: Bool?
        if p.tryEat(",") {
          closedRange = true
        } else if p.context.experimentalRanges && p.tryEat(".") {
          p.expect(".")
          if p.tryEat(".") {
            closedRange = true
          } else {
            p.expect("<")
            closedRange = false
          }
        } else {
          closedRange = nil
        }

        if let t = p.lexWhitespace() { trivia.append(t) }

        var upperOpt = p.lexNumber()
        if closedRange == false {
          // If we have an open range, the upper bound should be adjusted down.
          upperOpt?.value? -= 1
        }

        if let t = p.lexWhitespace() { trivia.append(t) }

        switch (lowerOpt, closedRange, upperOpt) {
        case let (l?, nil, nil):
          return .exactly(l)
        case let (l?, true, nil):
          return .nOrMore(l)
        case let (nil, _?, u?):
          return .upToN(u)
        case let (l?, _?, u?):
          return .range(l, u)

        case (nil, nil, _?):
          p.unreachable("Didn't lex lower bound, but lexed upper bound?")
          return nil
        default:
          return nil
        }
      }
    }
  }

  private mutating func lexUntil(
    _ predicate: (inout Self) -> Bool
  ) -> Located<String> {
    // We track locations without using recordLoc, as the predicate may advance
    // the input when we hit the end, and we don't want that to affect the
    // location of what was lexed in the `result`.
    // TODO: We should find a better way of doing this, `lexUntil` seems full
    // of footguns.
    let start = src.currentPosition
    var end = src.currentPosition
    var result = ""
    while !predicate(&self), let c = tryEat() {
      result.append(c)
      end = src.currentPosition
    }
    return .init(result, start ..< end)
  }

  private mutating func lexUntil(eating end: String) -> Located<String> {
    lexUntil { $0.tryEatNonEmpty(sequence: end) }
  }

  private mutating func lexUntil(
    eating end: Character
  ) -> Located<String> {
    lexUntil(eating: String(end))
  }

  /// Expect a linear run of non-nested non-empty content ending with a given
  /// delimiter. If `ignoreEscaped` is true, escaped characters will not be
  /// considered for the ending delimiter.
  private mutating func expectQuoted(
    endingWith endSingle: String, count: Int = 1, ignoreEscaped: Bool = false,
    eatEnding: Bool = true
  ) -> Located<String> {
    let end = String(repeating: endSingle, count: count)
    let result = recordLoc { p -> String in
      p.lexUntil { p in
        if p.src.starts(with: end) {
          return true
        }
        guard p.expectNonEmpty(.expected(endSingle)) else { return true }

        // Ignore escapes if we're allowed to. lexUntil will consume the next
        // character.
        if ignoreEscaped, p.tryEat("\\") {
          guard p.expectNonEmpty(.expectedEscape) else { return true }
        }
        return false
      }.value
    }
    if result.value.isEmpty {
      error(.expectedNonEmptyContents, at: result.location)
    }
    if eatEnding {
      expect(sequence: end)
    }
    return result
  }

  /// Try to consume quoted content
  ///
  ///     Quote -> '\Q' (!'\E' .)* '\E'?
  ///
  /// With `SyntaxOptions.experimentalQuotes`, also accepts
  ///
  ///     ExpQuote -> '"' ('\"' | [^"])* '"'
  ///
  /// Future: Experimental quotes are full fledged Swift string literals
  ///
  /// TODO: Need to support some escapes
  ///
  mutating func lexQuote() -> AST.Quote? {
    let str = recordLoc { p -> String? in
      if p.tryEat(sequence: #"\Q"#) {
        let contents = p.lexUntil { p in
          p.src.isEmpty || p.tryEat(sequence: #"\E"#)
        }

        // In multi-line literals, the quote may not span multiple lines.
        if p.context.syntax.contains(.multilineCompilerLiteral),
           contents.value.spansMultipleLinesInRegexLiteral {
          p.error(.quoteMayNotSpanMultipleLines, at: contents.location)
        }

        // The sequence must not be empty in a custom character class.
        if p.context.isInCustomCharacterClass && contents.value.isEmpty {
          p.error(.expectedNonEmptyContents, at: contents.location)
        }
        return contents.value
      }
      if p.context.experimentalQuotes, p.tryEat("\"") {
        // TODO: Can experimental quotes be empty?
        return p.expectQuoted(endingWith: "\"", ignoreEscaped: true).value
      }
      return nil
    }
    guard let str = str else { return nil }
    return AST.Quote(str.value, str.location)
  }

  /// Try to consume an interpolation sequence.
  ///
  ///     Interpolation -> '<{' String '}>'
  ///
  mutating func lexInterpolation() -> AST.Interpolation? {
    let contents = recordLoc { p -> String? in
      p.tryEating { p in
        guard p.tryEat(sequence: "<{") else { return nil }
        let contents = p.lexUntil { $0.src.isEmpty || $0.src.starts(with: "}>") }
        guard p.tryEat(sequence: "}>") else { return nil }
        return contents.value
      }
    }
    guard let contents = contents else { return nil }
    return .init(contents.value, contents.location)
  }

  /// Try to consume a comment
  ///
  ///     Comment -> '(?#' [^')']* ')'
  ///
  /// With `SyntaxOptions.experimentalComments`
  ///
  ///     ExpComment -> '/*' (!'*/' .)* '*/'
  ///
  /// With `SyntaxOptions.endOfLineComments`
  ///
  ///     EndOfLineComment -> '#' .*
  ///
  /// TODO: Swift-style nested comments, line-ending comments, etc
  ///
  mutating func lexComment() -> AST.Trivia? {
    let trivia: Located<String>? = recordLoc { p in
      if !p.context.isInCustomCharacterClass && p.tryEat(sequence: "(?#") {
        return p.lexUntil(eating: ")").value
      }
      if p.context.experimentalComments, p.tryEat(sequence: "/*") {
        return p.lexUntil(eating: "*/").value
      }
      if p.context.endOfLineComments, p.tryEat("#") {
        // Try eat until we either exhaust the input, or hit a newline. Note
        // that the definition of newline can be altered depending on the global
        // matching options. By default we consider a newline to be `\n` or
        // `\r`.
        return p.lexUntil { p in
          if p.src.isEmpty { return true }
          switch p.context.newlineMode {
          case .carriageReturnOnly:
            return p.tryEat("\r")
          case .linefeedOnly:
            return p.tryEat("\n")
          case .carriageAndLinefeedOnly:
            return p.tryEat("\r\n")
          case .anyCarriageReturnOrLinefeed:
            return p.tryEat(anyOf: "\r", "\n", "\r\n") != nil
          case .anyUnicode:
            return p.tryEat(where: \.isNewline)
          case .nulCharacter:
            return p.tryEat("\0")
          }
        }.value
      }
      return nil
    }
    guard let trivia = trivia else { return nil }
    return AST.Trivia(trivia)
  }

  /// Try to consume non-semantic whitespace as trivia
  ///
  ///     Whitespace -> WhitespaceChar+
  ///
  /// Does nothing unless `SyntaxOptions.nonSemanticWhitespace` is set
  mutating func lexNonSemanticWhitespace() -> AST.Trivia? {
    guard context.ignoreWhitespace else { return nil }

    // FIXME: PCRE only treats space and tab characters as whitespace when
    // inside a custom character class (and only treats whitespace as
    // non-semantic there for the extra-extended `(?xx)` mode). If we get a
    // strict-PCRE mode, we'll need to add a case for that.
    return lexWhitespace()
  }

  /// Try to consume whitespace as trivia
  ///
  ///     Whitespace -> WhitespaceChar+
  ///
  /// Unlike `lexNonSemanticWhitespace`, this will always attempt to lex
  /// whitespace.
  mutating func lexWhitespace() -> AST.Trivia? {
    guard let trivia = tryEatPrefix(\.isPatternWhitespace) else { return nil }
    return AST.Trivia(trivia)
  }

  /// Try to consume trivia.
  ///
  ///     Trivia -> Comment | Whitespace
  ///
  mutating func lexTrivia() -> AST.Trivia? {
    if let comment = lexComment() {
      return comment
    }
    if let whitespace = lexNonSemanticWhitespace() {
      return whitespace
    }
    return nil
  }

  /// Try to lex a matching option.
  ///
  ///     MatchingOption -> 'i' | 'J' | 'm' | 'n' | 's' | 'U' | 'x' | 'xx' | 'w'
  ///                     | 'D' | 'P' | 'S' | 'W' | 'y{' ('g' | 'w') '}'
  ///
  mutating func lexMatchingOption() -> AST.MatchingOption? {
    typealias OptKind = AST.MatchingOption.Kind

    let locOpt = recordLoc { p -> OptKind? in
      p.tryEating { p in
        guard let c = p.tryEat() else { return nil }
        switch c {
        // PCRE options.
        case "i": return .caseInsensitive
        case "J": return .allowDuplicateGroupNames
        case "m": return .multiline
        case "n": return .namedCapturesOnly
        case "s": return .singleLine
        case "U": return .reluctantByDefault
        case "x":
          return p.tryEat("x") ? .extraExtended : .extended

        // ICU options.
        case "w": return .unicodeWordBoundaries

        // Oniguruma options.
        case "D": return .asciiOnlyDigit
        case "P": return .asciiOnlyPOSIXProps
        case "S": return .asciiOnlySpace
        case "W": return .asciiOnlyWord
        case "y":
          // Default to grapheme cluster if unknown.
          let recoveryMode = OptKind.textSegmentGraphemeMode
          guard p.expect("{") else { return recoveryMode }

          guard let optChar = p.tryEatWithLoc(), optChar.value != "}" else {
            p.errorAtCurrentPosition(.expected("text segment mode"))
            return recoveryMode
          }
          let opt: OptKind
          switch optChar.value {
          case "w":
            opt = .textSegmentWordMode
          case "g":
            opt = .textSegmentGraphemeMode
          case let x:
            p.error(.unknownTextSegmentMatchingOption(x), at: optChar.location)
            opt = recoveryMode
          }
          p.expect("}")
          return opt

        // Swift semantic level options
        case "X": return .graphemeClusterSemantics
        case "u": return .unicodeScalarSemantics
        case "b": return .byteSemantics

        default:
          return nil
        }
      }
    }
    guard let locOpt = locOpt else { return nil }
    return .init(locOpt.value, location: locOpt.location)
  }

  /// Try to lex a sequence of matching options.
  ///
  ///     MatchingOptionSeq -> '^' MatchingOption* | MatchingOption+
  ///                        | MatchingOption* '-' MatchingOption*
  ///
  mutating func lexMatchingOptionSequence() -> AST.MatchingOptionSequence? {
    // PCRE accepts '(?)'
    // TODO: This is a no-op, should we warn?
    if peek() == ")" {
      return .init(caretLoc: nil, adding: [], minusLoc: nil, removing: [])
    }
    let caret = tryEatWithLoc("^")

    // TODO: Warn on duplicate options, and options appearing in both adding
    // and removing lists?
    var adding: [AST.MatchingOption] = []
    while let opt = lexMatchingOption() {
      adding.append(opt)
    }

    // Try to lex options to remove.
    var removing: [AST.MatchingOption] = []
    let minus = tryEatWithLoc("-")
    if minus != nil {
      if let caret = caret {
        // Options cannot be removed if '^' is used.
        error(.cannotRemoveMatchingOptionsAfterCaret, at: caret)
      }
      while let opt = lexMatchingOption() {
        // Text segment options can only be added, they cannot be removed
        // with (?-), they should instead be set to a different mode.
        if opt.isTextSegmentMode {
          error(.cannotRemoveTextSegmentOptions, at: opt.location)
        }
        // Matching semantics options can only be added, not removed.
        if opt.isSemanticMatchingLevel {
          error(.cannotRemoveSemanticsOptions, at: opt.location)
        }
        removing.append(opt)
      }
    }
    // We must have lexed at least something to proceed.
    guard caret != nil || minus != nil || !adding.isEmpty else { return nil }
    return .init(
      caretLoc: caret, adding: adding, minusLoc: minus, removing: removing)
  }

  /// A matching option changing atom.
  ///
  ///     '(?' MatchingOptionSeq ')'
  ///
  mutating func lexChangeMatchingOptionAtom() -> AST.MatchingOptionSequence? {
    tryEating { p in
      guard p.tryEat(sequence: "(?"), let seq = p.lexMatchingOptionSequence()
      else { return nil }
      p.expect(")")
      return seq
    }
  }

  /// Try to consume explicitly spelled-out PCRE2 group syntax.
  mutating func lexExplicitPCRE2GroupStart() -> AST.Group.Kind? {
    tryEating { p in
      guard p.tryEat(sequence: "(*") else { return nil }

      if p.tryEat(sequence: "atomic:") {
        return .atomicNonCapturing
      }
      if p.tryEat(sequence: "pla:") ||
          p.tryEat(sequence: "positive_lookahead:") {
        return .lookahead
      }
      if p.tryEat(sequence: "nla:") ||
          p.tryEat(sequence: "negative_lookahead:") {
        return .negativeLookahead
      }
      if p.tryEat(sequence: "plb:") ||
          p.tryEat(sequence: "positive_lookbehind:") {
        return .lookbehind
      }
      if p.tryEat(sequence: "nlb:") ||
          p.tryEat(sequence: "negative_lookbehind:") {
        return .negativeLookbehind
      }
      if p.tryEat(sequence: "napla:") ||
          p.tryEat(sequence: "non_atomic_positive_lookahead:") {
        return .nonAtomicLookahead
      }
      if p.tryEat(sequence: "naplb:") ||
          p.tryEat(sequence: "non_atomic_positive_lookbehind:") {
        return .nonAtomicLookbehind
      }
      if p.tryEat(sequence: "sr:") || p.tryEat(sequence: "script_run:") {
        return .scriptRun
      }
      if p.tryEat(sequence: "asr:") ||
          p.tryEat(sequence: "atomic_script_run:") {
        return .atomicScriptRun
      }
      return nil
    }
  }

  /// Consume an identifier.
  ///
  ///     Identifier -> [\w--\d] \w*
  ///
  private mutating func expectIdentifier(
    _ kind: IdentifierKind, endingWith ending: String, eatEnding: Bool = true
  ) -> Located<String> {
    let str = recordLoc { p -> String in
      guard !p.src.isEmpty && !p.src.starts(with: ending) else {
        p.errorAtCurrentPosition(.expectedIdentifier(kind))
        return ""
      }
      let firstChar = p.peekWithLoc()!
      if firstChar.value.isNumber {
        p.error(.identifierCannotStartWithNumber(kind), at: firstChar.location)
      }
      guard let str = p.tryEatPrefix(\.isWordCharacter) else {
        p.error(.identifierMustBeAlphaNumeric(kind), at: firstChar.location)
        // Try skip ahead to the closing delimiter for better recovery.
        _ = p.lexUntil { $0.src.isEmpty || $0.src.starts(with: ending) }
        return ""
      }
      return str.value
    }
    if eatEnding {
      expect(sequence: ending)
    }
    return str
  }

  /// Consume a named group field, producing either a named capture or balanced
  /// capture.
  ///
  ///     NamedGroup    -> 'P<' GroupNameBody '>'
  ///                    | '<' GroupNameBody '>'
  ///                    | "'" GroupNameBody "'"
  ///     GroupNameBody -> Identifier | Identifier? '-' Identifier
  ///
  private mutating func expectNamedGroup(
    endingWith ending: String
  ) -> AST.Group.Kind {
    func lexBalanced(_ lhs: Located<String>? = nil) -> AST.Group.Kind? {
      // If we have a '-', this is a .NET-style 'balanced group'.
      guard let dash = tryEatWithLoc("-") else { return nil }
      let rhs = expectIdentifier(.groupName, endingWith: ending)
      return .balancedCapture(.init(name: lhs, dash: dash, priorName: rhs))
    }

    // Lex a group name, trying to lex a '-rhs' for a balanced capture group
    // both before and after.
    if let b = lexBalanced() { return b }
    let name = expectIdentifier(
      .groupName, endingWith: ending, eatEnding: false
    )
    if let b = lexBalanced(name) { return b }

    expect(sequence: ending)
    return .namedCapture(name)
  }

  /// Try to consume the start of a group
  ///
  ///     GroupStart -> '(?' GroupKind | '('
  ///     GroupKind  -> ':' | '|' | '>' | '=' | '!' | '*' | '<=' | '<!' | '<*'
  ///                 | NamedGroup | MatchingOptionSeq (':' | ')')
  ///
  /// If `SyntaxOptions.experimentalGroups` is enabled, also accepts:
  ///
  ///     ExpGroupStart -> '(_:'
  ///
  /// Future: Named groups of the form `(name: ...)`
  ///
  /// Note: we exclude comments from being `Group`s, since
  /// they do not nest: they parse like quotes. They actually
  /// need to be parsed earlier than the group check, as
  /// comments, like quotes, cannot be quantified.
  ///
  mutating func lexGroupStart() -> Located<AST.Group.Kind>? {
    recordLoc { p in
      p.tryEating { p in
        // Explicitly spelled out PRCE2 syntax for some groups. This needs to be
        // done before group-like atoms, as it uses the '(*' syntax, which is
        // otherwise a group-like atom.
        if let g = p.lexExplicitPCRE2GroupStart() { return g }

        // There are some atoms that syntactically look like groups, bail here
        // if we see any. Care needs to be taken here as e.g a group starting
        // with '(?-' is a subpattern if the next character is a digit,
        // otherwise a matching option specifier. Conversely, '(?P' can be the
        // start of a matching option sequence, or a reference if it is followed
        // by '=' or '<'.
        guard !p.shouldLexGroupLikeAtom() else { return nil }

        guard p.tryEat("(") else { return nil }
        if p.tryEat("?") {
          if p.tryEat(":") { return .nonCapture }
          if p.tryEat("|") { return .nonCaptureReset }
          if p.tryEat(">") { return .atomicNonCapturing }
          if p.tryEat("=") { return .lookahead }
          if p.tryEat("!") { return .negativeLookahead }
          if p.tryEat("*") { return .nonAtomicLookahead }

          if p.tryEat(sequence: "<=") { return .lookbehind }
          if p.tryEat(sequence: "<!") { return .negativeLookbehind }
          if p.tryEat(sequence: "<*") { return .nonAtomicLookbehind }

          // Named
          if p.tryEat("<") || p.tryEat(sequence: "P<") {
            return p.expectNamedGroup(endingWith: ">")
          }
          if p.tryEat("'") {
            return p.expectNamedGroup(endingWith: "'")
          }

          // Matching option changing group (?iJmnsUxxxDPSWy{..}-iJmnsUxxxDPSW:).
          if let seq = p.lexMatchingOptionSequence() {
            if !p.tryEat(":") {
              if let next = p.peekWithLoc() {
                p.error(.invalidMatchingOption(next.value), at: next.location)
              } else {
                p.errorAtCurrentPosition(.expected(")"))
              }
            }
            return .changeMatchingOptions(seq)
          }

          if let next = p.peekWithLoc() {
            p.error(.unknownGroupKind("?\(next.value)"), at: next.location)
          } else {
            p.errorAtCurrentPosition(.expectedGroupSpecifier)
          }
          return .nonCapture
        }

        // (_:)
        if p.context.experimentalCaptures && p.tryEat(sequence: "_:") {
          return .nonCapture
        }
        // TODO: (name:)

        // If (?n) is set, a bare (...) group is non-capturing.
        if p.context.syntax.contains(.namedCapturesOnly) {
          return .nonCapture
        }
        return .capture
      }
    }
  }

  /// Consume a PCRE version number.
  ///
  ///     PCREVersionNumber -> <Int>.<Int>
  ///
  private mutating func expectPCREVersionNumber(
  ) -> AST.Conditional.Condition.PCREVersionNumber {
    let nums = recordLoc { p -> (major: AST.Atom.Number,
                                 minor: AST.Atom.Number) in
      let major = p.expectNumber()
      p.expect(".")
      let minor = p.expectNumber()
      return (major, minor)
    }
    return .init(major: nums.value.major, minor: nums.value.minor,
                 nums.location)
  }

  /// Consume a PCRE version check suffix.
  ///
  ///     PCREVersionCheck -> '>'? '=' PCREVersionNumber
  ///
  private mutating func expectPCREVersionCheck(
  ) -> AST.Conditional.Condition.Kind {
    typealias Kind = AST.Conditional.Condition.PCREVersionCheck.Kind
    let kind = recordLoc { p -> Kind in
      let greaterThan = p.tryEat(">")
      p.expect("=")
      return greaterThan ? .greaterThanOrEqual : .equal
    }
    return .pcreVersionCheck(.init(kind, expectPCREVersionNumber()))
  }

  /// Try to lex a known condition (excluding group conditions).
  ///
  ///     KnownCondition -> 'R'
  ///                     | 'R' NumberRef
  ///                     | 'R&' <String> !')'
  ///                     | '<' NameRef '>'
  ///                     | "'" NameRef "'"
  ///                     | 'DEFINE'
  ///                     | 'VERSION' VersionCheck
  ///                     | NumberRef
  ///                     | NameRef
  ///
  private mutating func lexKnownCondition() -> AST.Conditional.Condition? {
    typealias ConditionKind = AST.Conditional.Condition.Kind

    let kind = recordLoc { p -> ConditionKind? in
      p.tryEating { p in

        // PCRE recursion check.
        if p.tryEat("R") {
          if p.tryEat("&") {
            return .groupRecursionCheck(
              p.expectNamedReference(endingWith: ")", eatEnding: false))
          }
          if let num = p.lexNumber() {
            return .groupRecursionCheck(
              .init(.absolute(num), innerLoc: num.location))
          }
          return .recursionCheck
        }

        if let open = p.tryEat(anyOf: "<", "'") {
          // In PCRE, this can only be a named reference. In Oniguruma, it can
          // also be a numbered reference.
          let closing = String(p.getClosingDelimiter(for: open))
          return .groupMatched(
            p.expectNamedOrNumberedReference(endingWith: closing))
        }

        // PCRE group definition and version check.
        if p.tryEat(sequence: "DEFINE") {
          return .defineGroup
        }
        if p.tryEat(sequence: "VERSION") {
          return p.expectPCREVersionCheck()
        }

        // If we have a numbered reference, this is a check to see if a group
        // matched. Oniguruma also permits a recursion level here.
        if let num = p.lexNumberedReference(allowRecursionLevel: true) {
          return .groupMatched(num)
        }

        // PCRE and .NET also allow a named reference to be parsed here. PCRE
        // always treats it as a named reference, whereas .NET only treats it
        // as such if a group exists with that name. For now, just check if a
        // prior group exists with that name.
        // FIXME: This should apply to future groups too.
        // TODO: We should probably advise users to use the more explicit
        // syntax.
        let nameRef = p.lexNamedReference(
          endingWith: ")", eatEnding: false, allowRecursionLevel: true)
        if let nameRef = nameRef, p.context.isPriorGroupRef(nameRef.kind) {
          return .groupMatched(nameRef)
        }
        return nil
      }
    }
    guard let kind = kind else { return nil }
    return .init(kind.value, kind.location)
  }

  /// Attempt to lex a known conditional start (excluding group conditions).
  ///
  ///     KnownConditionalStart -> '(?(' KnownCondition ')'
  ///
  mutating func lexKnownConditionalStart() -> AST.Conditional.Condition? {
    tryEating { p in
      guard p.tryEat(sequence: "(?("), let cond = p.lexKnownCondition()
      else { return nil }
      p.expect(")")
      return cond
    }
  }

  /// Attempt to lex the start of a group conditional.
  ///
  ///     GroupCondStart -> '(?' GroupStart
  ///
  mutating func lexGroupConditionalStart() -> Located<AST.Group.Kind>? {
    tryEating { p in
      guard p.tryEat(sequence: "(?") else { return nil }
      return p.lexGroupStart()
    }
  }

  /// Try to consume the start of an absent function.
  ///
  ///     AbsentFunctionStart -> '(?~' '|'?
  ///
  mutating func lexAbsentFunctionStart(
  ) -> Located<AST.AbsentFunction.Start>? {
    recordLoc { p in
      if p.tryEat(sequence: "(?~|") { return .withPipe }
      if p.tryEat(sequence: "(?~") { return .withoutPipe }
      return nil
    }
  }

  mutating func lexCustomCCStart() -> Located<CustomCC.Start>? {
    recordLoc { p in
      // Make sure we don't have a POSIX character property. This may require
      // walking to its ending to make sure we have a closing ':]', as otherwise
      // we have a custom character class.
      // TODO: This behavior seems subtle, could we warn?
      guard !p.canLexPOSIXCharacterProperty() else {
        return nil
      }
      if p.tryEat("[") {
        return p.tryEat("^") ? .inverted : .normal
      }
      return nil
    }
  }

  /// Try to consume a binary operator from within a custom character class
  ///
  ///     CustomCCBinOp -> '--' | '~~' | '&&'
  ///
  mutating func lexCustomCCBinOp() -> Located<CustomCC.SetOp>? {
    recordLoc { p in
      // TODO: Perhaps a syntax options check (!PCRE)
      // TODO: Better AST types here
      guard let binOp = p.peekCCBinOp() else { return nil }
      p.expect(sequence: binOp.rawValue)
      return binOp
    }
  }

  // Check to see if we can lex a binary operator.
  func peekCCBinOp() -> CustomCC.SetOp? {
    if src.starts(with: "--") { return .subtraction }
    if src.starts(with: "~~") { return .symmetricDifference }
    if src.starts(with: "&&") { return .intersection }
    return nil
  }

  /// Check to see if we can lex a .NET subtraction. Returns the
  /// location of the `-`.
  ///
  ///     DotNetSubtraction -> Trivia* '-' Trivia* CustomCharClass
  ///
  mutating func canLexDotNetCharClassSubtraction() -> SourceLocation? {
    lookahead { p in
      // We can lex '-' as a .NET subtraction if it precedes a custom character
      // class.
      while p.lexTrivia() != nil {}
      guard let dashLoc = p.tryEatWithLoc("-") else { return nil }
      while p.lexTrivia() != nil {}
      guard p.lexCustomCCStart() != nil else { return nil }
      return dashLoc
    }
  }

  private mutating func lexPOSIXCharacterProperty(
  ) -> Located<AST.Atom.CharacterProperty>? {
    recordLoc { p in
      p.tryEating { p in
        guard p.tryEat(sequence: "[:") else { return nil }
        let inverted = p.tryEat("^")

        // Note we lex the contents and ending *before* classifying, because we
        // want to bail with nil if we don't have the right ending. This allows
        // the lexing of a custom character class if we don't have a ':]'
        // ending.
        let (key, value) = p.lexCharacterPropertyKeyValue()
        guard p.tryEat(sequence: ":]") else { return nil }

        let prop = p.classifyCharacterPropertyContents(key: key, value: value)
        return .init(prop, isInverted: inverted, isPOSIX: true)
      }
    }
  }

  private mutating func canLexPOSIXCharacterProperty() -> Bool {
    lookahead { $0.lexPOSIXCharacterProperty() != nil }
  }

  /// Try to consume a named character.
  ///
  ///     NamedCharacter -> '\N{' CharName '}'
  ///     CharName -> 'U+' HexDigit{1...8} | [\s\w-]+
  ///
  private mutating func lexNamedCharacter() -> Located<AST.Atom.Kind>? {
    recordLoc { p in
      guard p.tryEat(sequence: "N{") else { return nil }

      // We should either have a unicode scalar.
      if p.tryEat(sequence: "U+") {
        let str = p.lexUntil(eating: "}")
        return .scalar(p.validateUnicodeScalar(str, .hex))
      }

      // Or we should have a character name.
      // TODO: Validate the types of characters that can appear in the name?
      return .namedCharacter(p.lexUntil(eating: "}").value)
    }
  }

  private mutating func lexCharacterPropertyKeyValue(
  ) -> (key: Located<String>?, value: Located<String>) {
    func atPossibleEnding(_ p: inout Self) -> Bool {
      guard let next = p.peek() else { return true }
      switch next {
      case "=":
        // End of a key.
        return true
      case ":", "[", "]":
        // POSIX character property endings to cover ':]', ']', and '[' as the
        // start of a nested character class.
        return true
      case "}":
        // Ending of '\p{'. We cover this for POSIX too as it's not a valid
        // character property name anyway, and it's nice not to have diverging
        // logic for these cases.
        return true
      case "\\":
        // An escape sequence, which may include e.g '\Q :] \E'. ICU bails here
        // for all its known escape sequences (e.g '\a', '\e' '\f', ...). It
        // seems character class escapes e.g '\d' are excluded, however it's not
        // clear that is intentional. Let's apply the rule for any escape, as a
        // backslash would never be a valid character property name, and we can
        // diagnose any invalid escapes when parsing as a character class.
        return true
      default:
        // We may want to handle other metacharacters here, e.g '{', '(', ')',
        // as they're not valid character property names. However for now
        // let's tend on the side of forming an unknown property name in case
        // these characters are ever used in future character property names
        // (though it's very unlikely). Users can always escape e.g the ':'
        // in '[:' if they definitely want a custom character class.
        return false
      }
    }
    // We should either have:
    // - 'x=y' where 'x' is a property key, and 'y' is a value.
    // - 'y' where 'y' is a value (or a bool key with an inferred value of true)
    //   and its key is inferred.
    let lhs = lexUntil(atPossibleEnding)
    if tryEat("=") {
      let rhs = lexUntil(atPossibleEnding)
      return (lhs, rhs)
    }
    return (nil, lhs)
  }

  private mutating func classifyCharacterPropertyContents(
    key: Located<String>?, value: Located<String>
  ) -> AST.Atom.CharacterProperty.Kind {
    if let key = key {
      return classifyCharacterProperty(key: key, value: value)
    }
    return classifyCharacterPropertyValueOnly(value)
  }

  /// Try to consume a character property.
  ///
  ///     Property -> ('p{' | 'P{') Prop ('=' Prop)? '}'
  ///     Prop -> [\s\w-]+
  ///
  private mutating func lexCharacterProperty(
  ) -> Located<AST.Atom.CharacterProperty>? {
    recordLoc { p in
      // '\P{...}' is the inverted version of '\p{...}'
      guard p.src.starts(with: "p{") || p.src.starts(with: "P{") else {
        return nil
      }
      let isInverted = p.peek() == "P"
      p.advance(2)

      let (key, value) = p.lexCharacterPropertyKeyValue()
      let prop = p.classifyCharacterPropertyContents(key: key, value: value)
      p.expect("}")
      return .init(prop, isInverted: isInverted, isPOSIX: false)
    }
  }

  /// Try to lex an absolute or relative numbered reference.
  ///
  ///     NumberRef -> ('+' | '-')? <Decimal Number> RecursionLevel?
  ///
  private mutating func lexNumberedReference(
    allowWholePatternRef: Bool = false, allowRecursionLevel: Bool = false
  ) -> AST.Reference? {
    let kind = recordLoc { p -> AST.Reference.Kind? in
      p.tryEating { p in
        // Note this logic should match canLexNumberedReference.
        if let plus = p.tryEatWithLoc("+"), let num = p.lexNumber() {
          return .relative(.init(num.value, at: num.location.union(with: plus)))
        }
        if let minus = p.tryEatWithLoc("-"), let num = p.lexNumber() {
          let val = num.value.map { x in -x }
          return .relative(.init(val, at: num.location.union(with: minus)))
        }
        if let num = p.lexNumber() {
          return .absolute(num)
        }
        return nil
      }
    }
    guard let kind = kind else { return nil }
    if !allowWholePatternRef && kind.value.recursesWholePattern {
      error(.cannotReferToWholePattern, at: kind.location)
    }
    let recLevel = allowRecursionLevel ? lexRecursionLevel() : nil
    let loc = recLevel?.location.union(with: kind.location) ?? kind.location
    return .init(kind.value, recursionLevel: recLevel, innerLoc: loc)
  }

  /// Try to consume a recursion level for a group reference.
  ///
  ///     RecursionLevel -> '+' <Int> | '-' <Int>
  ///
  private mutating func lexRecursionLevel(
  ) -> AST.Atom.Number? {
    let value = recordLoc { p -> Int? in
      if p.tryEat("+") { return p.expectNumber().value }
      if p.tryEat("-") { return p.expectNumber().value.map { x in -x } }
      return nil
    }
    guard let value = value else { return nil }
    return .init(value.value, at: value.location)
  }

  /// Checks whether a numbered reference can be lexed.
  private mutating func canLexNumberedReference() -> Bool {
    lookahead { p in
      _ = p.tryEat(anyOf: "+", "-")
      guard let next = p.peek() else { return false }
      return RadixKind.decimal.characterFilter(next)
    }
  }

  /// Eat a named reference up to a given closing delimiter.
  private mutating func expectNamedReference(
    endingWith end: String, eatEnding: Bool = true,
    allowRecursionLevel: Bool = false
  ) -> AST.Reference {
    // Note we don't want to eat the ending as we may also want to parse a
    // recursion level.
    let str = expectIdentifier(
      .groupName, endingWith: end, eatEnding: false)

    // If we're allowed to, parse a recursion level.
    let recLevel = allowRecursionLevel ? lexRecursionLevel() : nil
    let loc = recLevel?.location.union(with: str.location) ?? str.location

    if eatEnding {
      expect(sequence: end)
    }
    return .init(.named(str.value), recursionLevel: recLevel, innerLoc: loc)
  }

  /// Try to consume a named reference up to a closing delimiter, returning
  /// `nil` if the characters aren't valid for a named reference.
  private mutating func lexNamedReference(
    endingWith end: String, eatEnding: Bool = true,
    allowRecursionLevel: Bool = false
  ) -> AST.Reference? {
    tryEating { p in
      p.expectNamedReference(
        endingWith: end, eatEnding: eatEnding,
        allowRecursionLevel: allowRecursionLevel
      )
    }
  }

  /// Try to lex a numbered reference, or otherwise a named reference.
  ///
  ///     NameOrNumberRef -> NumberRef | <String>
  ///
  private mutating func expectNamedOrNumberedReference(
    endingWith ending: String, eatEnding: Bool = true,
    allowWholePatternRef: Bool = false, allowRecursionLevel: Bool = false
  ) -> AST.Reference {
    let num = lexNumberedReference(
      allowWholePatternRef: allowWholePatternRef,
      allowRecursionLevel: allowRecursionLevel
    )
    if let num = num {
      if eatEnding {
        expect(sequence: ending)
      }
      return num
    }
    return expectNamedReference(
      endingWith: ending, eatEnding: eatEnding,
      allowRecursionLevel: allowRecursionLevel
    )
  }

  private mutating func getClosingDelimiter(
    for openChar: Character
  ) -> Character {
    switch openChar {
      // Identically-balanced delimiters.
    case "'", "\"", "`", "^", "%", "#", "$": return openChar
    case "<": return ">"
    case "{": return "}"
    default:
      unreachable("Unhandled case")
      return openChar
    }
  }

  /// Lex an escaped reference for a backreference or subpattern.
  ///
  ///     EscapedReference -> 'g{' NameOrNumberRef '}'
  ///                       | 'g<' NameOrNumberRef '>'
  ///                       | "g'" NameOrNumberRef "'"
  ///                       | 'g' NumberRef
  ///                       | 'k<' <String> '>'
  ///                       | "k'" <String> "'"
  ///                       | 'k{' <String> '}'
  ///                       | [1-9] [0-9]+
  ///
  private mutating func lexEscapedReference() -> Located<AST.Atom.Kind>? {
    recordLoc { p in
      p.tryEating { p in
        guard let firstChar = p.peek() else { return nil }

        if p.tryEat("g") {
          // PCRE-style backreferences.
          if p.tryEat("{") {
            let ref = p.expectNamedOrNumberedReference(endingWith: "}")
            return .backreference(ref)
          }

          // Oniguruma-style subpatterns.
          if let openChar = p.tryEat(anyOf: "<", "'") {
            let closing = String(p.getClosingDelimiter(for: openChar))
            return .subpattern(p.expectNamedOrNumberedReference(
              endingWith: closing, allowWholePatternRef: true))
          }

          // PCRE allows \g followed by a bare numeric reference.
          if let ref = p.lexNumberedReference() {
            return .backreference(ref)
          }
          return nil
        }

        if p.tryEat("k") {
          // Perl/.NET/Oniguruma-style backreferences.
          if let openChar = p.tryEat(anyOf: "<", "'") {
            let closing = String(p.getClosingDelimiter(for: openChar))

            // Perl only accept named references here, but Oniguruma and .NET
            // also accepts numbered references. This shouldn't be an ambiguity
            // as named references may not begin with a digit, '-', or '+'.
            // Oniguruma also allows a recursion level to be specified.
            return .backreference(p.expectNamedOrNumberedReference(
              endingWith: closing, allowRecursionLevel: true))
          }
          // Perl/.NET also allow a named references with the '{' delimiter.
          if p.tryEat("{") {
            return .backreference(p.expectNamedReference(endingWith: "}"))
          }
          return nil
        }

        // Backslash followed by a non-0 digit character is a backreference.
        if firstChar != "0", let num = p.lexNumber() {
          return .backreference(.init(.absolute(num), innerLoc: num.location))
        }
        return nil
      }
    }
  }

  /// Try to lex a reference that syntactically looks like a group.
  ///
  ///     GroupLikeReference -> '(?' GroupLikeReferenceBody ')'
  ///     GroupLikeReferenceBody -> 'P=' <String>
  ///                             | 'P>' <String>
  ///                             | '&' <String>
  ///                             | 'R'
  ///                             | NumberRef
  ///
  private mutating func lexGroupLikeReference(
  ) -> Located<AST.Atom.Kind>? {
    recordLoc { p in
      p.tryEating { p in
        guard p.tryEat(sequence: "(?") else { return nil }

        // Note the below should be covered by canLexGroupLikeReference.

        // Python-style references.
        if p.tryEat(sequence: "P=") {
          return .backreference(p.expectNamedReference(endingWith: ")"))
        }
        if p.tryEat(sequence: "P>") {
          return .subpattern(p.expectNamedReference(endingWith: ")"))
        }

        // Perl-style subpatterns.
        if p.tryEat("&") {
          return .subpattern(p.expectNamedReference(endingWith: ")"))
        }

        // Whole-pattern recursion, which is equivalent to (?0).
        if let loc = p.tryEatWithLoc("R") {
          p.expect(")")
          return .subpattern(.init(.recurseWholePattern(loc), innerLoc: loc))
        }

        // Numbered subpattern reference.
        if let ref = p.lexNumberedReference(allowWholePatternRef: true) {
          p.expect(")")
          return .subpattern(ref)
        }
        return nil
      }
    }
  }

  /// Whether we can lex a group-like reference after the specifier '(?'.
  private mutating func canLexGroupLikeReference() -> Bool {
    lookahead { p in
      if p.tryEat("P") {
        return p.tryEat(anyOf: "=", ">") != nil
      }
      if p.tryEat(anyOf: "&", "R") != nil {
        return true
      }
      return p.canLexNumberedReference()
    }
  }

  private mutating func canLexMatchingOptionsAsAtom() -> Bool {
    lookahead { p in
      // See if we can lex a matching option sequence that terminates in ')'.
      // Such a sequence is an atom.
      guard p.lexMatchingOptionSequence() != nil else {
        return false
      }
      return p.tryEat(")")
    }
  }

  /// Whether a group specifier should be lexed as an atom instead of a group.
  private mutating func shouldLexGroupLikeAtom() -> Bool {
    lookahead { p in
      guard p.tryEat("(") else { return false }

      if p.tryEat("?") {
        // The start of a reference '(?P=', '(?R', ...
        if p.canLexGroupLikeReference() { return true }

        // The start of a PCRE callout.
        if p.tryEat("C") { return true }

        // The start of an Oniguruma 'of-contents' callout.
        if p.tryEat("{") { return true }

        // A matching option atom (?x), (?i), ...
        if p.canLexMatchingOptionsAsAtom() { return true }

        return false
      }
      // The start of a backreference directive or Oniguruma named callout.
      if p.tryEat("*") { return true }

      return false
    }
  }

  /// Consume an escaped atom, starting from after the backslash
  ///
  ///     Escaped          -> KeyboardModified | Builtin
  ///                       | UniScalar | Property | NamedCharacter
  ///                       | EscapedReference
  ///
  mutating func expectEscaped() -> Located<AST.Atom.Kind> {
    recordLoc { p in
      let ccc = p.context.isInCustomCharacterClass

      // Keyboard control/meta
      if p.tryEat("c") || p.tryEat(sequence: "C-") {
        guard let ascii = p.expectASCII() else { return .invalid }
        return .keyboardControl(ascii.value)
      }
      if p.tryEat(sequence: "M-\\C-") {
        guard let ascii = p.expectASCII() else { return .invalid }
        return .keyboardMetaControl(ascii.value)
      }
      if p.tryEat(sequence: "M-") {
        guard let ascii = p.expectASCII() else { return .invalid }
        return .keyboardMeta(ascii.value)
      }

      // Named character '\N{...}'.
      if let char = p.lexNamedCharacter() {
        return char.value
      }

      // Character property \p{...} \P{...}.
      if let prop = p.lexCharacterProperty() {
        return .property(prop.value)
      }

      // References using escape syntax, e.g \1, \g{1}, \k<...>, ...
      // These are not valid inside custom character classes.
      if !ccc, let ref = p.lexEscapedReference()?.value {
        return ref
      }

      // Hexadecimal and octal unicode scalars.
      if let scalar = p.lexUnicodeScalar() {
        return scalar
      }

      guard let charLoc = p.tryEatWithLoc() else {
        p.errorAtCurrentPosition(.expectedEscape)
        return .invalid
      }
      let char = charLoc.value

      // Single-character builtins.
      if let builtin = AST.Atom.EscapedBuiltin(
        char, inCustomCharacterClass: ccc
      ) {
        return .escaped(builtin)
      }

      // We only allow unknown escape sequences for non-letter non-number ASCII,
      // and non-ASCII whitespace.
      // TODO: Once we have fix-its, suggest a `0` prefix for octal `[\7]`.
      if (char.isASCII && (char.isLetter || char.isNumber)) ||
          (!char.isASCII && !char.isWhitespace) {
        p.error(.invalidEscape(char), at: charLoc.location)
      }
      return .char(char)
    }
  }

  /// Try to consume a PCRE callout.
  ///
  ///     PCRECallout     -> '(?C' CalloutBody ')'
  ///     PCRECalloutBody -> '' | <Number>
  ///                      | '`' <String> '`'
  ///                      | "'" <String> "'"
  ///                      | '"' <String> '"'
  ///                      | '^' <String> '^'
  ///                      | '%' <String> '%'
  ///                      | '#' <String> '#'
  ///                      | '$' <String> '$'
  ///                      | '{' <String> '}'
  ///
  mutating func lexPCRECallout() -> AST.Atom.Callout? {
    guard tryEat(sequence: "(?C") else { return nil }
    let arg = recordLoc { p -> AST.Atom.Callout.PCRE.Argument in
      // Parse '(?C' followed by a number.
      if let num = p.lexNumber() {
        return .number(num)
      }
      // '(?C)' is implicitly '(?C0)'.
      if p.peek() == ")" {
        return .number(.init(0, at: p.loc(p.src.currentPosition)))
      }
      // Parse '(C?' followed by a set of balanced delimiters as defined by
      // http://pcre.org/current/doc/html/pcre2pattern.html#SEC28
      if let open = p.tryEat(anyOf: "`", "'", "\"", "^", "%", "#", "$", "{") {
        let closing = String(p.getClosingDelimiter(for: open))
        return .string(p.expectQuoted(endingWith: closing).value)
      }
      // If we don't know what this syntax is, consume up to the ending ')' and
      // emit an error.
      let remaining = p.lexUntil { $0.src.isEmpty || $0.peek() == ")" }
      if p.src.isEmpty && remaining.value.isEmpty {
        p.errorAtCurrentPosition(.expected(")"))
      } else {
        p.error(.unknownCalloutKind("(?C\(remaining.value))"), at: remaining.location)
      }
      return .string(remaining.value)
    }
    expect(")")
    return .pcre(.init(arg))
  }

  /// Consume a list of arguments for an Oniguruma callout.
  ///
  ///     OnigurumaCalloutArgList -> OnigurumaCalloutArg (',' OnigurumaCalloutArgList)*
  ///     OnigurumaCalloutArg -> [^,}]+
  ///
  mutating func expectOnigurumaCalloutArgList(
    leftBrace: SourceLocation
  ) -> AST.Atom.Callout.OnigurumaNamed.ArgList {
    var args: [Located<String>] = []
    while true {
      let arg = recordLoc { p -> String? in
        // TODO: Warn about whitespace being included?
        guard let arg = p.tryEatPrefix({ $0 != "," && $0 != "}" }) else {
          p.errorAtCurrentPosition(.expectedCalloutArgument)
          return nil
        }
        return arg.value
      }
      if let arg = arg {
        args.append(arg)
      }
      if src.isEmpty || peek() == "}" { break }
      expect(",")
    }
    let rightBrace = expectWithLoc("}").location
    return .init(leftBrace, args,  rightBrace)
  }

  /// Try to consume an Oniguruma callout tag.
  ///
  ///     OnigurumaTag -> '[' Identifier ']'
  ///
  mutating func lexOnigurumaCalloutTag(
  ) -> AST.Atom.Callout.OnigurumaTag? {
    guard let leftBracket = tryEatWithLoc("[") else { return nil }
    let name = expectIdentifier(
      .onigurumaCalloutTag, endingWith: "]", eatEnding: false
    )
    let rightBracket = expectWithLoc("]").location
    return .init(leftBracket, name, rightBracket)
  }

  /// Try to consume a named Oniguruma callout.
  ///
  ///     OnigurumaNamedCallout -> '(*' Identifier OnigurumaTag? Args? ')'
  ///     Args                  -> '{' OnigurumaCalloutArgList '}'
  ///
  mutating func lexOnigurumaNamedCallout() -> AST.Atom.Callout? {
    tryEating { p in
      guard p.tryEat(sequence: "(*") else { return nil }
      let name = p.expectIdentifier(
        .onigurumaCalloutName, endingWith: ")", eatEnding: false)

      let tag = p.lexOnigurumaCalloutTag()

      let args = p.tryEatWithLoc("{").map {
        p.expectOnigurumaCalloutArgList(leftBrace: $0)
      }
      p.expect(")")
      return .onigurumaNamed(.init(name, tag: tag, args: args))
    }
  }

  /// Try to consume an Oniguruma callout 'of contents'.
  ///
  ///     OnigurumaCalloutOfContents -> '(?' '{'+ Contents '}'+ OnigurumaTag? Direction? ')'
  ///     Contents                   -> <String>
  ///     Direction                  -> 'X' | '<' | '>'
  ///
  mutating func lexOnigurumaCalloutOfContents() -> AST.Atom.Callout? {
    tryEating { p in
      guard p.tryEat(sequence: "(?"),
            let openBraces = p.tryEatPrefix({ $0 == "{" })
      else { return nil }

      let contents = p.expectQuoted(
        endingWith: "}", count: openBraces.value.count)
      let closeBraces = SourceLocation(
        contents.location.end ..< p.src.currentPosition)

      let tag = p.lexOnigurumaCalloutTag()

      typealias Direction = AST.Atom.Callout.OnigurumaOfContents.Direction
      let direction = p.recordLoc { p -> Direction in
        if p.tryEat(">") { return .inProgress }
        if p.tryEat("<") { return .inRetraction }
        if p.tryEat("X") { return .both }
        // The default is in-progress.
        return .inProgress
      }
      p.expect(")")

      return .onigurumaOfContents(.init(
        openBraces.location, contents, closeBraces, tag: tag,
        direction: direction
      ))
    }
  }

  /// Try to consume a backtracking directive.
  ///
  ///     BacktrackingDirective     -> '(*' BacktrackingDirectiveKind (':' <String>)? ')'
  ///     BacktrackingDirectiveKind -> 'ACCEPT' | 'FAIL' | 'F' | 'MARK' | ''
  ///                                | 'COMMIT' | 'PRUNE' | 'SKIP' | 'THEN'
  ///
  mutating func lexBacktrackingDirective(
  ) -> AST.Atom.BacktrackingDirective? {
    tryEating { p in
      guard p.tryEat(sequence: "(*") else { return nil }
      let kind = p.recordLoc { p -> AST.Atom.BacktrackingDirective.Kind? in
        if p.tryEat(sequence: "ACCEPT") { return .accept }
        if p.tryEat(sequence: "FAIL") || p.tryEat("F") { return .fail }
        if p.tryEat(sequence: "MARK") || p.peek() == ":" { return .mark }
        if p.tryEat(sequence: "COMMIT") { return .commit }
        if p.tryEat(sequence: "PRUNE") { return .prune }
        if p.tryEat(sequence: "SKIP") { return .skip }
        if p.tryEat(sequence: "THEN") { return .then }
        return nil
      }
      guard let kind = kind else { return nil }
      var name: Located<String>?
      if p.tryEat(":") {
        // TODO: PCRE allows escaped delimiters or '\Q...\E' sequences in the
        // name under PCRE2_ALT_VERBNAMES. It also allows whitespace under (?x).
        name = p.expectQuoted(endingWith: ")", eatEnding: false)
      }
      p.expect(")")

      // MARK directives must be named.
      if name == nil && kind.value == .mark {
        let kindStr = String(p.src[kind.location.range])
        p.error(.backtrackingDirectiveMustHaveName(kindStr), at: kind.location)
      }
      return .init(kind, name: name)
    }
  }

  /// Consume a group-like atom, diagnosing an error if an atom could not be
  /// produced.
  ///
  ///     GroupLikeAtom -> GroupLikeReference | Callout | BacktrackingDirective
  ///
  mutating func expectGroupLikeAtom() -> AST.Atom.Kind {
    // References that look like groups, e.g (?R), (?1), ...
    if let ref = lexGroupLikeReference() {
      return ref.value
    }

    // Change matching options atom (?i), (?x-i), ...
    if let seq = lexChangeMatchingOptionAtom() {
      return .changeMatchingOptions(seq)
    }

    // (*ACCEPT), (*FAIL), (*MARK), ...
    if let b = lexBacktrackingDirective() {
      return .backtrackingDirective(b)
    }

    // Global matching options can only appear at the very start.
    if let opt = lexGlobalMatchingOption() {
      let optStr = String(src[opt.location.range])
      error(.globalMatchingOptionNotAtStart(optStr), at: opt.location)
      return .invalid
    }

    // (?C)
    if let callout = lexPCRECallout() {
      return .callout(callout)
    }

    // Try to consume an Oniguruma named callout '(*name)', which should be
    // done after backtracking directives and global options.
    if let callout = lexOnigurumaNamedCallout() {
      return .callout(callout)
    }

    // (?{...})
    if let callout = lexOnigurumaCalloutOfContents() {
      return .callout(callout)
    }

    // If we didn't produce an atom, consume up until a reasonable end-point
    // and diagnose an error.
    expect("(")
    let remaining = lexUntil {
      $0.src.isEmpty || $0.tryEat(anyOf: ":", ")") != nil
    }
    if remaining.value.isEmpty {
      error(.expected(")"), at: remaining.location)
    } else {
      error(.unknownGroupKind(remaining.value), at: remaining.location)
    }
    return .invalid
  }


  /// Try to consume an Atom.
  ///
  ///     Atom             -> SpecialCharacter | POSIXSet
  ///                       | '\' Escaped | [^')' '|']
  ///     SpecialCharacter -> '.' | '^' | '$'
  ///     POSIXSet         -> '[:' name ':]'
  ///
  /// If `SyntaxOptions.experimentalGroups` is enabled, also accepts:
  ///
  ///     ExpGroupStart -> '(_:'
  ///
  mutating func lexAtom() -> AST.Atom? {
    let customCC = context.isInCustomCharacterClass
    let kind = recordLoc { p -> AST.Atom.Kind? in
      // Check for not-an-atom, e.g. parser recursion termination
      if p.src.isEmpty { return nil }
      if !customCC && (p.peek() == ")" || p.peek() == "|") { return nil }
      // TODO: Store customCC in the atom, if that's useful

      // POSIX character property. Like \p{...} this is also allowed outside of
      // a custom character class.
      if let prop = p.lexPOSIXCharacterProperty()?.value {
        return .property(prop)
      }

      // If we have group syntax that was skipped over in lexGroupStart, we
      // need to handle it as an atom, or diagnose an error.
      if !customCC && p.shouldLexGroupLikeAtom() {
        return p.expectGroupLikeAtom()
      }

      // A quantifier here is invalid.
      if !customCC, let q = p.recordLoc({ $0.lexQuantifier() }) {
        let str = String(p.src[q.location.range])
        p.error(.quantifierRequiresOperand(str), at: q.location)
        return .invalid
      }

      guard let charLoc = p.tryEatWithLoc() else {
        // We check at the beginning of the function for `isEmpty`, so we should
        // not be at the end of the input here.
        p.unreachable("Unexpected end of input")
        return nil
      }
      let char = charLoc.value
      switch char {
      case ")", "|":
        if customCC {
          return .char(char)
        }
        p.unreachable("Is as a termination condition")

      case "(" where !customCC:
        p.unreachable("Should have lexed a group or group-like atom")

      // (sometimes) special metacharacters
      case ".": return customCC ? .char(".") : .dot
      case "^": return customCC ? .char("^") : .caretAnchor
      case "$": return customCC ? .char("$") : .dollarAnchor

      // Escaped
      case "\\": return p.expectEscaped().value

      case "]":
        assert(!customCC, "parser should have prevented this")
        break

      default:
        // Reject non-letter non-number non-`\r\n` ASCII characters that have
        // multiple scalars. These may be confusable for metacharacters, e.g
        // `[\u{301}]` wouldn't be interpreted as a custom character class due
        // to the combining accent (assuming it is literal, not `\u{...}`).
        let scalars = char.unicodeScalars
        if scalars.count > 1 && scalars.first!.isASCII && char != "\r\n" &&
            !char.isLetter && !char.isNumber {
          p.error(.confusableCharacter(char), at: charLoc.location)
        }
        break
      }
      return .char(char)
    }
    guard let kind = kind else { return nil }
    return AST.Atom(kind.value, kind.location)
  }

  /// Try to lex the range operator '-' for a custom character class.
  mutating func lexCustomCharacterClassRangeOperator() -> SourceLocation? {
    // Eat a '-', making sure we don't have a binary op such as '--'.
    guard peekCCBinOp() == nil else { return nil }
    return tryEatWithLoc("-")
  }

  /// Try to consume a newline sequence matching option kind.
  ///
  ///     NewlineSequenceKind -> 'BSR_ANYCRLF' | 'BSR_UNICODE'
  ///
  private mutating func lexNewlineSequenceMatchingOption(
  ) -> AST.GlobalMatchingOption.NewlineSequenceMatching? {
    if tryEat(sequence: "BSR_ANYCRLF") { return .anyCarriageReturnOrLinefeed }
    if tryEat(sequence: "BSR_UNICODE") { return .anyUnicode }
    return nil
  }

  /// Try to consume a newline matching option kind.
  ///
  ///     NewlineKind -> 'CRLF' | 'CR' | 'ANYCRLF' | 'ANY' | 'LF' | 'NUL'
  ///
  private mutating func lexNewlineMatchingOption(
  ) -> AST.GlobalMatchingOption.NewlineMatching? {
    // The ordering here is important: CRLF needs to precede CR, and ANYCRLF
    // needs to precede ANY to ensure we don't short circuit on the wrong one.
    if tryEat(sequence: "CRLF") { return .carriageAndLinefeedOnly }
    if tryEat(sequence: "CR") { return .carriageReturnOnly }
    if tryEat(sequence: "ANYCRLF") { return .anyCarriageReturnOrLinefeed }
    if tryEat(sequence: "ANY") { return .anyUnicode }

    if tryEat(sequence: "LF") { return .linefeedOnly }
    if tryEat(sequence: "NUL") { return .nulCharacter }
    return nil
  }

  /// Try to consume a global matching option kind, returning `nil` if
  /// unsuccessful.
  ///
  ///     GlobalMatchingOptionKind -> LimitOptionKind '=' <Int>
  ///                               | NewlineKind | NewlineSequenceKind
  ///                               | 'NOTEMPTY_ATSTART' | 'NOTEMPTY'
  ///                               | 'NO_AUTO_POSSESS' | 'NO_DOTSTAR_ANCHOR'
  ///                               | 'NO_JIT' | 'NO_START_OPT' | 'UTF' | 'UCP'
  ///
  ///     LimitOptionKind          -> 'LIMIT_DEPTH' | 'LIMIT_HEAP'
  ///                               | 'LIMIT_MATCH'
  ///
  private mutating func lexGlobalMatchingOptionKind(
  ) -> Located<AST.GlobalMatchingOption.Kind>? {
    recordLoc { p in
      if let opt = p.lexNewlineSequenceMatchingOption() {
        return .newlineSequenceMatching(opt)
      }
      if let opt = p.lexNewlineMatchingOption() {
        return .newlineMatching(opt)
      }
      if p.tryEat(sequence: "LIMIT_DEPTH") {
        p.expect("=")
        return .limitDepth(p.expectNumber())
      }
      if p.tryEat(sequence: "LIMIT_HEAP") {
        p.expect("=")
        return .limitHeap(p.expectNumber())
      }
      if p.tryEat(sequence: "LIMIT_MATCH") {
        p.expect("=")
        return .limitMatch(p.expectNumber())
      }

      // The ordering here is important: NOTEMPTY_ATSTART needs to precede
      // NOTEMPTY to ensure we don't short circuit on the wrong one.
      if p.tryEat(sequence: "NOTEMPTY_ATSTART") { return .notEmptyAtStart }
      if p.tryEat(sequence: "NOTEMPTY") { return .notEmpty }

      if p.tryEat(sequence: "NO_AUTO_POSSESS") { return .noAutoPossess }
      if p.tryEat(sequence: "NO_DOTSTAR_ANCHOR") { return .noDotStarAnchor }
      if p.tryEat(sequence: "NO_JIT") { return .noJIT }
      if p.tryEat(sequence: "NO_START_OPT") { return .noStartOpt }
      if p.tryEat(sequence: "UTF") { return .utfMode }
      if p.tryEat(sequence: "UCP") { return .unicodeProperties }
      return nil
    }
  }

  /// Try to consume a global matching option, returning `nil` if unsuccessful.
  ///
  ///     GlobalMatchingOption -> '(*' GlobalMatchingOptionKind ')'
  ///
  mutating func lexGlobalMatchingOption(
  ) -> AST.GlobalMatchingOption? {
    let kind = recordLoc { p -> AST.GlobalMatchingOption.Kind? in
      p.tryEating { p in
        guard p.tryEat(sequence: "(*"),
              let kind = p.lexGlobalMatchingOptionKind()?.value
        else { return nil }
        p.expect(")")
        return kind
      }
    }
    guard let kind = kind else { return nil }
    return .init(kind.value, kind.location)
  }

  /// Try to consume a sequence of global matching options.
  ///
  ///     GlobalMatchingOptionSequence -> GlobalMatchingOption+
  ///
  mutating func lexGlobalMatchingOptionSequence(
  ) -> AST.GlobalMatchingOptionSequence? {
    var opts: [AST.GlobalMatchingOption] = []
    while let opt = lexGlobalMatchingOption() {
      opts.append(opt)
    }
    return .init(opts)
  }
}

