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

@_implementationOnly import _RegexParser
@_spi(RegexBuilder) import _StringProcessing

@available(SwiftStdlib 5.7, *)
public struct CharacterClass {
  internal var ccc: DSLTree.CustomCharacterClass
  /// The builtin character class, if this CharacterClass is representable by one
  internal var builtin: DSLTree.Atom.CharacterClass?
  
  init(_ ccc: DSLTree.CustomCharacterClass) {
    self.ccc = ccc
    self.builtin = nil
  }
  
  init(builtin: DSLTree.Atom.CharacterClass) {
    self.ccc = .init(members: [.atom(.characterClass(builtin))])
    self.builtin = builtin
  }
}

@available(SwiftStdlib 5.7, *)
extension CharacterClass: RegexComponent {
  public var regex: Regex<Substring> {
    if let cc = builtin {
      return _RegexFactory().characterClass(cc)
    } else {
      return _RegexFactory().customCharacterClass(ccc)
    }
  }
}

@available(SwiftStdlib 5.7, *)
extension CharacterClass {
  public var inverted: CharacterClass {
    if let inv = builtin?.inverted {
      return CharacterClass(builtin: inv)
    } else {
      return CharacterClass(ccc.inverted)
    }
  }
}

@available(SwiftStdlib 5.7, *)
extension RegexComponent where Self == CharacterClass {
  public static var any: CharacterClass {
    .init(DSLTree.CustomCharacterClass(members: [.atom(.any)]))
  }

  public static var anyNonNewline: CharacterClass {
    .init(DSLTree.CustomCharacterClass(members: [.atom(.anyNonNewline)]))
  }

  public static var anyGraphemeCluster: CharacterClass {
    .init(builtin: .anyGrapheme)
  }
  
  public static var whitespace: CharacterClass {
    .init(builtin: .whitespace)
  }
  
  public static var digit: CharacterClass {
    .init(builtin: .digit)
  }
  
  public static var hexDigit: CharacterClass {
    .init(DSLTree.CustomCharacterClass(members: [
      .range(.char("A"), .char("F")),
      .range(.char("a"), .char("f")),
      .range(.char("0"), .char("9")),
    ]))
  }

  public static var horizontalWhitespace: CharacterClass {
    .init(builtin: .horizontalWhitespace)
  }

  public static var newlineSequence: CharacterClass {
    .init(builtin: .newlineSequence)
  }

  public static var verticalWhitespace: CharacterClass {
    .init(builtin: .verticalWhitespace)
  }

  public static var word: CharacterClass {
    .init(builtin: .word)
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
    return CharacterClass(.generalCategory(category))
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
