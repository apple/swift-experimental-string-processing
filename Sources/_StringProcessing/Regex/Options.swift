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

@available(SwiftStdlib 5.7, *)
extension RegexComponent {
  /// Returns a regular expression that ignores case when matching.
  ///
  /// - Parameter ignoresCase: A Boolean value indicating whether to ignore case.
  /// - Returns: The modified regular expression.
  public func ignoresCase(_ ignoresCase: Bool = true) -> Regex<RegexOutput> {
    wrapInOption(.caseInsensitive, addingIf: ignoresCase)
  }

  /// Returns a regular expression that matches only ASCII characters as word
  /// characters.
  ///
  /// - Parameter useASCII: A Boolean value indicating whether to match only
  ///   ASCII characters as word characters.
  /// - Returns: The modified regular expression.
  public func asciiOnlyClasses(_ kinds: RegexCharacterClassKind = .all) -> Regex<RegexOutput> {
    if kinds == [] {
      return Regex(node: .nonCapturingGroup(
        .init(ast: .changeMatchingOptions(AST.MatchingOptionSequence(removing: [
          .init(.asciiOnlyDigit, location: .fake),
          .init(.asciiOnlySpace, location: .fake),
          .init(.asciiOnlyWord, location: .fake),
          .init(.asciiOnlyPOSIXProps, location: .fake),
        ]))), regex.root))
    }
    return self
      .wrapInOption(.asciiOnlyDigit, addingIf: kinds.contains(.digit))
      .wrapInOption(.asciiOnlySpace, addingIf: kinds.contains(.whitespace))
      .wrapInOption(.asciiOnlyWord, addingIf: kinds.contains(.wordCharacter))
      .wrapInOption(.asciiOnlyPOSIXProps, addingIf: kinds.contains(.all))
  }

  /// Returns a regular expression that uses the specified word boundary algorithm.
  ///
  /// - Parameter wordBoundaryKind: The algorithm to use for determining word boundaries.
  /// - Returns: The modified regular expression.
  public func wordBoundaryKind(_ wordBoundaryKind: RegexWordBoundaryKind) -> Regex<RegexOutput> {
    wrapInOption(.unicodeWordBoundaries, addingIf: wordBoundaryKind == .defaultBoundaries)
  }
  
  /// Returns a regular expression where the start and end of input
  /// anchors (`^` and `$`) also match against the start and end of a line.
  ///
  /// - Parameter dotMatchesNewlines: A Boolean value indicating whether `.`
  ///   should match a newline character.
  /// - Returns: The modified regular expression.
  public func dotMatchesNewlines(_ dotMatchesNewlines: Bool = true) -> Regex<RegexOutput> {
    wrapInOption(.singleLine, addingIf: dotMatchesNewlines)
  }
  
  /// Returns a regular expression where the start and end of input
  /// anchors (`^` and `$`) also match against the start and end of a line.
  ///
  /// This method corresponds to applying the `m` option in regex syntax. For
  /// this behavior in the `RegexBuilder` syntax, see
  /// ``Anchor.startOfLine``, ``Anchor.endOfLine``, ``Anchor.startOfInput``,
  /// and ``Anchor.endOfInput``.
  ///
  /// - Parameter matchLineEndings: A Boolean value indicating whether `^` and
  ///   `$` should match the start and end of lines, respectively.
  /// - Returns: The modified regular expression.
  public func anchorsMatchLineEndings(_ matchLineEndings: Bool = true) -> Regex<RegexOutput> {
    wrapInOption(.multiline, addingIf: matchLineEndings)
  }
  
  /// Returns a regular expression where quantifiers use the specified behavior
  /// by default.
  ///
  /// You can call this method to change the default repetition behavior for
  /// quantifier operators in regex syntax and `RegexBuilder` quantifier
  /// methods. For example, in the following example, both regexes use
  /// possessive quantification when matching a quotation surround by `"`
  /// quote marks:
  ///
  ///     let regex1 = /"[^"]*"/.defaultRepetitionBehavior(.possessive)
  ///
  ///     let quoteMark = "\""
  ///     let regex2 = Regex {
  ///         quoteMark
  ///         ZeroOrMore(.noneOf(quoteMark))
  ///         quoteMark
  ///     }.defaultRepetitionBehavior(.possessive)
  ///
  /// This setting only changes the default behavior of quantifiers, and does
  /// not affect regex syntax operators with an explicit behavior indicator,
  /// such as `*?` or `++`. Likewise, calls to quantifier methods such as
  /// `OneOrMore` always use the explicit `behavior`, when given.
  ///
  /// - Parameter behavior: The default behavior to use for quantifiers.
  public func defaultRepetitionBehavior(_ behavior: RegexRepetitionBehavior) -> Regex<RegexOutput> {
    if behavior == .possessive {
      return wrapInOption(.possessiveByDefault, addingIf: true)
    } else {
      return wrapInOption(.reluctantByDefault, addingIf: behavior == .reluctant)
    }
  }

  /// Returns a regular expression that matches with the specified semantic
  /// level.
  ///
  /// When matching with grapheme cluster semantics (the default),
  /// metacharacters like `.` and `\w`, custom character classes, and character
  /// class instances like `.any` match a grapheme cluster when possible,
  /// corresponding with the default string representation. In addition,
  /// matching with grapheme cluster semantics compares characters using their
  /// canonical representation, corresponding with how strings comparison works.
  ///
  /// When matching with Unicode scalar semantics, metacharacters and character
  /// classes always match a single Unicode scalar value, even if that scalar
  /// comprises part of a grapheme cluster.
  ///
  /// These semantic levels can lead to different results, especially when
  /// working with strings that have decomposed characters. In the following
  /// example, `queRegex` matches any 3-character string that begins with `"q"`.
  ///
  ///     let composed = "qué"
  ///     let decomposed = "que\u{301}"
  ///
  ///     let queRegex = /^q..$/
  ///
  ///     print(composed.contains(queRegex))
  ///     // Prints "true"
  ///     print(decomposed.contains(queRegex))
  ///     // Prints "true"
  ///
  /// When using Unicode scalar semantics, however, the regular expression only
  /// matches the composed version of the string, because each `.` matches a
  /// single Unicode scalar value.
  ///
  ///     let queRegexScalar = queRegex.matchingSemantics(.unicodeScalar)
  ///     print(composed.contains(queRegexScalar))
  ///     // Prints "true"
  ///     print(decomposed.contains(queRegexScalar))
  ///     // Prints "false"
  ///
  /// - Parameter semanticLevel: The semantics to use during matching.
  /// - Returns: The modified regular expression.
  public func matchingSemantics(_ semanticLevel: RegexSemanticLevel) -> Regex<RegexOutput> {
    switch semanticLevel.base {
    case .graphemeCluster:
      return wrapInOption(.graphemeClusterSemantics, addingIf: true)
    case .unicodeScalar:
      return wrapInOption(.unicodeScalarSemantics, addingIf: true)
    }
  }
}

/// A built-in regex character class kind.
///
/// Pass one or more `RegexCharacterClassKind` classes to `asciiOnlyClasses(_:)`
/// to control whether character classes match any character or only members
/// of the ASCII character set.
@available(SwiftStdlib 5.7, *)
public struct RegexCharacterClassKind: OptionSet, Hashable {
  public var rawValue: Int
  
  public init(rawValue: Int) {
    self.rawValue = rawValue
  }

  /// Regex digit-matching character classes, like `\d`, `[:digit:]`, and
  /// `\p{HexDigit}`.
  public static var digit: RegexCharacterClassKind {
    .init(rawValue: 1)
  }

  /// Regex whitespace-matching character classes, like `\s`, `[:space:]`,
  /// and `\p{Whitespace}`.
  public static var whitespace: RegexCharacterClassKind {
    .init(rawValue: 1 << 1)
  }

  /// Regex word character-matching character classes, like `\w`.
  public static var wordCharacter: RegexCharacterClassKind {
    .init(rawValue: 1 << 2)
  }

  /// All built-in regex character classes.
  public static var all: RegexCharacterClassKind {
    .init(rawValue: 1 << 3)
  }

  /// No built-in regex character classes.
  public static var none: RegexCharacterClassKind { [] }
}

/// A semantic level to use during regex matching.
@available(SwiftStdlib 5.7, *)
public struct RegexSemanticLevel: Hashable {
  internal enum Representation {
    case graphemeCluster
    case unicodeScalar
  }
  
  internal var base: Representation
  
  /// Match at the character level.
  ///
  /// At this semantic level, each matched element is a `Character` value.
  /// This is the default semantic level.
  public static var graphemeCluster: RegexSemanticLevel {
    .init(base: .graphemeCluster)
  }
  
  /// Match at the Unicode scalar level.
  ///
  /// At this semantic level, the string's `UnicodeScalarView` is used for matching,
  /// and each matched element is a `UnicodeScalar` value.
  public static var unicodeScalar: RegexSemanticLevel {
    .init(base: .unicodeScalar)
  }
}

/// A word boundary algorithm to use during regex matching.
@available(SwiftStdlib 5.7, *)
public struct RegexWordBoundaryKind: Hashable {
  internal enum Representation {
    case unicodeLevel1
    case unicodeLevel2
  }
  
  internal var base: Representation

  /// A word boundary algorithm that implements the "simple word boundary"
  /// Unicode recommendation.
  ///
  /// A simple word boundary is a position in the input between two characters
  /// that match `/\w\W/` or `/\W\w/`, or between the start or end of the input
  /// and a `\w` character. Word boundaries therefore depend on the option-
  /// defined behavior of `\w`.
  public static var simpleBoundaries: Self {
    .init(base: .unicodeLevel1)
  }

  /// A word boundary algorithm that implements the "default word boundary"
  /// Unicode recommendation.
  ///
  /// Default word boundaries use a Unicode algorithm that handles some cases
  /// better than simple word boundaries, such as words with internal
  /// punctuation, changes in script, and Emoji.
  public static var defaultBoundaries: Self {
    .init(base: .unicodeLevel2)
  }
}

/// Specifies how much to attempt to match when using a quantifier.
@available(SwiftStdlib 5.7, *)
public struct RegexRepetitionBehavior: Hashable {
  internal enum Kind {
    case eager
    case reluctant
    case possessive
  }

  var kind: Kind

  @_spi(RegexBuilder) public var dslTreeKind: DSLTree._AST.QuantificationKind {
    switch kind {
    case .eager: return .eager
    case .reluctant: return .reluctant
    case .possessive: return .possessive
    }
  }
}

@available(SwiftStdlib 5.7, *)
extension RegexRepetitionBehavior {
  /// Match as much of the input string as possible, backtracking when
  /// necessary.
  public static var eager: Self {
    .init(kind: .eager)
  }

  /// Match as little of the input string as possible, expanding the matched
  /// region as necessary to complete a match.
  public static var reluctant: Self {
    .init(kind: .reluctant)
  }

  /// Match as much of the input string as possible, performing no backtracking.
  public static var possessive: Self {
    .init(kind: .possessive)
  }
}

// MARK: - Helper method

@available(SwiftStdlib 5.7, *)
extension RegexComponent {
  fileprivate func wrapInOption(
    _ option: AST.MatchingOption.Kind,
    addingIf shouldAdd: Bool) -> Regex<RegexOutput>
  {
    let sequence = shouldAdd
      ? AST.MatchingOptionSequence(adding: [.init(option, location: .fake)])
      : AST.MatchingOptionSequence(removing: [.init(option, location: .fake)])
    return Regex(node: .nonCapturingGroup(
      .init(ast: .changeMatchingOptions(sequence)), regex.root))
  }
}
