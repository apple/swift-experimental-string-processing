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
  /// An option written in source that changes matching semantics.
  public struct MatchingOption: Hashable {
    public enum Kind {
      // PCRE options
      case caseInsensitive          // i
      case allowDuplicateGroupNames // J
      case multiline                // m
      case noAutoCapture            // n
      case singleLine               // s
      case reluctantByDefault       // U
      case extended                 // x
      case extraExtended            // xx

      // ICU options
      case unicodeWordBoundaries    // w

      // Oniguruma options
      case asciiOnlyDigit           // D
      case asciiOnlyPOSIXProps      // P
      case asciiOnlySpace           // S
      case asciiOnlyWord            // W

      // Oniguruma text segment options (these are mutually exclusive and cannot
      // be unset, only flipped between)
      case textSegmentGraphemeMode  // y{g}
      case textSegmentWordMode      // y{w}
    }
    public var kind: Kind
    public var location: SourceLocation

    public init(_ kind: Kind, location: SourceLocation) {
      self.kind = kind
      self.location = location
    }

    public var isTextSegmentMode: Bool {
      switch kind {
      case .textSegmentGraphemeMode, .textSegmentWordMode:
        return true
      default:
        return false
      }
    }
  }

  /// A sequence of matching options written in source.
  public struct MatchingOptionSequence: Hashable {
    /// If the sequence starts with a caret '^', its source location, or nil
    /// otherwise. If this is set, it indicates that all the matching options
    /// are unset, except the ones in `adding`.
    public var caretLoc: SourceLocation?

    /// The options to add.
    public var adding: [MatchingOption]

    /// The location of the '-' between the options to add and options to
    /// remove.
    public var minusLoc: SourceLocation?

    /// The options to remove.
    public var removing: [MatchingOption]

    public init(caretLoc: SourceLocation?, adding: [MatchingOption],
                minusLoc: SourceLocation?, removing: [MatchingOption]) {
      self.caretLoc = caretLoc
      self.adding = adding
      self.minusLoc = minusLoc
      self.removing = removing
    }
  }
}

extension AST.MatchingOption: _ASTPrintable {
  public var _dumpBase: String { "\(kind)" }
}

extension AST.MatchingOptionSequence: _ASTPrintable {
  public var _dumpBase: String {
    "adding: \(adding), removing: \(removing), hasCaret: \(caretLoc != nil)"
  }
}

extension AST {
  /// Global matching option specifiers. Unlike `MatchingOptionSequence`,
  /// these must appear at the start of the pattern, and apply globally.
  public struct GlobalMatchingOption: _ASTNode, Hashable {
    /// Determines what the definition of a newline for the '.' character class.
    public enum NewlineMatching: Hashable {
      /// (*CR*)
      case carriageReturnOnly
      
      /// (*LF)
      case linefeedOnly

      /// (*CRLF)
      case carriageAndLinefeedOnly

      /// (*ANYCRLF)
      case anyCarriageReturnOrLinefeed

      /// (*ANY)
      case anyUnicode

      /// (*NUL)
      case nulCharacter
    }
    /// Determines what `\R` matches.
    public enum NewlineSequenceMatching: Hashable {
      /// (*BSR_ANYCRLF)
      case anyCarriageReturnOrLinefeed

      /// (*BSR_UNICODE)
      case anyUnicode
    }
    public enum Kind: Hashable {
      /// (*LIMIT_DEPTH=d)
      case limitDepth(Located<Int>)

      /// (*LIMIT_HEAP=d)
      case limitHeap(Located<Int>)

      /// (*LIMIT_MATCH=d)
      case limitMatch(Located<Int>)

      /// (*NOTEMPTY)
      case notEmpty

      /// (*NOTEMPTY_ATSTART)
      case notEmptyAtStart

      /// (*NO_AUTO_POSSESS)
      case noAutoPossess

      /// (*NO_DOTSTAR_ANCHOR)
      case noDotStarAnchor

      /// (*NO_JIT)
      case noJIT

      /// (*NO_START_OPT)
      case noStartOpt

      /// (*UTF)
      case utfMode

      /// (*UCP)
      case unicodeProperties

      case newlineMatching(NewlineMatching)
      case newlineSequenceMatching(NewlineSequenceMatching)
    }
    public var kind: Kind
    public var location: SourceLocation

    public init(_ kind: Kind, _ location: SourceLocation) {
      self.kind = kind
      self.location = location
    }
  }
}

extension AST.GlobalMatchingOption: _ASTPrintable {
  public var _dumpBase: String { "\(kind)" }
}

extension AST.GlobalMatchingOption.Kind: _ASTPrintable {
  public var _dumpBase: String { _canonicalBase }
}
