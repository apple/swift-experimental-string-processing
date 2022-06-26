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

extension AST {
  public struct Atom: Hashable, _ASTNode {
    public let kind: Kind
    public let location: SourceLocation

    public init(_ k: Kind, _ loc: SourceLocation) {
      self.kind = k
      self.location = loc
    }

    public enum Kind: Hashable {
      /// Just a character
      ///
      /// A, \*, \\, ...
      case char(Character)

      /// A Unicode scalar value written as a literal
      ///
      /// \u{...}, \0dd, \x{...}, ...
      case scalar(Scalar)

      /// A whitespace-separated sequence of Unicode scalar values which are
      /// implicitly splatted out.
      ///
      /// `\u{A B C}` -> `\u{A}\u{B}\u{C}`
      case scalarSequence(ScalarSequence)

      /// A Unicode property, category, or script, including those written using
      /// POSIX syntax.
      ///
      /// \p{...}, \p{^...}, \P, [:...:], [:^...:]
      case property(CharacterProperty)

      /// A built-in escaped character
      ///
      /// Literal escapes: \n, \t ...
      /// Character classes: \s, \w ...
      /// \n, \s, \Q, \b, \A, \K, ...
      case escaped(EscapedBuiltin) // TODO: expand this out

      /// A control character
      ///
      /// \cx, \C-x, \M-x, \M-\C-x, ...
      case keyboardControl(Character)
      case keyboardMeta(Character)        // Oniguruma
      case keyboardMetaControl(Character) // Oniguruma

      /// A named character \N{...}
      case namedCharacter(String)

      /// .
      case any

      /// ^
      case startOfLine

      /// $
      case endOfLine

      // References
      case backreference(Reference)
      case subpattern(Reference)

      // (?C)
      case callout(Callout)

      // (*ACCEPT), (*FAIL), ...
      case backtrackingDirective(BacktrackingDirective)

      // (?i), (?i-m), ...
      case changeMatchingOptions(MatchingOptionSequence)
    }
  }
}

extension AST.Atom {
  private var _associatedValue: Any? {
    switch kind {
    case .char(let v):                  return v
    case .scalar(let v):                return v
    case .scalarSequence(let v):        return v
    case .property(let v):              return v
    case .escaped(let v):               return v
    case .keyboardControl(let v):       return v
    case .keyboardMeta(let v):          return v
    case .keyboardMetaControl(let v):   return v
    case .namedCharacter(let v):        return v
    case .backreference(let v):         return v
    case .subpattern(let v):            return v
    case .callout(let v):               return v
    case .backtrackingDirective(let v): return v
    case .changeMatchingOptions(let v): return v
    case .any:                          return nil
    case .startOfLine:                  return nil
    case .endOfLine:                    return nil
    }
  }

  func `as`<T>(_ t: T.Type = T.self) -> T? {
    _associatedValue as? T
  }
}

extension AST.Atom {
  public struct Scalar: Hashable {
    public var value: UnicodeScalar
    public var location: SourceLocation

    public init(_ value: UnicodeScalar, _ location: SourceLocation) {
      self.value = value
      self.location = location
    }
  }

  public struct ScalarSequence: Hashable {
    public var scalars: [Scalar]
    public var trivia: [AST.Trivia]

    public init(_ scalars: [Scalar], trivia: [AST.Trivia]) {
      precondition(scalars.count > 1, "Expected multiple scalars")
      self.scalars = scalars
      self.trivia = trivia
    }
    public var scalarValues: [Unicode.Scalar] { scalars.map(\.value) }
  }
}

extension AST.Atom {

  // TODO: We might scrap this and break out a few categories so
  // we can pull in `^`, `$`, and `.`, but we probably want to
  // just provide API instead, since that can transcend
  // taxonomies.

  // Characters, character types, literals, etc., derived from
  // an escape sequence.
  public enum EscapedBuiltin: Hashable {
    // TODO: better doc comments

    // Literal single characters

    /// \a
    case alarm

    /// \e
    case escape

    /// \f
    case formfeed

    /// \n
    case newline

    /// \r
    case carriageReturn

    /// \t
    case tab

    // Character types

    /// \C
    case singleDataUnit

    /// \d
    case decimalDigit

    /// \D
    case notDecimalDigit

    /// \h
    case horizontalWhitespace

    /// \H
    case notHorizontalWhitespace

    /// \N
    case notNewline

    /// \R
    case newlineSequence

    /// \s
    case whitespace

    /// \S
    case notWhitespace

    /// \v
    case verticalTab

    /// \V
    case notVerticalTab

    /// \w
    case wordCharacter

    /// \W
    case notWordCharacter

    /// \b (from within a custom character class)
    case backspace

    // Consumers?

    /// \X
    case graphemeCluster

    // Assertions

    /// \b (from outside a custom character class)
    case wordBoundary

    /// \B
    case notWordBoundary

    // Anchors

    /// \A
    case startOfSubject

    /// \Z
    case endOfSubjectBeforeNewline

    /// \z
    case endOfSubject

    /// \G
    case firstMatchingPositionInSubject

    // Other

    /// \K
    case resetStartOfMatch

    // Oniguruma

    /// \O
    case trueAnychar

    /// \y
    case textSegment

    /// \Y
    case notTextSegment
  }
}

extension AST.Atom.EscapedBuiltin {
  public var character: Character {
    switch self {
    // Literal single characters
    case .alarm:          return "a"
    case .escape:         return "e"
    case .formfeed:       return "f"
    case .newline:        return "n"
    case .carriageReturn: return "r"
    case .tab:            return "t"

    // Character types
    case .singleDataUnit:          return "C"
    case .decimalDigit:            return "d"
    case .notDecimalDigit:         return "D"
    case .horizontalWhitespace:    return "h"
    case .notHorizontalWhitespace: return "H"
    case .notNewline:              return "N"
    case .newlineSequence:         return "R"
    case .whitespace:              return "s"
    case .notWhitespace:           return "S"
    case .verticalTab:             return "v"
    case .notVerticalTab:          return "V"
    case .wordCharacter:           return "w"
    case .notWordCharacter:        return "W"

    case .graphemeCluster:         return "X"

    // Assertions
    case .backspace:       return "b" // inside custom cc
    case .wordBoundary:    return "b" // outside custom cc
    case .notWordBoundary: return "B"

    // Anchors
    case .startOfSubject:                 return "A"
    case .endOfSubjectBeforeNewline:      return "Z"
    case .endOfSubject:                   return "z"
    case .firstMatchingPositionInSubject: return "G"

    // Other
    case .resetStartOfMatch: return "K"

    // Oniguruma
    case .trueAnychar: return "O"
    case .textSegment: return "y"
    case .notTextSegment: return "Y"
    }
  }
  private static func fromCharacter(
    _ c: Character, inCustomCharacterClass customCC: Bool
  ) -> Self? {
    // Valid both inside and outside custom character classes.
    switch c {
    // Literal single characters
    case "a": return .alarm
    case "e": return .escape
    case "f": return .formfeed
    case "n": return .newline
    case "r": return .carriageReturn
    case "t": return .tab

    // Character types
    case "d": return .decimalDigit
    case "D": return .notDecimalDigit
    case "h": return .horizontalWhitespace
    case "H": return .notHorizontalWhitespace
    case "s": return .whitespace
    case "S": return .notWhitespace
    case "v": return .verticalTab
    case "V": return .notVerticalTab
    case "w": return .wordCharacter
    case "W": return .notWordCharacter

    // Assertions
    case "b": return customCC ? .backspace : .wordBoundary

    default: break
    }

    // The following are only valid outside custom character classes.
    guard !customCC else { return nil }
    switch c {
    // Character types
    case "C": return .singleDataUnit
    case "N": return .notNewline
    case "R": return .newlineSequence

    case "X": return .graphemeCluster

    // Assertions
    case "B": return .notWordBoundary

    // Anchors
    case "A": return .startOfSubject
    case "Z": return .endOfSubjectBeforeNewline
    case "z": return .endOfSubject
    case "G": return .firstMatchingPositionInSubject

    // Other
    case "K": return .resetStartOfMatch

    // Oniguruma
    case "O": return .trueAnychar
    case "y": return .textSegment
    case "Y": return .notTextSegment

    default: return nil
    }
  }
  public init?(_ c: Character, inCustomCharacterClass customCC: Bool) {
    guard let builtin = Self.fromCharacter(c, inCustomCharacterClass: customCC)
    else { return nil }
    self = builtin
  }
}

extension AST.Atom {
  public struct CharacterProperty: Hashable {
    public var kind: Kind

    /// Whether this is an inverted property e.g '\P{Ll}', '[:^ascii:]'.
    public var isInverted: Bool

    /// Whether this property was written using POSIX syntax e.g '[:ascii:]'.
    public var isPOSIX: Bool

    public init(_ kind: Kind, isInverted: Bool, isPOSIX: Bool) {
      self.kind = kind
      self.isInverted = isInverted
      self.isPOSIX = isPOSIX
    }

    public var _dumpBase: String {
      // FIXME: better printing...
      "\(kind)\(isInverted)\(isPOSIX)"
    }
  }
}

extension AST.Atom.CharacterProperty {
  public enum Kind: Hashable {
    /// Matches any character, equivalent to Oniguruma's '\O'.
    case any

    // The inverse of 'Unicode.ExtendedGeneralCategory.unassigned'.
    case assigned

    /// All ascii characters U+00...U+7F
    case ascii

    /// A general category property.
    case generalCategory(Unicode.ExtendedGeneralCategory)

    /// Binary character properties. Note that only the following are required
    /// by UTS#18 Level 1:
    /// - Alphabetic
    /// - Uppercase
    /// - Lowercase
    /// - White_Space
    /// - Noncharacter_Code_Point
    /// - Default_Ignorable_Code_Point
    case binary(Unicode.BinaryProperty, value: Bool = true)

    /// Character script and script extensions.
    case script(Unicode.Script)
    case scriptExtension(Unicode.Script)

    /// Character name in the form `\p{name=...}`
    case named(String)
    
    /// Numeric type.
    case numericType(Unicode.NumericType)
    
    /// Numeric value.
    case numericValue(Double)
    
    /// Case mapping.
    case mapping(MapKind, String)
    
    /// Canonical Combining Class.
    case ccc(Unicode.CanonicalCombiningClass)
    
    /// Character age, as per UnicodeScalar.Properties.age.
    case age(major: Int, minor: Int)

    /// A block property.
    case block(Unicode.Block)

    case posix(Unicode.POSIXProperty)

    /// Some special properties implemented by PCRE and Oniguruma.
    case pcreSpecial(PCRESpecialCategory)

    /// Some special properties implemented by Java.
    case javaSpecial(JavaSpecial)

    public enum MapKind: Hashable {
      case lowercase
      case uppercase
      case titlecase
    }
  }

  public enum PCRESpecialCategory: String, Hashable {
    case alphanumeric     = "Xan"
    case posixSpace       = "Xps"
    case perlSpace        = "Xsp"
    case universallyNamed = "Xuc"
    case perlWord         = "Xwd"
  }

  /// Special Java properties that correspond to methods on
  /// `java.lang.Character`, with the `java` prefix replaced by `is`.
  public enum JavaSpecial: String, Hashable, CaseIterable {
    case alphabetic             = "javaAlphabetic"
    case defined                = "javaDefined"
    case digit                  = "javaDigit"
    case identifierIgnorable    = "javaIdentifierIgnorable"
    case ideographic            = "javaIdeographic"
    case isoControl             = "javaISOControl"
    case javaIdentifierPart     = "javaJavaIdentifierPart" // not a typo, that's actually the name
    case javaIdentifierStart    = "javaJavaIdentifierStart" // not a typo, that's actually the name
    case javaLetter             = "javaLetter"
    case javaLetterOrDigit      = "javaLetterOrDigit"
    case lowerCase              = "javaLowerCase"
    case mirrored               = "javaMirrored"
    case spaceChar              = "javaSpaceChar"
    case titleCase              = "javaTitleCase"
    case unicodeIdentifierPart  = "javaUnicodeIdentifierPart"
    case unicodeIdentifierStart = "javaUnicodeIdentifierStart"
    case upperCase              = "javaUpperCase"
    case whitespace             = "javaWhitespace"
  }
}

extension AST.Atom {
  /// Anchors and other built-in zero-width assertions.
  public enum AssertionKind: String, Hashable {
    /// \A
    case startOfSubject = #"\A"#

    /// \Z
    case endOfSubjectBeforeNewline = #"\Z"#

    /// \z
    case endOfSubject = #"\z"#

    /// \K
    case resetStartOfMatch = #"\K"#

    /// \G
    case firstMatchingPositionInSubject = #"\G"#

    /// \y
    case textSegment = #"\y"#

    /// \Y
    case notTextSegment = #"\Y"#

    /// ^
    case startOfLine = #"^"#

    /// $
    case endOfLine = #"$"#

    /// \b (from outside a custom character class)
    case wordBoundary = #"\b"#

    /// \B
    case notWordBoundary = #"\B"#

  }

  public var assertionKind: AssertionKind? {
    switch kind {
    case .startOfLine:     return .startOfLine
    case .endOfLine:       return .endOfLine

    case .escaped(.wordBoundary):    return .wordBoundary
    case .escaped(.notWordBoundary): return .notWordBoundary
    case .escaped(.startOfSubject):  return .startOfSubject
    case .escaped(.endOfSubject):    return .endOfSubject
    case .escaped(.textSegment):     return .textSegment
    case .escaped(.notTextSegment):  return .notTextSegment
    case .escaped(.endOfSubjectBeforeNewline):
      return .endOfSubjectBeforeNewline
    case .escaped(.firstMatchingPositionInSubject):
      return .firstMatchingPositionInSubject

    case .escaped(.resetStartOfMatch): return .resetStartOfMatch

    default: return nil
    }
  }
}

extension AST.Atom {
  public enum Callout: Hashable {
    /// A PCRE callout written `(?C...)`
    public struct PCRE: Hashable {
      public enum Argument: Hashable {
        case number(Int)
        case string(String)
      }
      public var arg: AST.Located<Argument>

      public init(_ arg: AST.Located<Argument>) {
        self.arg = arg
      }

      /// Whether the argument isn't written explicitly in the source, e.g
      /// `(?C)` which is implicitly `(?C0)`.
      public var isImplicit: Bool { arg.location.isEmpty }
    }

    /// A named Oniguruma callout written `(*name[tag]{args, ...})`
    public struct OnigurumaNamed: Hashable {
      public struct ArgList: Hashable {
        public var leftBrace: SourceLocation
        public var args: [AST.Located<String>]
        public var rightBrace: SourceLocation

        public init(
          _ leftBrace: SourceLocation,
          _ args: [AST.Located<String>],
          _ rightBrace: SourceLocation
        ) {
          self.leftBrace = leftBrace
          self.args = args
          self.rightBrace = rightBrace
        }
      }

      public var name: AST.Located<String>
      public var tag: OnigurumaTag?
      public var args: ArgList?

      public init(
        _ name: AST.Located<String>, tag: OnigurumaTag?, args: ArgList?
      ) {
        self.name = name
        self.tag = tag
        self.args = args
      }
    }

    /// An Oniguruma callout 'of contents', written `(?{...}[tag]D)`
    public struct OnigurumaOfContents: Hashable {
      public enum Direction: Hashable {
        case inProgress   // > (the default)
        case inRetraction // <
        case both         // X
      }
      public var openBraces: SourceLocation
      public var contents: AST.Located<String>
      public var closeBraces: SourceLocation
      public var tag: OnigurumaTag?
      public var direction: AST.Located<Direction>

      public init(
        _ openBraces: SourceLocation, _ contents: AST.Located<String>,
        _ closeBraces: SourceLocation, tag: OnigurumaTag?,
        direction: AST.Located<Direction>
      ) {
        self.openBraces = openBraces
        self.contents = contents
        self.closeBraces = closeBraces
        self.tag = tag
        self.direction = direction
      }

      /// Whether the direction flag isn't written explicitly in the
      /// source, e.g `(?{x})` which is implicitly `(?{x}>)`.
      public var isDirectionImplicit: Bool { direction.location.isEmpty }
    }
    case pcre(PCRE)
    case onigurumaNamed(OnigurumaNamed)
    case onigurumaOfContents(OnigurumaOfContents)

    private var _associatedValue: Any {
      switch self {
      case .pcre(let v):                return v
      case .onigurumaNamed(let v):      return v
      case .onigurumaOfContents(let v): return v
      }
    }

    func `as`<T>(_ t: T.Type = T.self) -> T? {
      _associatedValue as? T
    }
  }
}

extension AST.Atom.Callout {
  /// A tag specifier `[...]` that can appear in an Oniguruma callout.
  public struct OnigurumaTag: Hashable {
    public var leftBracket: SourceLocation
    public var name: AST.Located<String>
    public var rightBracket: SourceLocation

    public init(
      _ leftBracket: SourceLocation,
      _ name: AST.Located<String>,
      _ rightBracket: SourceLocation
    ) {
      self.leftBracket = leftBracket
      self.name = name
      self.rightBracket = rightBracket
    }
  }
}

extension AST.Atom {
  public struct BacktrackingDirective: Hashable {
    public enum Kind: Hashable {
      /// (*ACCEPT)
      case accept

      /// (*FAIL)
      case fail

      /// (*MARK:NAME)
      case mark

      /// (*COMMIT)
      case commit

      /// (*PRUNE)
      case prune

      /// (*SKIP)
      case skip

      /// (*THEN)
      case then
    }
    public var kind: AST.Located<Kind>
    public var name: AST.Located<String>?

    public init(_ kind: AST.Located<Kind>, name: AST.Located<String>?) {
      self.kind = kind
      self.name = name
    }

    public var isQuantifiable: Bool {
      // As per http://pcre.org/current/doc/html/pcre2pattern.html#SEC29, only
      // (*ACCEPT) is quantifiable.
      kind.value == .accept
    }
  }
}

extension AST.Atom.EscapedBuiltin {
  /// If the escape sequence represents a unicode scalar value, returns the
  /// value, otherwise `nil`.
  public var scalarValue: UnicodeScalar? {
    switch self {
    // TODO: Should we separate these into a separate enum? Or move the
    // specifics of the scalar to the DSL tree?
    case .alarm:
      return "\u{7}"
    case .backspace:
      return "\u{8}"
    case .escape:
      return "\u{1B}"
    case .formfeed:
      return "\u{C}"
    case .newline:
      return "\n"
    case .carriageReturn:
      return "\r"
    case .tab:
      return "\t"

    case .singleDataUnit, .decimalDigit, .notDecimalDigit,
        .horizontalWhitespace, .notHorizontalWhitespace, .notNewline,
        .newlineSequence, .whitespace, .notWhitespace, .verticalTab,
        .notVerticalTab, .wordCharacter, .notWordCharacter, .graphemeCluster,
        .wordBoundary, .notWordBoundary, .startOfSubject,
        .endOfSubjectBeforeNewline, .endOfSubject,
        .firstMatchingPositionInSubject, .resetStartOfMatch, .trueAnychar,
        .textSegment, .notTextSegment:
      return nil
    }
  }

  public var isQuantifiable: Bool {
    switch self {
    case .alarm, .escape, .formfeed, .newline, .carriageReturn, .tab,
        .singleDataUnit, .decimalDigit, .notDecimalDigit, .horizontalWhitespace,
        .notHorizontalWhitespace, .notNewline, .newlineSequence, .whitespace,
        .notWhitespace, .verticalTab, .notVerticalTab, .wordCharacter,
        .notWordCharacter, .backspace, .graphemeCluster, .trueAnychar:
      return true

    case .wordBoundary, .notWordBoundary, .startOfSubject,
        .endOfSubjectBeforeNewline, .endOfSubject,
        .firstMatchingPositionInSubject, .resetStartOfMatch, .textSegment,
        .notTextSegment:
      return false
    }
  }
}

extension AST.Atom {
  /// Retrieves the character value of the atom.
  ///
  /// If the atom doesn't represent a literal character or a Unicode scalar,
  /// this value is `nil`.
  public var literalCharacterValue: Character? {
    switch kind {
    case .char(let c):
      return c
    case .scalar(let s):
      return Character(s.value)

    case .escaped(let c):
      return c.scalarValue.map(Character.init)

    case .keyboardControl, .keyboardMeta, .keyboardMetaControl:
      // TODO: These should have unicode scalar values.
      return nil

    case .namedCharacter:
      // TODO: This should have a unicode scalar value depending on the name
      // given.
      // TODO: Do we want to validate and assign a scalar value when building
      // the AST? Or defer for the matching engine?
      return nil

    case .scalarSequence, .property, .any, .startOfLine, .endOfLine,
        .backreference, .subpattern, .callout, .backtrackingDirective,
        .changeMatchingOptions:
      return nil
    }
  }

  /// Whether this atom is valid as the operand of a custom character class
  /// range.
  public var isValidCharacterClassRangeBound: Bool {
    // If we have a literal character value for this, it can be used as a bound.
    if literalCharacterValue?.hasExactlyOneScalar == true { return true }
    switch kind {
    // \cx, \C-x, \M-x, \M-\C-x, \N{...}
    case .keyboardControl, .keyboardMeta, .keyboardMetaControl, .namedCharacter:
      return true
    default:
      return false
    }
  }

  /// A string literal representation of the atom, if possible.
  ///
  /// Individual characters are returned as-is, and Unicode scalars are
  /// presented using "\u{nn nn ...}" syntax.
  public var literalStringValue: String? {
    func scalarLiteral(_ u: [UnicodeScalar]) -> String {
      let digits = u.map { String($0.value, radix: 16, uppercase: true) }
        .joined(separator: " ")
      return "\\u{\(digits)}"
    }
    switch kind {
    case .char(let c):
      return String(c)
    case .scalar(let s):
      return scalarLiteral([s.value])

    case .scalarSequence(let s):
      return scalarLiteral(s.scalarValues)

    case .keyboardControl(let x):
      return "\\C-\(x)"
    case .keyboardMeta(let x):
      return "\\M-\(x)"

    case .keyboardMetaControl(let x):
      return "\\M-\\C-\(x)"

    case .property, .escaped, .any, .startOfLine, .endOfLine,
        .backreference, .subpattern, .namedCharacter, .callout,
        .backtrackingDirective, .changeMatchingOptions:
      return nil
    }
  }

  public var isQuantifiable: Bool {
    switch kind {
    case .backtrackingDirective(let b):
      return b.isQuantifiable
    case .changeMatchingOptions:
      return false
    // TODO: Are callouts quantifiable?
    case .escaped(let esc):
      return esc.isQuantifiable
    case .startOfLine, .endOfLine:
      return false
    default:
      return true
    }
  }
}

extension AST.Node {
  public var literalStringValue: String? {
    switch self {
    case .atom(let a): return a.literalStringValue

    case .alternation, .concatenation, .group,
        .conditional, .quantification, .quote,
        .trivia, .customCharacterClass, .empty,
        .absentFunction, .interpolation:
      return nil
    }
  }

}
