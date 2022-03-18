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

extension AST {
  var dslTree: DSLTree {
    return DSLTree(
      root.dslTreeNode, options: globalOptions?.dslTreeOptions)
  }
}

extension AST.GlobalMatchingOptionSequence {
  var dslTreeOptions: DSLTree.Options {
    // TODO: map options
    return .init()
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
      return .convertedRegexLiteral(node, self)
    }

    // Convert the top-level node without wrapping
    func convert() -> DSLTree.Node {
      switch self {
      case let .alternation(v):
        let children = v.children.map(\.dslTreeNode)
        return .alternation(children)

      case let .concatenation(v):
        // Coalesce adjacent children who can produce a
        // string literal representation
        let astChildren = v.children
        func coalesce(
          _ idx: Array<AST>.Index
        ) -> (Array<AST>.Index, String)? {
          var result = ""
          var idx = idx
          while idx < astChildren.endIndex {
            let atom: AST.Atom? = astChildren[idx].as()

            // TODO: For printing, nice to coalesce
            // scalars literals too. We likely need a different
            // approach even before we have a better IR.
            guard let char = atom?.singleCharacter else {
              break
            }
            result.append(char)
            astChildren.formIndex(after: &idx)
          }
          return result.count <= 1 ? nil : (idx, result)
        }

        // No need to nest single children concatenations
        if astChildren.count == 1 {
          return astChildren.first!.dslTreeNode
        }

        // Check for a single child post-coalescing
        if let (idx, str) = coalesce(astChildren.startIndex),
           idx == astChildren.endIndex
        {
          return .quotedLiteral(str)
        }

        // Coalesce adjacent string children
        var curIdx = astChildren.startIndex
        var children = Array<DSLTree.Node>()
        while curIdx < astChildren.endIndex {
          if let (nextIdx, str) = coalesce(curIdx) {
            // TODO: Track source info...
            children.append(.quotedLiteral(str))
            curIdx = nextIdx
          } else {
            children.append(astChildren[curIdx].dslTreeNode)
            children.formIndex(after: &curIdx)
          }
        }
        return .concatenation(children)

      case let .group(v):
        let child = v.child.dslTreeNode
        return .group(v.kind.value, child)

      case let .conditional(v):
        let trueBranch = v.trueBranch.dslTreeNode
        let falseBranch = v.falseBranch.dslTreeNode
        return .conditional(
          v.condition.kind, trueBranch, falseBranch)

      case let .quantification(v):
        let child = v.child.dslTreeNode
        return .quantification(
          v.amount.value, v.kind.value, child)

      case let .quote(v):
        return .quotedLiteral(v.literal)

      case let .trivia(v):
        return .trivia(v.contents)

      case let .atom(v):
        return .atom(v.dslTreeAtom)

      case let .customCharacterClass(ccc):
        return .customCharacterClass(ccc.dslTreeClass)

      case .empty(_):
        return .empty

      case let .absentFunction(a):
        // TODO: What should this map to?
        return .absentFunction(a)
      }
    }

    let converted = convert()
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

extension AST.Atom {
  var dslTreeAtom: DSLTree.Atom {
    if let kind = assertionKind {
      return .assertion(kind)
    }

    switch self.kind {
    case let .char(c):          return .char(c)
    case let .scalar(s):        return .scalar(s)
    case .any:                  return .any
    case let .backreference(r): return .backreference(r)
    case let .subpattern(r):    return .subpattern(r)

    default: return .unconverted(self)
    }
  }
}
