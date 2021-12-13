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
      case scalar(Unicode.Scalar)

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
      //
      // TODO: Haven't thought through these a ton
      case backreference(Reference)
      case subpattern(Reference)
      case condition(Reference)
    }
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
    // TOOD: better doc comments

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
      "\(kind)\(isInverted)"
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

    case posix(Unicode.POSIXProperty)

    /// Some special properties implemented by PCRE and Oniguruma.
    case pcreSpecial(PCRESpecialCategory)
    case onigurumaSpecial(OnigurumaSpecialProperty)

    /// Unhandled properties.
    case other(key: String?, value: String)
  }

  // TODO: erm, separate out or fold into something? splat it in?
  public enum PCRESpecialCategory: String, Hashable {
    case alphanumeric     = "Xan"
    case posixSpace       = "Xps"
    case perlSpace        = "Xsp"
    case universallyNamed = "Xuc"
    case perlWord         = "Xwd"
  }
}

// TODO: I haven't thought through this a bunch; this seems like
// a sensible type to have and break down this way. But it could
// easily get folded in with the kind of reference
public enum Reference: Hashable {
  // \n \gn \g{n} \g<n> \g'n' (?n) (?(n)...
  // Oniguruma: \k<n>, \k'n'
  case absolute(Int)

  // \g{-n} \g<+n> \g'+n' \g<-n> \g'-n' (?+n) (?-n)
  // (?(+n)... (?(-n)...
  // Oniguruma: \k<-n> \k<+n> \k'-n' \k'+n'
  case relative(Int)

  // \k<name> \k'name' \g{name} \k{name} (?P=name)
  // \g<name> \g'name' (?&name) (?P>name)
  // (?(<name>)... (?('name')... (?(name)...
  case named(String)

  // TODO: I'm not sure the below goes here
  //
  // ?(R) (?(R)...
  case recurseWholePattern
}

extension AST.Atom: _ASTPrintable {
  public var _dumpBase: String {
    if let lit = self.literalCharacterValue {
      return String(lit).halfWidthCornerQuoted
    }

    switch kind {
    case .escaped(let c): return "\\\(c.character)"

    case .namedCharacter(let charName):
      return "\\N{\(charName)}"

    case .property(let p): return "\(p._dumpBase)"

    case .keyboardControl, .keyboardMeta, .keyboardMetaControl:
      fatalError("TODO")

    case .any:         return "."
    case .startOfLine: return "^"
    case .endOfLine:   return "$"

    case .backreference(_):
      fatalError("TODO")
    case .subpattern(_):
      fatalError("TODO")
    case .condition(_):
      fatalError("TODO")

    case .char, .scalar:
      fatalError("Unreachable")
    }
  }
}

extension AST.Atom {
  /// Retrieve the character value of the atom if it represents a literal
  /// character or unicode scalar, nil otherwise.
  public var literalCharacterValue: Character? {
    switch kind {
    case .char(let c):
      return c
    case .scalar(let s):
      return Character(s)

    case .keyboardControl, .keyboardMeta, .keyboardMetaControl:
      // TODO: Not a character per-say, what should we do?
      fallthrough

    case .property, .escaped, .any, .startOfLine, .endOfLine,
        .backreference, .subpattern, .condition, .namedCharacter:
      return nil
    }
  }
}
