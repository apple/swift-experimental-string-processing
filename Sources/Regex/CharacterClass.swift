public struct CharacterClass: Hashable {
  /// The actual character class to match.
  var cc: Representation
  
  /// The level (character or Unicode scalar) at which to match.
  var matchLevel: MatchLevel

  /// Whether this character class matches against an inverse,
  /// e.g \D, \S, [^abc].
  var isInverted: Bool = false

  public enum Representation: Hashable {
    /// Any character
    case any
    /// Character.isDigit
    case digit
    /// Character.isHexDigit
    case hexDigit
    /// Character.isWhitespace
    case whitespace
    /// Character.isLetter or Character.isDigit or Character == "_"
    case word
    /// One of the custom character set.
    case custom([CharacterSetComponent])
  }

  public enum SetOperator: Hashable {
    case intersection
    case subtraction
    case symmetricDifference
  }

  /// A binary set operation that forms a character class component.
  public struct SetOperation: Hashable {
    var lhs: CharacterSetComponent
    var op: SetOperator
    var rhs: CharacterSetComponent

    public func matches(_ c: Character) -> Bool {
      switch op {
      case .intersection:
        return lhs.matches(c) && rhs.matches(c)
      case .subtraction:
        return lhs.matches(c) && !rhs.matches(c)
      case .symmetricDifference:
        return lhs.matches(c) != rhs.matches(c)
      }
    }
  }

  public enum CharacterSetComponent: Hashable {
    case character(Character)
    case range(ClosedRange<Character>)

    /// A nested character class.
    case characterClass(CharacterClass)

    /// A binary set operation of character class components.
    indirect case setOperation(SetOperation)

    public static func setOperation(
      lhs: CharacterSetComponent, op: SetOperator, rhs: CharacterSetComponent
    ) -> CharacterSetComponent {
      .setOperation(.init(lhs: lhs, op: op, rhs: rhs))
    }

    public func matches(_ character: Character) -> Bool {
      switch self {
      case .character(let c): return c == character
      case .range(let range): return range.contains(character)
      case .characterClass(let custom):
        let str = String(character)
        return custom.matches(in: str, at: str.startIndex) != nil
      case .setOperation(let op): return op.matches(character)
      }
    }
  }

  public enum MatchLevel {
    /// Match at the extended grapheme cluster level.
    case graphemeCluster
    /// Match at the Unicode scalar level.
    case unicodeScalar
  }

  public var scalarSemantic: Self {
    var result = self
    result.matchLevel = .unicodeScalar
    return result
  }
  
  public var graphemeClusterSemantic: Self {
    var result = self
    result.matchLevel = .graphemeCluster
    return result
  }

  /// Returns an inverted character class if true is passed, otherwise the
  /// same character class is returned.
  public func withInversion(_ invertion: Bool) -> Self {
    var copy = self
    if invertion {
      copy.isInverted.toggle()
    }
    return copy
  }

  /// Returns the inverse character class.
  public var inverted: Self {
    return withInversion(!isInverted)
  }
  
  /// Returns the end of the match of this character class in `str`, if
  /// it matches.
  public func matches(in str: String, at i: String.Index) -> String.Index? {
    switch matchLevel {
    case .graphemeCluster:
      let c = str[i]
      var matched: Bool
      switch cc {
      case .any: matched = true
      case .digit: matched = c.isNumber
      case .hexDigit: matched = c.isHexDigit
      case .whitespace: matched = c.isWhitespace
      case .word: matched = c.isLetter || c.isNumber || c == "_"
      case .custom(let set): matched = set.any { $0.matches(c) }
      }
      if isInverted {
        matched.toggle()
      }
      return matched ? str.index(after: i) : nil
    case .unicodeScalar:
      let c = str.unicodeScalars[i]
      var matched: Bool
      switch cc {
      case .any: matched = true
      case .digit: matched = c.properties.numericType != nil
      case .hexDigit: matched = Character(c).isHexDigit
      case .whitespace: matched = c.properties.isWhitespace
      case .word: matched = c.properties.isAlphabetic || c == "_"
      case .custom: fatalError("Not supported")
      }
      if isInverted {
        matched.toggle()
      }
      return matched ? str.unicodeScalars.index(after: i) : nil
    }
  }
}

extension CharacterClass {
  public static var any: CharacterClass {
    .init(cc: .any, matchLevel: .graphemeCluster)
  }
  
  public static var whitespace: CharacterClass {
    .init(cc: .whitespace, matchLevel: .graphemeCluster)
  }
  
  public static var digit: CharacterClass {
    .init(cc: .digit, matchLevel: .graphemeCluster)
  }
  
  public static var hexDigit: CharacterClass {
    .init(cc: .hexDigit, matchLevel: .graphemeCluster)
  }
  
  public static var word: CharacterClass {
    .init(cc: .word, matchLevel: .graphemeCluster)
  }

  public static func custom(
    _ components: [CharacterSetComponent]
  ) -> CharacterClass {
    .init(cc: .custom(components), matchLevel: .graphemeCluster)
  }
}

extension CharacterClass.CharacterSetComponent: CustomStringConvertible {
  public var description: String {
    switch self {
    case .range(let range): return "<range \(range)>"
    case .character(let character): return "<character \(character)>"
    case .characterClass(let custom): return "\(custom)"
    case .setOperation(let op): return "<\(op.lhs) \(op.op) \(op.rhs)>"
    }
  }
}

extension CharacterClass.Representation: CustomStringConvertible {
  public var description: String {
    switch self {
    case .any: return "<any>"
    case .digit: return "<digit>"
    case .hexDigit: return "<hex digit>"
    case .whitespace: return "<whitespace>"
    case .word: return "<word>"
    case .custom(let set): return "<custom \(set)>"
    }
  }
}

extension CharacterClass: CustomStringConvertible {
  public var description: String {
    return "\(isInverted ? "not " : "")\(cc)"
  }
}
