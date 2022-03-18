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

import _MatchingEngine

struct DSLTree {
  var root: Node
  var options: Options?

  init(_ r: Node, options: Options?) {
    self.root = r
    self.options = options
  }
}

extension DSLTree {
  indirect enum Node: _TreeNode {
    /// ... | ... | ...
    case alternation([Node])

    /// ... ...
    case concatenation([Node])

    /// (...)
    case group(AST.Group.Kind, Node, ReferenceID? = nil)

    /// (?(cond) true-branch | false-branch)
    ///
    /// TODO: Consider splitting off grouped conditions, or have our own kind
    case conditional(
      AST.Conditional.Condition.Kind, Node, Node)

    case quantification(
      AST.Quantification.Amount,
      AST.Quantification.Kind,
      Node)

    case customCharacterClass(CustomCharacterClass)

    case atom(Atom)

    /// Comments, non-semantic whitespace, etc
    // TODO: Do we want this? Could be interesting
    case trivia(String)

    // TODO: Probably some atoms, built-ins, etc.

    case empty

    case quotedLiteral(String)

    /// An embedded literal
    case regexLiteral(AST.Node)

    // TODO: What should we do here?
    ///
    /// TODO: Consider splitting off expression functions, or have our own kind
    case absentFunction(AST.AbsentFunction)

    // MARK: - Tree conversions

    /// The target of AST conversion.
    ///
    /// Keeps original AST around for rich syntactic and source information
    case convertedRegexLiteral(Node, AST.Node)

    // MARK: - Extensibility points

    /// A capturing group (TODO: is it?) with a transformation function
    ///
    /// TODO: Consider as a validator or constructor nested in a
    /// group, or split capturing off of group.
    case groupTransform(
      AST.Group.Kind,
      Node,
      CaptureTransform,
      ReferenceID? = nil)

    case consumer(_ConsumerInterface)

    case matcher(AnyType, _MatcherInterface)

    // TODO: Would this just boil down to a consumer?
    case characterPredicate(_CharacterPredicateInterface)
  }
}

extension DSLTree {
  struct CustomCharacterClass {
    var members: [Member]
    var isInverted: Bool

    enum Member {
      case atom(Atom)
      case range(Atom, Atom)
      case custom(CustomCharacterClass)

      case quotedLiteral(String)

      case trivia(String)

      indirect case intersection(CustomCharacterClass, CustomCharacterClass)
      indirect case subtraction(CustomCharacterClass, CustomCharacterClass)
      indirect case symmetricDifference(CustomCharacterClass, CustomCharacterClass)
    }
  }

  enum Atom {
    case char(Character)
    case scalar(Unicode.Scalar)
    case any

    case assertion(AST.Atom.AssertionKind)
    case backreference(AST.Reference)
    case subpattern(AST.Reference)
    case symbolicReference(ReferenceID)

    case unconverted(AST.Atom)
  }
}

// CollectionConsumer
typealias _ConsumerInterface = (
  String, Range<String.Index>
) -> String.Index?

// Type producing consume
// TODO: better name
typealias _MatcherInterface = (
  String, String.Index, Range<String.Index>
) -> (String.Index, Any)?

// Character-set (post grapheme segmentation)
typealias _CharacterPredicateInterface = (
  (Character) -> Bool
)

/*

 TODO: Use of syntactic types, like group kinds, is a
 little suspect. We may want to figure out a model here.

 TODO: Do capturing groups need explicit numbers?

 TODO: Are storing closures better/worse than existentials?

 */

extension DSLTree.Node {
  var children: [DSLTree.Node]? {
    switch self {
      
    case let .alternation(v):   return v
    case let .concatenation(v): return v

    case let .convertedRegexLiteral(n, _):
      // Treat this transparently
      return n.children

    case let .group(_, n, _):             return [n]
    case let .groupTransform(_, n, _, _): return [n]
    case let .quantification(_, _, n): return [n]

    case let .conditional(_, t, f): return [t,f]

    case .trivia, .empty, .quotedLiteral, .regexLiteral,
        .consumer, .matcher, .characterPredicate,
        .customCharacterClass, .atom:
      return []

    case let .absentFunction(a):
      return a.children.map(\.dslTreeNode)
    }
  }
}

extension DSLTree.Node {
  var astNode: AST.Node? {
    switch self {
    case let .regexLiteral(ast):             return ast
    case let .convertedRegexLiteral(_, ast): return ast
    default: return nil
    }
  }
}

extension DSLTree.Atom {
  // Return the Character or promote a scalar to a Character
  var literalCharacterValue: Character? {
    switch self {
    case let .char(c):   return c
    case let .scalar(s): return Character(s)
    default: return nil
    }
  }
}

extension DSLTree {
  struct Options {
    // TBD
  }
}

extension DSLTree {
  var ast: AST? {
    guard let root = root.astNode else {
      return nil
    }
    // TODO: Options mapping
    return AST(root, globalOptions: nil)
  }
}

extension DSLTree {
  var hasCapture: Bool {
    root.hasCapture
  }
}
extension DSLTree.Node {
  var hasCapture: Bool {
    switch self {
    case let .group(k, _, _) where k.isCapturing,
         let .groupTransform(k, _, _, _) where k.isCapturing:
      return true
    case let .convertedRegexLiteral(n, re):
      assert(n.hasCapture == re.hasCapture)
      return n.hasCapture
    case let .regexLiteral(re):
      return re.hasCapture
    default:
      break
    }
    return self.children?.any(\.hasCapture) ?? false
  }
}

extension DSLTree {
  var captureStructure: CaptureStructure {
    // TODO: nesting
    var constructor = CaptureStructure.Constructor(.flatten)
    return root._captureStructure(&constructor)
  }
}
extension DSLTree.Node {
  func _captureStructure(
    _ constructor: inout CaptureStructure.Constructor
  ) -> CaptureStructure {
    switch self {
    case let .alternation(children):
      return constructor.alternating(children)

    case let .concatenation(children):
      return constructor.concatenating(children)

    case let .group(kind, child, _):
      if let type = child.matcherCaptureType {
        return constructor.grouping(
          child, as: kind, withType: type)
      }
      return constructor.grouping(child, as: kind)

    case let .groupTransform(kind, child, transform, _):
      return constructor.grouping(
        child, as: kind, withTransform: transform)

    case let .conditional(cond, trueBranch, falseBranch):
      return constructor.condition(
        cond,
        trueBranch: trueBranch,
        falseBranch: falseBranch)

    case let .quantification(amount, _, child):
      return constructor.quantifying(
        child, amount: amount)

    case let .regexLiteral(re):
      // TODO: Force a re-nesting?
      return re._captureStructure(&constructor)

    case let .absentFunction(abs):
      return constructor.absent(abs.kind)

    case let .convertedRegexLiteral(n, _):
      // TODO: Switch nesting strategy?
      return n._captureStructure(&constructor)

    case .matcher:
      return .empty

    case .customCharacterClass, .atom, .trivia, .empty,
        .quotedLiteral, .consumer, .characterPredicate:
      return .empty
    }
  }

  // TODO: Unify with group transform
  var matcherCaptureType: AnyType? {
    switch self {
    case let .matcher(t, _):
      return t
    default: return nil
    }
  }
}

extension DSLTree.Node {
  func appending(_ newNode: DSLTree.Node) -> DSLTree.Node {
    if case .concatenation(let components) = self {
      return .concatenation(components + [newNode])
    }
    return .concatenation([self, newNode])
  }

  func appendingAlternationCase(_ newNode: DSLTree.Node) -> DSLTree.Node {
    if case .alternation(let components) = self {
      return .alternation(components + [newNode])
    }
    return .alternation([self, newNode])
  }
}

extension DSLTree.Node {
  /// Generates a DSLTree node for a repeated range of the given DSLTree node.
  /// Individual public API functions are in the generated Variadics.swift file.
  static func repeating(
    _ range: Range<Int>,
    _ behavior: QuantificationBehavior,
    _ node: DSLTree.Node
  ) -> DSLTree.Node {
    // TODO: Throw these as errors
    assert(range.lowerBound >= 0, "Cannot specify a negative lower bound")
    assert(!range.isEmpty, "Cannot specify an empty range")
    
    switch (range.lowerBound, range.upperBound) {
    case (0, Int.max): // 0...
      return .quantification(.zeroOrMore, behavior.astKind, node)
    case (1, Int.max): // 1...
      return .quantification(.oneOrMore, behavior.astKind, node)
    case _ where range.count == 1: // ..<1 or ...0 or any range with count == 1
      // Note: `behavior` is ignored in this case
      return .quantification(.exactly(.init(faking: range.lowerBound)), .eager, node)
    case (0, _): // 0..<n or 0...n or ..<n or ...n
      return .quantification(.upToN(.init(faking: range.upperBound)), behavior.astKind, node)
    case (_, Int.max): // n...
      return .quantification(.nOrMore(.init(faking: range.lowerBound)), behavior.astKind, node)
    default: // any other range
      return .quantification(.range(.init(faking: range.lowerBound), .init(faking: range.upperBound)), behavior.astKind, node)
    }
  }
}
