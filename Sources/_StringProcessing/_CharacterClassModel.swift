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

// NOTE: This is a model type. We want to be able to get one from
// an AST, but this isn't a natural thing to produce in the context
// of parsing or to store in an AST

struct _CharacterClassModel: Hashable {
  /// The actual character class to match.
  var cc: Representation
  
  /// The level (character or Unicode scalar) at which to match.
  var matchLevel: MatchLevel

  /// Whether this character class matches against an inverse,
  /// e.g \D, \S, [^abc].
  var isInverted: Bool = false

  // TODO: Split out builtin character classes into their own type?
  enum Representation: UInt64, Hashable {
    /// Any character
    case any = 0
    /// Any grapheme cluster
    case anyGrapheme
    /// Any Unicode scalar
    case anyScalar
    /// Character.isDigit
    case digit
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
  }

  enum MatchLevel: Hashable {
    /// Match at the extended grapheme cluster level.
    case graphemeCluster
    /// Match at the Unicode scalar level.
    case unicodeScalar
  }

  var scalarSemantic: Self {
    var result = self
    result.matchLevel = .unicodeScalar
    return result
  }
  
  var graphemeClusterSemantic: Self {
    var result = self
    result.matchLevel = .graphemeCluster
    return result
  }

  /// Returns true if this CharacterClass should be matched by strict ascii under the given options
  func isStrictAscii(options: MatchingOptions) -> Bool {
    switch self.cc {
    case .digit: return options.usesASCIIDigits
    case .horizontalWhitespace: return options.usesASCIISpaces
    case .newlineSequence: return options.usesASCIISpaces
    case .verticalWhitespace: return options.usesASCIISpaces
    case .whitespace: return options.usesASCIISpaces
    case .word: return options.usesASCIIWord
    default: return false
    }
  }

  /// Inverts a character class.
  var inverted: Self {
    var copy = self
    copy.isInverted.toggle()
    return copy
  }
  
  /// Returns the end of the match of this character class in the string.
  ///
  /// - Parameter str: The string to match against.
  /// - Parameter at: The index to start matching.
  /// - Parameter options: Options for the match operation.
  /// - Returns: The index of the end of the match, or `nil` if there is no match.
  func matches(in str: String, at i: String.Index, with options: MatchingOptions) -> String.Index? {
    // FIXME: This is only called in custom character classes that contain builtin
    // character classes as members (ie: [a\w] or set operations), is there
    // any way to avoid that? Can we remove this somehow?
    switch matchLevel {
    case .graphemeCluster:
      let c = str[i]
      var matched: Bool
      var next = str.index(after: i)
      switch cc {
      case .any, .anyGrapheme: matched = true
      case .anyScalar:
        matched = true
        next = str.unicodeScalars.index(after: i)
      case .digit:
        matched = c.isNumber && (c.isASCII || !options.usesASCIIDigits)
      case .horizontalWhitespace:
        matched = c.unicodeScalars.first?.isHorizontalWhitespace == true
          && (c.isASCII || !options.usesASCIISpaces)
      case .newlineSequence, .verticalWhitespace:
        matched = c.unicodeScalars.first?.isNewline == true
          && (c.isASCII || !options.usesASCIISpaces)
      case .whitespace:
        matched = c.isWhitespace && (c.isASCII || !options.usesASCIISpaces)
      case .word:
        matched = c.isWordCharacter && (c.isASCII || !options.usesASCIIWord)
      }
      if isInverted {
        matched.toggle()
      }
      return matched ? next : nil
    case .unicodeScalar:
      let c = str.unicodeScalars[i]
      var nextIndex = str.unicodeScalars.index(after: i)
      var matched: Bool
      switch cc {
      case .any: matched = true
      case .anyScalar: matched = true
      case .anyGrapheme:
        matched = true
        nextIndex = str.index(after: i)
      case .digit:
        matched = c.properties.numericType != nil && (c.isASCII || !options.usesASCIIDigits)
      case .horizontalWhitespace:
        matched = c.isHorizontalWhitespace && (c.isASCII || !options.usesASCIISpaces)
      case .verticalWhitespace:
        matched = c.isNewline && (c.isASCII || !options.usesASCIISpaces)
      case .newlineSequence:
        matched = c.isNewline && (c.isASCII || !options.usesASCIISpaces)
        if c == "\r" && nextIndex != str.endIndex && str.unicodeScalars[nextIndex] == "\n" {
          str.unicodeScalars.formIndex(after: &nextIndex)
        }
      case .whitespace:
        matched = c.properties.isWhitespace && (c.isASCII || !options.usesASCIISpaces)
      case .word:
        matched = (c.properties.isAlphabetic || c == "_") && (c.isASCII || !options.usesASCIIWord)
      }
      if isInverted {
        matched.toggle()
      }
      return matched ? nextIndex : nil
    }
  }
}

extension _CharacterClassModel {
  static var any: _CharacterClassModel {
    .init(cc: .any, matchLevel: .graphemeCluster)
  }

  static var anyGrapheme: _CharacterClassModel {
    .init(cc: .anyGrapheme, matchLevel: .graphemeCluster)
  }

  static var anyUnicodeScalar: _CharacterClassModel {
    .init(cc: .any, matchLevel: .unicodeScalar)
  }

  static var whitespace: _CharacterClassModel {
    .init(cc: .whitespace, matchLevel: .graphemeCluster)
  }
  
  static var digit: _CharacterClassModel {
    .init(cc: .digit, matchLevel: .graphemeCluster)
  }

  static var horizontalWhitespace: _CharacterClassModel {
    .init(cc: .horizontalWhitespace, matchLevel: .graphemeCluster)
  }

  static var newlineSequence: _CharacterClassModel {
    .init(cc: .newlineSequence, matchLevel: .graphemeCluster)
  }

  static var verticalWhitespace: _CharacterClassModel {
    .init(cc: .verticalWhitespace, matchLevel: .graphemeCluster)
  }

  static var word: _CharacterClassModel {
    .init(cc: .word, matchLevel: .graphemeCluster)
  }
}

extension _CharacterClassModel.Representation: CustomStringConvertible {
  var description: String {
    switch self {
    case .any: return "<any>"
    case .anyGrapheme: return "<any grapheme>"
    case .anyScalar: return "<any scalar>"
    case .digit: return "<digit>"
    case .horizontalWhitespace: return "<horizontal whitespace>"
    case .newlineSequence: return "<newline sequence>"
    case .verticalWhitespace: return "vertical whitespace"
    case .whitespace: return "<whitespace>"
    case .word: return "<word>"
    }
  }
}

extension _CharacterClassModel: CustomStringConvertible {
  var description: String {
    return "\(isInverted ? "not " : "")\(cc)"
  }
}

extension _CharacterClassModel {
  func withMatchLevel(
    _ level: _CharacterClassModel.MatchLevel
  ) -> _CharacterClassModel {
    var cc = self
    cc.matchLevel = level
    return cc
  }
}

extension DSLTree.Atom.CharacterClass {
    var model: _CharacterClassModel {
    switch self {
    case .digit:    return .digit
    case .notDigit: return .digit.inverted

    case .horizontalWhitespace: return .horizontalWhitespace
    case .notHorizontalWhitespace:
      return .horizontalWhitespace.inverted

    case .newlineSequence: return .newlineSequence

    // FIXME: This is more like '.' than inverted '\R', as it is affected
    // by e.g (*CR). We should therefore really be emitting it through
    // emitDot(). For now we treat it as semantically invalid.
    case .notNewline: return .newlineSequence.inverted

    case .whitespace:    return .whitespace
    case .notWhitespace: return .whitespace.inverted

    case .verticalWhitespace:    return .verticalWhitespace
    case .notVerticalWhitespace: return .verticalWhitespace.inverted

    case .word:    return .word
    case .notWord: return .word.inverted

    case .anyGrapheme: return .anyGrapheme
    case .anyUnicodeScalar: return .anyUnicodeScalar
    }
  }
}
