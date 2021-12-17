/// The source given to a parser. This can be bytes in memory, a file on disk,
/// something streamed over a network connection, etc.
///
/// For now, we use String...
///
public struct Source {
  var input: Input
  var bounds: Range<Input.Index>
  var syntax: SyntaxOptions

  // TODO: source should hold outer collection and range, at least
  // for error reporting if nothing else

  init(_ str: Input, _ syntax: SyntaxOptions) {
    self.input = str
    self.bounds = str.startIndex ..< str.endIndex
    self.syntax = syntax
  }
}

// MARK: - Prototype uses String

// For prototyping, base everything on String. Might be buffer
// of bytes, etc., in the future
extension Source {
  public typealias Input = String    // for wrapper...
  public typealias Char  = Character // for wrapper...

  /// A precise point in the input, commonly used for bounded ranges
  public typealias Position = String.Index
}

// MARK: - Syntax

extension Source {
  var experimentalRanges: Bool { syntax.contains(.experimentalRanges) }
  var experimentalCaptures: Bool { syntax.contains(.experimentalCaptures) }
  var experimentalQuotes: Bool { syntax.contains(.experimentalQuotes) }
  var experimentalComments: Bool { syntax.contains(.experimentalComments) }
  var nonSemanticWhitespace: Bool {
    syntax.contains(.nonSemanticWhitespace)
  }
}

// MARK: - Source as a peekable consumer

extension Source {
  var _slice: Input.SubSequence { input[bounds] }

  var isEmpty: Bool { _slice.isEmpty }

  mutating func peek() -> Char? { _slice.first }

  mutating func advance() {
    assert(!isEmpty)
    let newLower = _slice.index(after: bounds.lowerBound)
    self.bounds = newLower ..< bounds.upperBound
  }

  mutating func advance(_ i: Int) {
    for _ in 0..<i {
      advance()
    }
  }

  mutating func tryEat(_ c: Char) -> Bool {
    guard peek() == c else { return false }
    advance()
    return true
  }

  mutating func tryEat<C: Collection>(sequence c: C) -> Bool
  where C.Element == Char {
    guard _slice.starts(with: c) else { return false }
    advance(c.count)
    return true
  }

  mutating func eat(asserting c: Char) {
    assert(peek() == c)
    advance()
  }

  mutating func eat() -> Char {
    assert(!isEmpty)
    defer { advance() }
    return peek().unsafelyUnwrapped
  }

  func starts<S: Sequence>(
    with s: S
  ) -> Bool where S.Element == Char {
    _slice.starts(with: s)
  }

  mutating func eat(upTo: Position) -> Input.SubSequence {
    defer {
      while _slice.startIndex != upTo { advance() }
    }
    return _slice[..<upTo]
  }
  mutating func eat(upToCount count: Int) -> Input.SubSequence {
    let pre = _slice.prefix(count)
    defer { advance(pre.count) }
    return pre
  }

  mutating func tryEatPrefix(
    maxLength: Int? = nil,
    _ f: (Char) -> Bool
  ) -> Input.SubSequence? {
    let chunk: Input.SubSequence
    if let maxLength = maxLength {
      chunk = _slice.prefix(maxLength)
    } else {
      chunk = _slice[...]
    }
    let pre = chunk.prefix(while: f)
    guard !pre.isEmpty else { return nil }

    defer { self.advance(pre.count) }
    return pre
  }

  mutating func tryEat(count: Int) -> Input.SubSequence? {
    let pre = _slice.prefix(count)
    guard pre.count == count else { return nil }
    defer { advance(count) }
    return pre
  }
}
