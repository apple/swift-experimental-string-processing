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

extension AST {
  var dslTree: DSLTree {
    return DSLTree(root.dslTreeNode)
  }
}

extension AST.Node {
  /// Converts an AST node to a `convertedRegexLiteral` node.
  var dslTreeNode: DSLTree.Node {
    func wrap(_ node: DSLTree.Node) -> DSLTree.Node {
      switch node {
      case .convertedRegexLiteral:
        // FIXME: DSL can have one item concats
//        assertionFailure("Double wrapping?")
        return node
      default:
        break
      }
      // TODO: Should we do this for the
      // single-concatenation child too, or should?
      // we wrap _that_?
      return .convertedRegexLiteral(node, .init(ast: self))
    }

    // Convert the top-level node without wrapping
    func convert() throws -> DSLTree.Node {
      switch self {
      case let .alternation(v):
        let children = v.children.map(\.dslTreeNode)
        return .orderedChoice(children)

      case let .concatenation(v):
        return .concatenation(v.children.map(\.dslTreeNode))

      case let .group(v):
        let child = v.child.dslTreeNode
        switch v.kind.value {
        case .capture:
          return .capture(child)
        case .namedCapture(let name):
          return .capture(name: name.value, child)
        case .balancedCapture:
          throw Unsupported("TODO: balanced captures")
        default:
          return .nonCapturingGroup(.init(ast: v.kind.value), child)
        }

      case let .conditional(v):
        let trueBranch = v.trueBranch.dslTreeNode
        let falseBranch = v.falseBranch.dslTreeNode
        return .conditional(
          .init(ast: v.condition.kind), trueBranch, falseBranch)

      case let .quantification(v):
        let child = v.child.dslTreeNode
        return .quantification(
          .init(ast: v.amount.value), .syntax(.init(ast: v.kind.value)), child)

      case let .quote(v):
        return .quotedLiteral(v.literal)

      case let .trivia(v):
        return .trivia(v.contents)

      case .interpolation:
        throw Unsupported("TODO: interpolation")

      case let .atom(v):
        switch v.kind {
        case .scalarSequence(let seq):
          // The DSL doesn't have an equivalent node for scalar sequences. Splat
          // them into a concatenation of scalars.
          return .concatenation(seq.scalarValues.map { .atom(.scalar($0)) })
        default:
          return .atom(v.dslTreeAtom)
        }

      case let .customCharacterClass(ccc):
        return .customCharacterClass(ccc.dslTreeClass)

      case .empty(_):
        return .empty

      case let .absentFunction(abs):
        // TODO: What should this map to?
        return .absentFunction(.init(ast: abs))
      }
    }

    // FIXME: make total function again
    let converted = try! convert()
    return wrap(converted)
  }
}

extension AST.CustomCharacterClass {
  var dslTreeClass: DSLTree.CustomCharacterClass {
    // TODO: Not quite 1-1
    func convert(
      _ member: Member
    ) -> DSLTree.CustomCharacterClass.Member {
      switch member {
      case let .custom(ccc):
        return .custom(ccc.dslTreeClass)

      case let .range(r):
        return .range(
          r.lhs.dslTreeAtom, r.rhs.dslTreeAtom)

      case let .atom(a):
        return .atom(a.dslTreeAtom)

      case let .quote(q):
        return .quotedLiteral(q.literal)

      case let .setOperation(lhs, op, rhs):
        let lhs = DSLTree.CustomCharacterClass(
          members: lhs.map(convert),
          isInverted: false)
        let rhs = DSLTree.CustomCharacterClass(
          members: rhs.map(convert),
          isInverted: false)

        switch op.value {
        case .subtraction:
          return .subtraction(lhs, rhs)
        case .intersection:
          return .intersection(lhs, rhs)
        case .symmetricDifference:
          return .symmetricDifference(lhs, rhs)
        }
      case let .trivia(t):
        return .trivia(t.contents)
      }
    }

    return .init(
      members: members.map(convert),
      isInverted: self.isInverted)
  }
}

extension AST.Atom.EscapedBuiltin {
  var dslAssertionKind: DSLTree.Atom.Assertion? {
    switch self {
    case .wordBoundary:                   return .wordBoundary
    case .notWordBoundary:                return .notWordBoundary
    case .startOfSubject:                 return .startOfSubject
    case .endOfSubject:                   return .endOfSubject
    case .textSegment:                    return .textSegment
    case .notTextSegment:                 return .notTextSegment
    case .endOfSubjectBeforeNewline:      return .endOfSubjectBeforeNewline
    case .firstMatchingPositionInSubject: return .firstMatchingPositionInSubject
    case .resetStartOfMatch:              return .resetStartOfMatch
    default: return nil
    }
  }
}

extension AST.Atom {
  var dslAssertionKind: DSLTree.Atom.Assertion? {
    switch kind {
    case .caretAnchor:    return .caretAnchor
    case .dollarAnchor:   return .dollarAnchor
    case .escaped(let b): return b.dslAssertionKind
    default: return nil
    }
  }
}

extension AST.Atom {
  var dslTreeAtom: DSLTree.Atom {
    if let kind = dslAssertionKind {
      return .assertion(kind)
    }

    switch self.kind {
    case let .char(c):                    return .char(c)
    case let .scalar(s):                  return .scalar(s.value)
    case .dot:                            return .dot
    case let .backreference(r):           return .backreference(.init(ast: r))
    case let .changeMatchingOptions(seq): return .changeMatchingOptions(.init(ast: seq))

    case .escaped(let c) where c.scalarValue != nil:
      return .scalar(c.scalarValue!)

    default: return .unconverted(.init(ast: self))
    }
  }
}
