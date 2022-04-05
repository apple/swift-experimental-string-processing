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

import _RegexParser

// NOTE: This is a model type. We want to be able to get one from
// an AST, but this isn't a natural thing to produce in the context
// of parsing or to store in an AST

@_spi(RegexBuilder)
public struct _CharacterClassModel: Hashable {
  /// The actual character class to match.
  var cc: Representation
  
  /// The level (character or Unicode scalar) at which to match.
  var matchLevel: MatchLevel

  /// Whether this character class matches against an inverse,
  /// e.g \D, \S, [^abc].
  var isInverted: Bool = false

  // TODO: Split out builtin character classes into their own type?
  public enum Representation: Hashable {
    /// Any character
    case any
    /// Any grapheme cluster
    case anyGrapheme
    /// Character.isDigit
    case digit
    /// Character.isHexDigit
    case hexDigit
    /// Horizontal whitespace: `[:blank:]`, i.e
    /// `[\p{gc=Space_Separator}\N{CHARACTER TABULATION}]
    case horizontalWhitespace
    /// Character.isNewline
    case newlineSequence
    /// Vertical whitespace: `[\u{0A}-\u{0D}\u{85}\u{2028}\u{2029}]`
    case verticalWhitespace
    /// Character.isWhitespace
    case whitespace
    /// Character.isLetter or Character.isDigit or Character == "_"
    case word
    /// One of the custom character set.
    case custom([CharacterSetComponent])
  }

  public typealias SetOperator = AST.CustomCharacterClass.SetOp

  /// A binary set operation that forms a character class component.
  @_spi(RegexBuilder)
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

  @_spi(RegexBuilder)
  public enum CharacterSetComponent: Hashable {
    case character(Character)
    case range(ClosedRange<Character>)

    /// A nested character class.
    case characterClass(_CharacterClassModel)

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
    return withInversion(true)
  }
  
  /// Returns the end of the match of this character class in `str`, if
  /// it matches.
  public func matches(in str: String, at i: String.Index) -> String.Index? {
    switch matchLevel {
    case .graphemeCluster:
      let c = str[i]
      var matched: Bool
      switch cc {
      case .any, .anyGrapheme: matched = true
      case .digit: matched = c.isNumber
      case .hexDigit: matched = c.isHexDigit
      case .horizontalWhitespace: fatalError("Not implemented")
      case .newlineSequence: matched = c.isNewline
      case .verticalWhitespace: fatalError("Not implemented")
      case .whitespace: matched = c.isWhitespace
      case .word: matched = c.isWordCharacter
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
      case .anyGrapheme: fatalError("Not matched in this mode")
      case .digit: matched = c.properties.numericType != nil
      case .hexDigit: matched = Character(c).isHexDigit
      case .horizontalWhitespace: fatalError("Not implemented")
      case .newlineSequence: fatalError("Not implemented")
      case .verticalWhitespace: fatalError("Not implemented")
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

extension _CharacterClassModel: RegexComponent {
  public typealias Output = Substring

  public var regex: Regex<Output> {
    guard let ast = self.makeAST() else {
      fatalError("FIXME: extended AST?")
    }
    return Regex(ast: ast)
  }
}

@_spi(RegexBuilder)
extension RegexComponent where Self == _CharacterClassModel {
  public static var any: _CharacterClassModel {
    .init(cc: .any, matchLevel: .graphemeCluster)
  }

  public static var anyGrapheme: _CharacterClassModel {
    .init(cc: .anyGrapheme, matchLevel: .graphemeCluster)
  }

  public static var whitespace: _CharacterClassModel {
    .init(cc: .whitespace, matchLevel: .graphemeCluster)
  }
  
  public static var digit: _CharacterClassModel {
    .init(cc: .digit, matchLevel: .graphemeCluster)
  }
  
  public static var hexDigit: _CharacterClassModel {
    .init(cc: .hexDigit, matchLevel: .graphemeCluster)
  }

  public static var horizontalWhitespace: _CharacterClassModel {
    .init(cc: .horizontalWhitespace, matchLevel: .graphemeCluster)
  }

  public static var newlineSequence: _CharacterClassModel {
    .init(cc: .newlineSequence, matchLevel: .graphemeCluster)
  }

  public static var verticalWhitespace: _CharacterClassModel {
    .init(cc: .verticalWhitespace, matchLevel: .graphemeCluster)
  }

  public static var word: _CharacterClassModel {
    .init(cc: .word, matchLevel: .graphemeCluster)
  }

  public static func custom(
    _ components: [_CharacterClassModel.CharacterSetComponent]
  ) -> _CharacterClassModel {
    .init(cc: .custom(components), matchLevel: .graphemeCluster)
  }
}

extension _CharacterClassModel.CharacterSetComponent: CustomStringConvertible {
  public var description: String {
    switch self {
    case .range(let range): return "<range \(range)>"
    case .character(let character): return "<character \(character)>"
    case .characterClass(let custom): return "\(custom)"
    case .setOperation(let op): return "<\(op.lhs) \(op.op) \(op.rhs)>"
    }
  }
}

extension _CharacterClassModel.Representation: CustomStringConvertible {
  public var description: String {
    switch self {
    case .any: return "<any>"
    case .anyGrapheme: return "<any grapheme>"
    case .digit: return "<digit>"
    case .hexDigit: return "<hex digit>"
    case .horizontalWhitespace: return "<horizontal whitespace>"
    case .newlineSequence: return "<newline sequence>"
    case .verticalWhitespace: return "vertical whitespace"
    case .whitespace: return "<whitespace>"
    case .word: return "<word>"
    case .custom(let set): return "<custom \(set)>"
    }
  }
}

extension _CharacterClassModel: CustomStringConvertible {
  public var description: String {
    return "\(isInverted ? "not " : "")\(cc)"
  }
}

extension _CharacterClassModel {
  public func makeAST() -> AST.Node? {
    let inv = isInverted

    func esc(_ b: AST.Atom.EscapedBuiltin) -> AST.Node {
      escaped(b)
    }

    switch cc {
    case .any: return atom(.any)

    case .digit:
      return esc(inv ? .notDecimalDigit : .decimalDigit)

    case .horizontalWhitespace:
      return esc(
        inv ? .notHorizontalWhitespace : .horizontalWhitespace)

    // FIXME: newline sequence is not same as \n
    case .newlineSequence:
      return esc(inv ? .notNewline : .newline)

    case .whitespace:
      return esc(inv ? .notWhitespace : .whitespace)

    case .verticalWhitespace:
      return esc(inv ? .notVerticalTab : .verticalTab)

    case .word:
      return esc(inv ? .notWordCharacter : .wordCharacter)

    case .anyGrapheme:
      return esc(.graphemeCluster)

    case .hexDigit:
      let members: [AST.CustomCharacterClass.Member] = [
        range_m(.char("a"), .char("f")),
        range_m(.char("A"), .char("F")),
        range_m(.char("0"), .char("9")),
      ]
      let ccc = AST.CustomCharacterClass(
        .init(faking: inv ? .inverted : .normal),
        members,
        .fake)

      return .customCharacterClass(ccc)

    default: return nil
    }
  }
}

extension DSLTree.Node {
  var characterClass: _CharacterClassModel? {
    switch self {
    case let .customCharacterClass(ccc):
      return ccc.modelCharacterClass
    case let .atom(a):
      return a.characterClass
    case .characterPredicate:
      // FIXME: Do we make one from this?
      return nil
    default:
      return nil
    }
  }
}

extension _CharacterClassModel {
  public func withMatchLevel(
    _ level: _CharacterClassModel.MatchLevel
  ) -> _CharacterClassModel {
    var cc = self
    cc.matchLevel = level
    return cc
  }
}

extension DSLTree.Atom {
  var characterClass: _CharacterClassModel? {
    switch self {
    case let .unconverted(a):
      return a.characterClass

    default: return nil
    }
  }
}

extension AST.Atom {
  var characterClass: _CharacterClassModel? {
    switch kind {
    case let .escaped(b): return b.characterClass

    case .property:
      // TODO: Would our model type for character classes include
      // this? Or does grapheme-semantic mode complicate that?
      return nil
      
    case .any:
      // `.any` is handled in the matching engine by Compiler.emitAny() and in
      // the legacy compiler by the `.any` instruction, which can provide lower
      // level instructions than the CharacterClass-generated consumer closure
      //
      // FIXME: We shouldn't be returning `nil` here, but instead fixing the call
      // site to check for any before trying to construct a character class.
      return nil

    default: return nil

    }
  }

}

extension AST.Atom.EscapedBuiltin {
  var characterClass: _CharacterClassModel? {
    switch self {
    case .decimalDigit:    return .digit
    case .notDecimalDigit: return .digit.inverted

    case .horizontalWhitespace: return .horizontalWhitespace
    case .notHorizontalWhitespace:
      return .horizontalWhitespace.inverted

    case .notNewline: return .newlineSequence.inverted
    case .newlineSequence: return .newlineSequence

    case .whitespace:    return .whitespace
    case .notWhitespace: return .whitespace.inverted

    case .verticalTab:    return .verticalWhitespace
    case .notVerticalTab: return .verticalWhitespace.inverted

    case .wordCharacter:    return .word
    case .notWordCharacter: return .word.inverted

    case .graphemeCluster: return .anyGrapheme

    default:
      return nil
    }
  }
}

extension DSLTree.CustomCharacterClass {
  // TODO: Refactor a bit, and... can we drop this type?
  var modelCharacterClass: _CharacterClassModel? {
    var result =
      Array<_CharacterClassModel.CharacterSetComponent>()
    for m in members {
      switch m {
      case let .atom(a):
        if let cc = a.characterClass {
          result.append(.characterClass(cc))
        } else if let c = a.literalCharacterValue {
          result.append(.character(c))
        } else {
          return nil
        }
      case let .range(low, high):
        guard let lhs = low.literalCharacterValue,
              let rhs = high.literalCharacterValue
        else {
          return nil
        }
        result.append(.range(lhs...rhs))

      case let .custom(ccc):
        guard let cc = ccc.modelCharacterClass else {
          return nil
        }
        result.append(.characterClass(cc))

      case let .intersection(lhs, rhs):
        guard let lhs = lhs.modelCharacterClass,
              let rhs = rhs.modelCharacterClass
        else {
          return nil
        }
        result.append(.setOperation(
          lhs: .characterClass(lhs),
          op: .intersection,
          rhs: .characterClass(rhs)))

      case let .subtraction(lhs, rhs):
        guard let lhs = lhs.modelCharacterClass,
              let rhs = rhs.modelCharacterClass
        else {
          return nil
        }
        result.append(.setOperation(
          lhs: .characterClass(lhs),
          op: .subtraction,
          rhs: .characterClass(rhs)))

      case let .symmetricDifference(lhs, rhs):
        guard let lhs = lhs.modelCharacterClass,
              let rhs = rhs.modelCharacterClass
        else {
          return nil
        }
        result.append(.setOperation(
          lhs: .characterClass(lhs),
          op: .symmetricDifference,
          rhs: .characterClass(rhs)))

      case let .quotedLiteral(s):
        // Decompose quoted literal into literal characters.
        result += s.map { .character($0) }

      case .trivia:
        break
      }
    }
    let cc = _CharacterClassModel.custom(result)
    return isInverted ? cc.inverted : cc
  }
}

extension _CharacterClassModel {
  // FIXME: Calling on inverted sets wont be the same as the
  // inverse of a boundary if at the start or end of the
  // string. (Think through what we want: do it ourselves or
  // give the caller both options).
  func isBoundary(
    _ input: String,
    at pos: String.Index,
    bounds: Range<String.Index>
  ) -> Bool {
    // FIXME: How should we handle bounds?
    // We probably need two concepts
    if input.isEmpty { return false }
    if pos == input.startIndex {
      return self.matches(in: input, at: pos) != nil
    }
    let priorIdx = input.index(before: pos)
    if pos == input.endIndex {
      return self.matches(in: input, at: priorIdx) != nil
    }

    let prior = self.matches(in: input, at: priorIdx) != nil
    let current = self.matches(in: input, at: pos) != nil
    return prior != current
  }

}
