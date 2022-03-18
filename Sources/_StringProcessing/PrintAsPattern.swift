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

// TODO: Add an expansion level, both from top to bottom.
//       After `printAsCanonical` is fleshed out, these two
//       printers can call each other. This would enable
//       incremental conversion, such that leaves remain
//       as canonical regex literals.

extension AST {
  /// Render as a Pattern DSL
  public func renderAsBuilderDSL(
    maxTopDownLevels: Int? = nil,
    minBottomUpLevels: Int? = nil
  ) -> String {
    var printer = PrettyPrinter(
      maxTopDownLevels: maxTopDownLevels,
      minBottomUpLevels: minBottomUpLevels)
    printer.printAsPattern(self)
    return printer.finish()
  }
}

extension PrettyPrinter {
  /// If pattern printing should back off, prints the regex literal and returns true
  mutating func patternBackoff<T: _TreeNode>(
    _ ast: T
  ) -> Bool {
    if let max = maxTopDownLevels, depth >= max {
      return true
    }
    if let min = minBottomUpLevels, ast.height <= min {
      return true
    }
    return false
  }

  mutating func printBackoff(_ node: DSLTree.Node) {
    precondition(node.astNode != nil, "unconverted node")
    printAsCanonical(
      .init(node.astNode!, globalOptions: nil),
      delimiters: true)
  }

  mutating func printAsPattern(_ ast: AST) {
    // TODO: Handle global options...
    let node = ast.root.dslTreeNode
    printAsPattern(convertedFromAST: node)
  }

  // FIXME: Use of back-offs like height and depth
  // imply that this DSLTree node has a corresponding
  // AST. That's not always true, and it would be nice
  // to have a non-backing-off pretty-printer that this
  // can defer to.
  private mutating func printAsPattern(
    convertedFromAST node: DSLTree.Node
  ) {
    if patternBackoff(node) {
      printBackoff(node)
      return
    }

    switch node {

    case let .alternation(a):
      printBlock("Alternation") { printer in
        a.forEach {
          printer.printAsPattern(convertedFromAST: $0)
        }
      }

    case let .concatenation(c):
      printBlock("Concatenation") { printer in
        c.forEach {
          printer.printAsPattern(convertedFromAST: $0)
        }
      }

    case let .group(kind, child, referenceID):
      let kind = kind._patternBase
      let refIDString = referenceID.map { ", referenceID: \($0)" } ?? ""
      printBlock("Group(\(kind)\(refIDString)") { printer in
        printer.printAsPattern(convertedFromAST: child)
      }

    case .conditional:
      print("/* TODO: conditional */")

    case let .quantification(amount, kind, child):
      let amount = amount._patternBase
      let kind = kind._patternBase
      printBlock("\(amount)(\(kind))") { printer in
        printer.printAsPattern(convertedFromAST: child)
      }

    case let .atom(a):
      switch a {
      case .any:
        print(".any")

      case let .char(c):
        print(String(c)._quoted)

      case let .scalar(s):
        let hex = String(s.value, radix: 16, uppercase: true)
        print("\\u{\(hex)}"._quoted)

      case let .unconverted(a):
        // TODO: is this always right?
        // TODO: Convert built-in character classes
        print(a._patternBase)

      case .assertion:
        print("/* TODO: assertions */")
      case .backreference:
        print("/* TOOD: backreferences */")
      case .subpattern:
        print("/* TOOD: subpatterns */")
      case .symbolicReference:
        print("/* TOOD: symbolic references */")
      }

    case .trivia:
      // What should we do? Maybe keep comments, etc?
      print("")

    case .empty:
      print("")

    case let .quotedLiteral(v):
      print(v._quoted)

    case .regexLiteral:
      printBackoff(node)

    case let .convertedRegexLiteral(n, _):
      // FIXME: This recursion coordinates with back-off
      // check above, so it should work out. Need a
      // cleaner way to do this. This means the argument
      // label is a lie.
      printAsPattern(convertedFromAST: n)

    case let .customCharacterClass(ccc):
      printAsPattern(ccc)

    case .groupTransform:
      print("/* TODO: group transforms */")
    case .consumer:
      print("/* TODO: consumers */")
    case .matcher:
      print("/* TODO: consumer validators */")
    case .characterPredicate:
      print("/* TODO: character predicates */")

    case .absentFunction:
      print("/* TODO: absent function */")
    }
  }

  // TODO: Some way to integrate this with conversion...
  mutating func printAsPattern(
    _ ccc: DSLTree.CustomCharacterClass
  ) {
    let inv = ccc.isInverted ? "inverted: true" : ""
    printBlock("CharacterClass(\(inv))") { printer in
      ccc.members.forEach { printer.printAsPattern($0) }
    }
  }

  // TODO: Some way to integrate this with conversion...
  mutating func printAsPattern(
    _ member: DSLTree.CustomCharacterClass.Member
  ) {
    switch member {
    case let .custom(ccc):
      printAsPattern(ccc)
    case let .range(lhs, rhs):
      if case let .char(lhs) = lhs,
         case let .char(rhs) = rhs {
        indent()
        output(String(lhs)._quoted)
        output("...")
        output(String(rhs)._quoted)
        terminateLine()
      } else {
        print("// TODO: Range \(lhs) to \(rhs)")
      }
    case let .atom(a):
      if case let .char(c) = a {
        print(String(c)._quoted)
      } else {
        print(" // TODO: Atom \(a) ")
      }
    case .quotedLiteral(let s):
      print("// TODO: quote \(s._quoted) in custom character classes (should we split it?)")
    case .trivia(let t):
      // TODO: We might want to output comments...
      _ = t
    case .symmetricDifference, .intersection, .subtraction:
      print("// TODO: Set operation: \(member)")
    }
  }
}

extension String {
  // TODO: Escaping?
  fileprivate var _quoted: String { "\"\(self)\"" }
}

extension AST.Atom.AssertionKind {
  // TODO: Some way to integrate this with conversion...
  var _patternBase: String {
    switch self {
    case .startOfSubject:    return "Anchor(.startOfSubject)"
    case .endOfSubject:      return "Anchor(.endOfSubject)"
    case .textSegment:       return "Anchor(.textSegment)"
    case .notTextSegment:    return "Anchor(.notTextSegment)"
    case .startOfLine:       return "Anchor(.startOfLine)"
    case .endOfLine:         return "Anchor(.endOfLine)"
    case .wordBoundary:      return "Anchor(.wordBoundary)"
    case .notWordBoundary:   return "Anchor(.notWordBoundary)"

    case .resetStartOfMatch:
      return "Anchor(.resetStartOfMatch)"
    case .endOfSubjectBeforeNewline:
      return "Anchor(.endOfSubjectBeforeNewline)"
    case .firstMatchingPositionInSubject:
      return "Anchor(.firstMatchingPositionInSubject)"
    }
  }
}

extension AST.Atom.CharacterProperty {
  // TODO: Some way to integrate this with conversion...
  var _patternBase: String {
    "Property(\(kind._patternBase)\(isInverted ? ", inverted: true" : ""))"
  }
}
extension AST.Atom.CharacterProperty.Kind {
  // TODO: Some way to integrate this with conversion...
  var _patternBase: String {
    "/* TODO: character properties */"
  }
}

extension AST.Atom {
  /// Base string to use when rendering as a component in a
  /// pattern. Note that when the atom is rendered individually,
  /// it still may need to be wrapped in quotes.
  ///
  /// TODO: We want to coalesce adjacent atoms, likely in
  /// caller, but we might want to be parameterized at that point.
  ///
  /// TODO: Some way to integrate this with conversion...
  var _patternBase: String {
    if let anchor = self.assertionKind {
      return anchor._patternBase
    }

    switch kind {
    case let .char(c):
      return String(c)

    case let .scalar(s):
      let hex = String(s.value, radix: 16, uppercase: true)
      return "\\u{\(hex)}"

    case let .property(p):
      return p._patternBase

    case let .escaped(e):
      // TODO: API names instead of case names
      return ".\(e)"

    case .keyboardControl:
      return " /* TODO: keyboard control */"

    case .keyboardMeta:
      return " /* TODO: keyboard meta */"

    case .keyboardMetaControl:
      return " /* TODO: keyboard meta-control */"

    case .namedCharacter:
      return " /* TODO: named character */"

    case .any:
      return ".any"

    case .startOfLine, .endOfLine:
      fatalError("unreachable")

    case .backreference:
      return " /* TODO: back reference */"

    case .subpattern:
      return " /* TODO: subpattern */"

    case .callout:
      return " /* TODO: callout */"

    case .backtrackingDirective:
      return " /* TODO: backtracking directive */"
    }
  }
}

extension AST.Group.Kind {
  var _patternBase: String {
    switch self {
    case .capture:
      // TODO: We probably want this to be a property after group
      return ".capture"

    case .namedCapture(let n):
      return "name: \"\(n)\""

    case .balancedCapture:
      return "/* TODO: balanced captures */"

    case .nonCapture: return ""

    case .nonCaptureReset:
      return "/* TODO: non-capture reset */"

    case .atomicNonCapturing:
      return "/* TODO: atomicNonCapturing */"
    case .lookahead:
      return "/* TODO: lookahead */"
    case .negativeLookahead:
      return "/* TODO: negativeLookahead */"
    case .nonAtomicLookahead:
      return "/* TODO: nonAtomicLookahead */"
    case .lookbehind:
      return "/* TODO: lookbehind */"
    case .negativeLookbehind:
      return "/* TODO: negativeLookbehind */"
    case .nonAtomicLookbehind:
      return "/* TODO: nonAtomicLookbehind */"
    case .scriptRun:
      return "/* TODO: scriptRun */"
    case .atomicScriptRun:
      return "/* TODO: atomicScriptRun */"
    case .changeMatchingOptions:
      return "/* TODO: changeMatchingOptions */"

    @unknown default:
      fatalError()
    }
  }
}

extension AST.Quantification.Amount {
  var _patternBase: String {
    switch self {
    case .zeroOrMore: return "ZeroOrMore"
    case .oneOrMore:  return "OneOrMore"
    case .zeroOrOne:  return "ZeroOrOne"
    case let .exactly(n):  return "Quantitified(exactly: \(n))"
    case let .nOrMore(n):  return "Quantified(\(n)...)"
    case let .upToN(n):    return "Quantified(...\(n))"
    case let .range(n, m): return "Quantified(\(n)...\(m))"
    }
  }
}

extension AST.Quantification.Kind {
  var _patternBase: String {
    switch self {
    case .eager: return ".eager"
    case .reluctant: return ".reluctant"
    case .possessive: return ".possessive"
    }
  }
}
