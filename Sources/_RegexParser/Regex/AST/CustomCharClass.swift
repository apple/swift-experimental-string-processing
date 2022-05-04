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
  public struct CustomCharacterClass: Hashable {
    public var start: Located<Start>
    public var members: [Member]

    public let location: SourceLocation

    public init(
      _ start: Located<Start>,
      _ members: [Member],
      _ sr: SourceLocation
    ) {
      self.start = start
      self.members = members
      self.location = sr
    }

    @frozen
    public enum Member: Hashable {
      /// A nested custom character class `[[ab][cd]]`
      case custom(CustomCharacterClass)

      /// A character range `a-z`
      case range(Range)

      /// A single character or escape
      case atom(Atom)

      /// A quoted sequence. Inside a custom character class this just means
      /// the contents should be interpreted literally.
      case quote(Quote)

      /// Trivia such as non-semantic whitespace.
      case trivia(Trivia)

      /// A binary operator applied to sets of members `abc&&def`
      case setOperation([Member], Located<SetOp>, [Member])
    }
    public struct Range: Hashable {
      public var lhs: Atom
      public var dashLoc: SourceLocation
      public var rhs: Atom

      public init(_ lhs: Atom, _ dashLoc: SourceLocation, _ rhs: Atom) {
        self.lhs = lhs
        self.dashLoc = dashLoc
        self.rhs = rhs
      }
    }
    @frozen
    public enum SetOp: String, Hashable {
      case subtraction = "--"
      case intersection = "&&"
      case symmetricDifference = "~~"
    }
    @frozen
    public enum Start: String {
      case normal = "["
      case inverted = "[^"
    }
  }
}

extension AST.CustomCharacterClass {
  public var isInverted: Bool { start.value == .inverted }
}

extension CustomCC.Member {
  private var _associatedValue: Any {
    switch self {
    case .custom(let c): return c
    case .range(let r): return r
    case .atom(let a): return a
    case .quote(let q): return q
    case .trivia(let t): return t
    case .setOperation(let lhs, let op, let rhs): return (lhs, op, rhs)
    }
  }

  func `as`<T>(_ t: T.Type = T.self) -> T? {
    _associatedValue as? T
  }

  public var isTrivia: Bool {
    if case .trivia = self { return true }
    return false
  }

  public var isSemantic: Bool {
    !isTrivia
  }
}

extension AST.CustomCharacterClass {
  /// Strips trivia from the character class members.
  ///
  /// This method doesn't recurse into nested custom character classes.
  public var strippingTriviaShallow: Self {
    var copy = self
    copy.members = copy.members.filter(\.isSemantic)
    return copy
  }
}
