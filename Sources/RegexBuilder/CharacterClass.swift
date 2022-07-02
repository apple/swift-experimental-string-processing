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

/// A class of characters that match in a regex.
///
/// A character class can represent individual characters, a group of
/// characters, the set of character that match some set of criteria, or
/// a set algebraic combination of all of the above.
@available(SwiftStdlib 5.7, *)
public struct CharacterClass {
  internal var ccc: DSLTree.CustomCharacterClass
  
  init(_ ccc: DSLTree.CustomCharacterClass) {
    self.ccc = ccc
  }
  
  init(unconverted model: _CharacterClassModel) {
    guard let ccc = model.makeDSLTreeCharacterClass() else {
      fatalError("Unsupported character class")
    }
    self.ccc = ccc
  }
}

@available(SwiftStdlib 5.7, *)
extension CharacterClass: RegexComponent {
  public var regex: Regex<Substring> {
    _RegexFactory().customCharacterClass(ccc)
  }
}

@available(SwiftStdlib 5.7, *)
extension CharacterClass {
  /// A character class that matches any character that does not match this
  /// character class.
  public var inverted: CharacterClass {
    CharacterClass(ccc.inverted)
  }
}

@available(SwiftStdlib 5.7, *)
extension RegexComponent where Self == CharacterClass {
  /// A character class that matches any element.
  ///
  /// This character class is unaffected by the `dotMatchesNewlines()` method.
  /// To match any character that isn't a newline, see
  /// ``CharacterClass.anyNonNewline``.
  ///
  /// This character class is equivalent to the regex syntax "dot"
  /// metacharacter in single-line mode: `(?s:.)`.
  public static var any: CharacterClass {
    .init(DSLTree.CustomCharacterClass(members: [.atom(.any)]))
  }

  /// A character class that matches any element that isn't a newline.
  ///
  /// This character class is unaffected by the `dotMatchesNewlines()` method.
  /// To match any character, including newlines, see ``CharacterClass.any``.
  ///
  /// This character class is equivalent to the regex syntax "dot"
  /// metacharacter with single-line mode disabled: `(?-s:.)`.
  public static var anyNonNewline: CharacterClass {
    .init(DSLTree.CustomCharacterClass(members: [.atom(.any)]))
  }

  /// A character class that matches any single `Character`, or extended
  /// grapheme cluster, regardless of the current semantic level.
  ///
  /// This character class is equivalent to `\X` in regex syntax.
  public static var anyGrapheme: CharacterClass {
    .init(unconverted: .anyGrapheme)
  }

  /// A character class that matches any digit.
  ///
  /// This character class is equivalent to `\d` in regex syntax.
  public static var digit: CharacterClass {
    .init(unconverted: .digit)
  }
  
  /// A character class that matches any hexadecimal digit.
  public static var hexDigit: CharacterClass {
    .init(DSLTree.CustomCharacterClass(members: [
      .range(.char("A"), .char("F")),
      .range(.char("a"), .char("f")),
      .range(.char("0"), .char("9")),
    ]))
  }

  /// A character class that matches any element that is a "word character".
  ///
  /// This character class is equivalent to `\w` in regex syntax.
  public static var word: CharacterClass {
    .init(unconverted: .word)
  }

  /// A character class that matches any element that is classified as
  /// whitespace.
  ///
  /// This character class is equivalent to `\s` in regex syntax.
  public static var whitespace: CharacterClass {
    .init(unconverted: .whitespace)
  }
  
  /// A character class that matches any element that is classified as
  /// horizontal whitespace.
  ///
  /// This character class is equivalent to `\h` in regex syntax.
  public static var horizontalWhitespace: CharacterClass {
    .init(unconverted: .horizontalWhitespace)
  }

  /// A character class that matches any element that is classified as
  /// vertical whitespace.
  ///
  /// This character class is equivalent to `\v` in regex syntax.
  public static var verticalWhitespace: CharacterClass {
    .init(unconverted: .verticalWhitespace)
  }
  
  /// A character class that matches any newline sequence.
  ///
  /// This character class is equivalent to `\R` or `\n` in regex syntax.
  public static var newlineSequence: CharacterClass {
    .init(unconverted: .newlineSequence)
  }
}

@available(SwiftStdlib 5.7, *)
extension RegexComponent where Self == CharacterClass {
  /// Returns a character class that matches any character in the given string
  /// or sequence.
  ///
  /// Calling this method with a group of characters is equivalent to listing
  /// those characters in a custom character class in regex syntax. For example,
  /// the two regexes in this example are equivalent:
  ///
  ///     let regex1 = /[abcd]+/
  ///     let regex2 = OneOrMore(.anyOf("abcd"))
  ///
  /// - Parameter s: A sequence of characters to match against.
  public static func anyOf<S: Sequence>(_ s: S) -> CharacterClass
    where S.Element == Character
  {
    CharacterClass(DSLTree.CustomCharacterClass(
      members: s.map { .atom(.char($0)) }))
  }
  
  /// Returns a character class that matches any Unicode scalar in the given
  /// sequence.
  ///
  /// Calling this method with a group of Unicode scalars is equivalent to
  /// listing them in a custom character class in regex syntax.
  ///
  /// - Parameter s: A sequence of Unicode scalar values to match against.
  public static func anyOf<S: Sequence>(_ s: S) -> CharacterClass
    where S.Element == UnicodeScalar
  {
    CharacterClass(DSLTree.CustomCharacterClass(
      members: s.map { .atom(.scalar($0)) }))
  }

  /// Returns a character class that matches none of the characters in the given
  /// string or sequence.
  ///
  /// Calling this method with a group of characters is equivalent to listing
  /// those characters in a negated custom character class in regex syntax. For
  /// example, the two regexes in this example are equivalent:
  ///
  ///     let regex1 = /[^abcd]+/
  ///     let regex2 = OneOrMore(.noneOf("abcd"))
  ///
  /// - Parameter s: A sequence of characters to match against.
  public static func noneOf<S: Sequence>(_ s: S) -> CharacterClass
    where S.Element == Character
  {
    CharacterClass(DSLTree.CustomCharacterClass(
      members: s.map { .atom(.char($0)) })).inverted
  }
  
  /// Returns a character class that matches none of the Unicode scalars in the
  /// given sequence.
  ///
  /// Calling this method with a group of Unicode scalars is equivalent to
  /// listing them in a negated custom character class in regex syntax.
  ///
  /// - Parameter s: A sequence of Unicode scalar values to match against.
  public static func noneOf<S: Sequence>(_ s: S) -> CharacterClass
    where S.Element == UnicodeScalar
  {
    CharacterClass(DSLTree.CustomCharacterClass(
      members: s.map { .atom(.scalar($0)) })).inverted
  }
}

// Unicode properties
@available(SwiftStdlib 5.7, *)
extension RegexComponent where Self == CharacterClass {
  /// Returns a character class that matches any element with the given Unicode
  /// general category.
  ///
  /// For example, when passed `.uppercaseLetter`, this method is equivalent to
  /// `/\p{Uppercase_Letter}/` or `/\p{Lu}/`.
  public static func generalCategory(_ category: Unicode.GeneralCategory) -> CharacterClass {
    return CharacterClass(.generalCategory(category))
  }
  
  /// Returns a character class that matches any element with the given Unicode
  /// binary property.
  ///
  /// For example, when passed `\.isAlphabetic`, this method is equivalent to
  /// `/\p{Alphabetic}/` or `/\p{Is_Alphabetic=true}/`.
  public static func binaryProperty(_ property: KeyPath<UnicodeScalar.Properties, Bool>, value: Bool = true) -> CharacterClass {
    return CharacterClass(.binaryProperty(property, value: value))
  }
  
  /// Returns a character class that matches any element with the given Unicode
  /// name.
  ///
  /// This method is equivalent to `/\p{Name=name}/`.
  public static func name(_ name: String) -> CharacterClass {
    return CharacterClass(.named(name))
  }
  
  /// Returns a character class that matches any element that was included in
  /// the specified Unicode version.
  ///
  /// This method is equivalent to `/\p{Age=version}/`.
  public static func age(_ version: Unicode.Version) -> CharacterClass {
    return CharacterClass(.age(version))
  }
  
  /// Returns a character class that matches any element with the given Unicode
  /// numeric type.
  ///
  /// This method is equivalent to `/\p{Numeric_Type=type}/`.
  public static func numericType(_ type: Unicode.NumericType) -> CharacterClass {
    return CharacterClass(.numericType(type))
  }
  
  /// Returns a character class that matches any element with the given numeric
  /// value.
  ///
  /// This method is equivalent to `/\p{Numeric_Value=value}/`.
  public static func numericValue(_ value: Double) -> CharacterClass {
    return CharacterClass(.numericValue(value))
  }
  
  /// Returns a character class that matches any element with the given Unicode
  /// canonical combining class.
  ///
  /// This method is equivalent to
  /// `/\p{Canonical_Combining_Class=combiningClass}/`.
  public static func canonicalCombiningClass(_ combiningClass: Unicode.CanonicalCombiningClass) -> CharacterClass {
    return CharacterClass(.ccc(combiningClass))
  }
  
  /// Returns a character class that matches any element with the given
  /// lowercase mapping.
  ///
  /// This method is equivalent to `/\p{Lowercase_Mapping=value}/`.
  public static func lowercaseMapping(_ value: String) -> CharacterClass {
    return CharacterClass(.lowercaseMapping(value))
  }
  
  /// Returns a character class that matches any element with the given
  /// uppercase mapping.
  ///
  /// This method is equivalent to `/\p{Uppercase_Mapping=value}/`.
  public static func uppercaseMapping(_ value: String) -> CharacterClass {
    return CharacterClass(.uppercaseMapping(value))
  }
  
  /// Returns a character class that matches any element with the given
  /// titlecase mapping.
  ///
  /// This method is equivalent to `/\p{Titlecase_Mapping=value}/`.
  public static func titlecaseMapping(_ value: String) -> CharacterClass {
    return CharacterClass(.titlecaseMapping(value))
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
  /// Returns a character class that combines all the given characters classes
  /// via union.
  public init(_ first: CharacterClass, _ rest: CharacterClass...) {
    if rest.isEmpty {
      self.init(first.ccc)
    } else {
      self.init([[first], rest].joined())
    }
  }
  
  /// Returns a character class that combines the characters classes in the
  /// given sequence or collection via union.
  ///
  /// - Parameter characterClasses: A sequence or collection of character class
  ///   instances.
  public init<S: Sequence>(_ characterClasses: S) where S.Element == CharacterClass {
    let members: [DSLTree.CustomCharacterClass.Member] =
      characterClasses.map { .custom($0.ccc) }
    self.init(.init(members: members))
  }
}

@available(SwiftStdlib 5.7, *)
extension CharacterClass {
  /// Returns a character class that is matches the union of this class and the
  /// given class.
  public func union(_ other: CharacterClass) -> CharacterClass {
    CharacterClass(.init(members: [
      .custom(self.ccc),
      .custom(other.ccc)]))
  }
  
  /// Returns a character class that is matches the intersection of this class
  /// and the given class.
  public func intersection(_ other: CharacterClass) -> CharacterClass {
    CharacterClass(.init(members: [
      .intersection(self.ccc, other.ccc)
    ]))
  }
    
  /// Returns a character class that is matches the difference of this class
  /// and the given class.
  public func subtracting(_ other: CharacterClass) -> CharacterClass {
    CharacterClass(.init(members: [
      .subtraction(self.ccc, other.ccc)
    ]))
  }
    
  /// Returns a character class that is matches the symmetric difference of
  /// this class and the given class.
  public func symmetricDifference(_ other: CharacterClass) -> CharacterClass {
    CharacterClass(.init(members: [
      .symmetricDifference(self.ccc, other.ccc)
    ]))
  }
}
