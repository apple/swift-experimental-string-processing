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
  let cc: Representation
  
  /// The level (character or Unicode scalar) at which to match.
  let matchLevel: MatchingOptions.SemanticLevel
  
  /// If this character character class only matches ascii characters
  let isStrictASCII: Bool

  /// Whether this character class matches against an inverse,
  /// e.g \D, \S, [^abc].
  let isInverted: Bool

  init(
    cc: Representation,
    options: MatchingOptions,
    isInverted: Bool
  ) {
    self.cc = cc
    self.matchLevel = options.semanticLevel
    self.isStrictASCII = cc.isStrictAscii(options: options)
    self.isInverted = isInverted
  }

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
  
  /// Returns the end of the match of this character class in the string.
  ///
  /// - Parameter str: The string to match against.
  /// - Parameter at: The index to start matching.
  /// - Parameter options: Options for the match operation.
  /// - Returns: The index of the end of the match, or `nil` if there is no match.
  func matches(
    in input: String,
    at currentPosition: String.Index
  ) -> String.Index? {
    // FIXME: This is only called in custom character classes that contain builtin
    // character classes as members (ie: [a\w] or set operations), is there
    // any way to avoid that? Can we remove this somehow?
    guard currentPosition != input.endIndex else {
      return nil
    }

    let isScalarSemantics = matchLevel == .unicodeScalar

    // ASCII fast-path
    if let (next, result) = input._quickMatch(
      cc, at: currentPosition, isScalarSemantics: isScalarSemantics
    ) {
      return result == isInverted ? nil : next
    }

    let char = input[currentPosition]
    let scalar = input.unicodeScalars[currentPosition]

    let asciiCheck = !isStrictASCII
      || (scalar.isASCII && isScalarSemantics)
      || char.isASCII
    
    var matched: Bool
    var next: String.Index
    switch (isScalarSemantics, cc) {
    case (_, .anyGrapheme):
      next = input.index(after: currentPosition)
    case (_, .anyScalar):
      // FIXME: This allows us to be not-scalar aligned when in grapheme mode
      // Should this even be allowed?
      next = input.unicodeScalars.index(after: currentPosition)
    case (true, _):
      next = input.unicodeScalars.index(after: currentPosition)
    case (false, _):
      next = input.index(after: currentPosition)
    }

    switch cc {
    case .any, .anyGrapheme, .anyScalar:
      matched = true
    case .digit:
      if isScalarSemantics {
        matched = scalar.properties.numericType != nil && asciiCheck
      } else {
        matched = char.isNumber && asciiCheck
      }
    case .horizontalWhitespace:
      if isScalarSemantics {
        matched = scalar.isHorizontalWhitespace && asciiCheck
      } else {
        matched = char._isHorizontalWhitespace && asciiCheck
      }
    case .verticalWhitespace:
      if isScalarSemantics {
        matched = scalar.isNewline && asciiCheck
      } else {
        matched = char._isNewline && asciiCheck
      }
    case .newlineSequence:
      if isScalarSemantics {
        matched = scalar.isNewline && asciiCheck
        if matched && scalar == "\r"
            && next != input.endIndex && input.unicodeScalars[next] == "\n" {
          // Match a full CR-LF sequence even in scalar sematnics
          input.unicodeScalars.formIndex(after: &next)
        }
      } else {
        matched = char._isNewline && asciiCheck
      }
    case .whitespace:
      if isScalarSemantics {
        matched = scalar.properties.isWhitespace && asciiCheck
      } else {
        matched = char.isWhitespace && asciiCheck
      }
    case .word:
      if isScalarSemantics {
        matched = scalar.properties.isAlphabetic && asciiCheck
      } else {
        matched = char.isWordCharacter && asciiCheck
      }
    }
    if isInverted {
      matched.toggle()
    }
    if matched {
      return next
    } else {
      return nil
    }
  }
}

extension _CharacterClassModel {
  var consumesSingleGrapheme: Bool {
   switch self.cc {
    case .anyScalar: return false
    default: return true
    }
  }
}

extension _CharacterClassModel.Representation {
  /// Returns true if this CharacterClass should be matched by strict ascii under the given options
  func isStrictAscii(options: MatchingOptions) -> Bool {
    switch self {
    case .digit: return options.usesASCIIDigits
    case .horizontalWhitespace: return options.usesASCIISpaces
    case .newlineSequence: return options.usesASCIISpaces
    case .verticalWhitespace: return options.usesASCIISpaces
    case .whitespace: return options.usesASCIISpaces
    case .word: return options.usesASCIIWord
    default: return false
    }
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

extension DSLTree.Atom.CharacterClass {
  /// Converts this DSLTree CharacterClass into our runtime representation
  func asRuntimeModel(_ options: MatchingOptions) -> _CharacterClassModel {
    let cc: _CharacterClassModel.Representation
    var inverted = false
    switch self {
    case .digit:
      cc = .digit
    case .notDigit:
      cc = .digit
      inverted = true

    case .horizontalWhitespace:
      cc = .horizontalWhitespace
    case .notHorizontalWhitespace:
      cc = .horizontalWhitespace
      inverted = true

    case .newlineSequence:
      cc = .newlineSequence

    // FIXME: This is more like '.' than inverted '\R', as it is affected
    // by e.g (*CR). We should therefore really be emitting it through
    // emitDot(). For now we treat it as semantically invalid.
    case .notNewline:
      cc = .newlineSequence
      inverted = true

    case .whitespace:
      cc = .whitespace
    case .notWhitespace:
      cc = .whitespace
      inverted = true

    case .verticalWhitespace:
      cc = .verticalWhitespace
    case .notVerticalWhitespace:
      cc = .verticalWhitespace
      inverted = true

    case .word:
      cc = .word
    case .notWord:
      cc = .word
      inverted = true

    case .anyGrapheme:
      cc = .anyGrapheme
    case .anyUnicodeScalar:
      cc = .anyScalar
    }
    return _CharacterClassModel(cc: cc, options: options, isInverted: inverted)
  }
}
