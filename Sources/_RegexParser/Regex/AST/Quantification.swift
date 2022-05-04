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
  public struct Quantification: Hashable {
    public let amount: Located<Amount>
    public let kind: Located<Kind>

    public let child: AST.Node
    public let location: SourceLocation

    /// Any trivia intermixed between the operand and the quantifier, as well
    /// as between the quantifier characters themselves. This can occur in
    /// extended syntax mode where PCRE permits e.g `x * +`.
    public let trivia: [AST.Trivia]

    public init(
      _ amount: Located<Amount>,
      _ kind: Located<Kind>,
      _ child: AST.Node,
      _ r: SourceLocation,
      trivia: [AST.Trivia]
    ) {
      self.amount = amount
      self.kind = kind
      self.child = child
      self.location = r
      self.trivia = trivia
    }

    @frozen
    public enum Amount: Hashable {
      case zeroOrMore              // *
      case oneOrMore               // +
      case zeroOrOne               // ?
      case exactly(Located<Int>)         // {n}
      case nOrMore(Located<Int>)         // {n,}
      case upToN(Located<Int>)           // {,n}
      case range(Located<Int>, Located<Int>) // {n,m}
    }

    @frozen
    public enum Kind: String, Hashable {
      case eager      = ""
      case reluctant  = "?"
      case possessive = "+"
    }
  }
}

/// MARK: - Semantic API

extension AST.Quantification.Amount {
  /// The bounds.
  public var bounds: (atLeast: Int, atMost: Int?) {
    switch self {
    case .zeroOrMore: return (0, nil)
    case .oneOrMore:  return (1, nil)
    case .zeroOrOne:  return (0, 1)

    case let .exactly(n):  return (n.value, n.value)
    case let .nOrMore(n):  return (n.value, nil)
    case let .upToN(n):    return (0, n.value)
    case let .range(n, m): return (n.value, m.value)
    }
  }
}
