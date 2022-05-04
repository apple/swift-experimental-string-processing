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
@_spi(RegexBuilder) import _StringProcessing

@available(SwiftStdlib 5.7, *)
public struct CharacterClass {
  internal var ccc: DSLTree.CustomCharacterClass
  
  init(_ ccc: DSLTree.CustomCharacterClass) {
    self.ccc = ccc
  }
  
  init(unconverted model: _CharacterClassModel) {
    // FIXME: Implement in DSLTree instead of wrapping an AST atom
    switch model.makeAST() {
    case .atom(let atom):
      self.ccc = .init(members: [.atom(.unconverted(atom))])
    default:
      fatalError("Unsupported _CharacterClassModel")
    }
  }
  
  init(property: AST.Atom.CharacterProperty) {
    // FIXME: Implement in DSLTree instead of wrapping an AST atom
    let astAtom = AST.Atom(.property(property), .fake)
    self.ccc = .init(members: [.atom(.unconverted(astAtom))])
  }
}

@available(SwiftStdlib 5.7, *)
extension CharacterClass: RegexComponent {
  public var regex: Regex<Substring> {
    return Regex(node: DSLTree.Node.customCharacterClass(ccc))
  }
}

@available(SwiftStdlib 5.7, *)
extension CharacterClass {
  public var inverted: CharacterClass {
    CharacterClass(ccc.inverted)
  }
}

@available(SwiftStdlib 5.7, *)
extension RegexComponent where Self == CharacterClass {
  public static var any: CharacterClass {
    .init(DSLTree.CustomCharacterClass(members: [.atom(.any)]))
  }

  public static var anyGrapheme: CharacterClass {
    .init(unconverted: .anyGrapheme)
  }
  
  public static var anyUnicodeScalar: CharacterClass {
    .init(unconverted: .anyUnicodeScalar)
  }

  public static var whitespace: CharacterClass {
    .init(unconverted: .whitespace)
  }
  
  public static var digit: CharacterClass {
    .init(unconverted: .digit)
  }
  
  public static var hexDigit: CharacterClass {
    .init(DSLTree.CustomCharacterClass(members: [
      .range(.char("A"), .char("F")),
      .range(.char("a"), .char("f")),
      .range(.char("0"), .char("9")),
    ]))
  }

  public static var horizontalWhitespace: CharacterClass {
    .init(unconverted: .horizontalWhitespace)
  }

  public static var newlineSequence: CharacterClass {
    .init(unconverted: .newlineSequence)
  }

  public static var verticalWhitespace: CharacterClass {
    .init(unconverted: .verticalWhitespace)
  }

  public static var word: CharacterClass {
    .init(unconverted: .word)
  }
}

@available(SwiftStdlib 5.7, *)
extension RegexComponent where Self == CharacterClass {
  /// Returns a character class that matches any character in the given string
  /// or sequence.
  public static func anyOf<S: Sequence>(_ s: S) -> CharacterClass
    where S.Element == Character
  {
    CharacterClass(DSLTree.CustomCharacterClass(
      members: s.map { .atom(.char($0)) }))
  }
  
  /// Returns a character class that matches any Unicode scalar in the given
  /// sequence.
  public static func anyOf<S: Sequence>(_ s: S) -> CharacterClass
    where S.Element == UnicodeScalar
  {
    CharacterClass(DSLTree.CustomCharacterClass(
      members: s.map { .atom(.scalar($0)) }))
  }
}

// Unicode properties
@available(SwiftStdlib 5.7, *)
extension CharacterClass {
  public static func generalCategory(_ category: Unicode.GeneralCategory) -> CharacterClass {
    guard let extendedCategory = category.extendedGeneralCategory else {
      fatalError("Unexpected general category")
    }
    return CharacterClass(property:
        .init(.generalCategory(extendedCategory), isInverted: false, isPOSIX: false))
  }
}

/// Returns a character class that includes the characters in the given range.
@available(SwiftStdlib 5.7, *)
public func ...(lhs: Character, rhs: Character) -> CharacterClass {
  let range: DSLTree.CustomCharacterClass.Member = .range(.char(lhs), .char(rhs))
  let ccc = DSLTree.CustomCharacterClass(members: [range], isInverted: false)
  return CharacterClass(ccc)
}

/// Returns a character class that includes the Unicode scalars in the given range.
@_disfavoredOverload
@available(SwiftStdlib 5.7, *)
public func ...(lhs: UnicodeScalar, rhs: UnicodeScalar) -> CharacterClass {
  let range: DSLTree.CustomCharacterClass.Member = .range(.scalar(lhs), .scalar(rhs))
  let ccc = DSLTree.CustomCharacterClass(members: [range], isInverted: false)
  return CharacterClass(ccc)
}

extension Unicode.GeneralCategory {
  var extendedGeneralCategory: Unicode.ExtendedGeneralCategory? {
    switch self {
    case .uppercaseLetter: return .uppercaseLetter
    case .lowercaseLetter: return .lowercaseLetter
    case .titlecaseLetter: return .titlecaseLetter
    case .modifierLetter: return .modifierLetter
    case .otherLetter: return .otherLetter
    case .nonspacingMark: return .nonspacingMark
    case .spacingMark: return .spacingMark
    case .enclosingMark: return .enclosingMark
    case .decimalNumber: return .decimalNumber
    case .letterNumber: return .letterNumber
    case .otherNumber: return .otherNumber
    case .connectorPunctuation: return .connectorPunctuation
    case .dashPunctuation: return .dashPunctuation
    case .openPunctuation: return .openPunctuation
    case .closePunctuation: return .closePunctuation
    case .initialPunctuation: return .initialPunctuation
    case .finalPunctuation: return .finalPunctuation
    case .otherPunctuation: return .otherPunctuation
    case .mathSymbol: return .mathSymbol
    case .currencySymbol: return .currencySymbol
    case .modifierSymbol: return .modifierSymbol
    case .otherSymbol: return .otherSymbol
    case .spaceSeparator: return .spaceSeparator
    case .lineSeparator: return .lineSeparator
    case .paragraphSeparator: return .paragraphSeparator
    case .control: return .control
    case .format: return .format
    case .surrogate: return .surrogate
    case .privateUse: return .privateUse
    case .unassigned: return .unassigned
    @unknown default: return nil
    }
  }
}

// MARK: - Set algebra methods

@available(SwiftStdlib 5.7, *)
extension RegexComponent where Self == CharacterClass {
  public init(_ first: CharacterClass, _ rest: CharacterClass...) {
    if rest.isEmpty {
      self.init(first.ccc)
    } else {
      let members: [DSLTree.CustomCharacterClass.Member] =
        (CollectionOfOne(first) + rest).map { .custom($0.ccc) }
      self.init(.init(members: members))
    }
  }
}

@available(SwiftStdlib 5.7, *)
extension CharacterClass {
  public func union(_ other: CharacterClass) -> CharacterClass {
    CharacterClass(.init(members: [
      .custom(self.ccc),
      .custom(other.ccc)]))
  }
  
  public func intersection(_ other: CharacterClass) -> CharacterClass {
    CharacterClass(.init(members: [
      .intersection(self.ccc, other.ccc)
    ]))
  }
  
  public func subtracting(_ other: CharacterClass) -> CharacterClass {
    CharacterClass(.init(members: [
      .subtraction(self.ccc, other.ccc)
    ]))
  }
  
  public func symmetricDifference(_ other: CharacterClass) -> CharacterClass {
    CharacterClass(.init(members: [
      .symmetricDifference(self.ccc, other.ccc)
    ]))
  }
}
