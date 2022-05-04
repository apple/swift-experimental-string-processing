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

// TODO: Round-tripping tests

extension AST {
  /// Renders using Swift's preferred regex literal syntax.
  public func renderAsCanonical(
    showDelimiters delimiters: Bool = false,
    terminateLine: Bool = false
  ) -> String {
    var printer = PrettyPrinter()
    printer.printAsCanonical(
       self,
       delimiters: delimiters,
       terminateLine: terminateLine)
    return printer.finish()
  }
}

extension AST.Node {
  /// Renders using Swift's preferred regex literal syntax.
  public func renderAsCanonical(
    showDelimiters delimiters: Bool = false,
    terminateLine: Bool = false
  ) -> String {
    AST(self, globalOptions: nil).renderAsCanonical(
      showDelimiters: delimiters, terminateLine: terminateLine)
  }
}

extension PrettyPrinter {
  /// Outputs a regular expression abstract syntax tree in canonical form,
  /// indenting and terminating the line, and updating its internal state.
  ///
  /// - Parameter ast: The abstract syntax tree of the regular expression being output.
  /// - Parameter delimiters: Whether to include commas between items.
  /// - Parameter terminateLine: Whether to include terminate the line.
  public mutating func printAsCanonical(
    _ ast: AST,
    delimiters: Bool = false,
    terminateLine terminate: Bool = true
  ) {
    indent()
    if delimiters { output("'/") }
    if let opts = ast.globalOptions {
      outputAsCanonical(opts)
    }
    outputAsCanonical(ast.root)
    if delimiters { output("/'") }
    if terminate {
      terminateLine()
    }
  }

  /// Outputs a regular expression abstract syntax tree in canonical form,
  /// without indentation, line termation, or affecting its internal state.
  mutating func outputAsCanonical(_ ast: AST.Node) {
    switch ast {
    case let .alternation(a):
      for idx in a.children.indices {
        outputAsCanonical(a.children[idx])
        if a.children.index(after: idx) != a.children.endIndex {
          output("|")
        }
      }
    case let .concatenation(c):
      c.children.forEach { outputAsCanonical($0) }
    case let .group(g):
      output(g.kind.value._canonicalBase)
      outputAsCanonical(g.child)
      output(")")

    case let .conditional(c):
      output("(")
      outputAsCanonical(c.condition)
      outputAsCanonical(c.trueBranch)
      output("|")
      outputAsCanonical(c.falseBranch)

    case let .quantification(q):
      outputAsCanonical(q.child)
      output(q.amount.value._canonicalBase)
      output(q.kind.value._canonicalBase)

    case let .quote(q):
      output(q._canonicalBase)

    case let .trivia(t):
      output(t._canonicalBase)

    case let .atom(a):
      output(a._canonicalBase)

    case let .customCharacterClass(ccc):
      outputAsCanonical(ccc)

    case let .absentFunction(abs):
      outputAsCanonical(abs)

    case .empty:
      output("")
    }
  }

  mutating func outputAsCanonical(
    _ ccc: AST.CustomCharacterClass
  ) {
    output(ccc.start.value._canonicalBase)
    ccc.members.forEach { outputAsCanonical($0) }
    output("]")
  }

  mutating func outputAsCanonical(
    _ member: AST.CustomCharacterClass.Member
  ) {
    // TODO: Do we need grouping or special escape rules?
    switch member {
    case .custom(let ccc):
      outputAsCanonical(ccc)
    case .range(let r):
      output(r.lhs._canonicalBase)
      output("-")
      output(r.rhs._canonicalBase)
    case .atom(let a):
      output(a._canonicalBase)
    case .quote(let q):
      output(q._canonicalBase)
    case .trivia(let t):
      output(t._canonicalBase)
    case .setOperation:
      output("/* TODO: set operation \(self) */")
    }
  }

  mutating func outputAsCanonical(_ condition: AST.Conditional.Condition) {
    output("(/*TODO: conditional \(condition) */)")
  }

  mutating func outputAsCanonical(_ abs: AST.AbsentFunction) {
    output("(?~")
    switch abs.kind {
    case .repeater(let a):
      outputAsCanonical(a)
    case .expression(let a, _, let child):
      output("|")
      outputAsCanonical(a)
      output("|")
      outputAsCanonical(child)
    case .stopper(let a):
      output("|")
      outputAsCanonical(a)
    case .clearer:
      output("|")
    }
    output(")")
  }

  mutating func outputAsCanonical(_ opts: AST.GlobalMatchingOptionSequence) {
    for opt in opts.options {
      output(opt._canonicalBase)
    }
  }
}

extension AST.Quote {
  var _canonicalBase: String {
    // TODO: Is this really what we want?
    "\\Q\(literal)\\E"
  }
}

extension AST.Group.Kind {
  var _canonicalBase: String {
    switch self {
    case .capture:                return "("
    case .namedCapture(let n):    return "(?<\(n.value)>"
    case .balancedCapture(let b): return "(?<\(b._canonicalBase)>"
    case .nonCapture:             return "(?:"
    case .nonCaptureReset:        return "(?|"
    case .atomicNonCapturing:     return "(?>"
    case .lookahead:              return "(?="
    case .negativeLookahead:      return "(?!"
    case .nonAtomicLookahead:     return "(?*"
    case .lookbehind:             return "(?<="
    case .negativeLookbehind:     return "(?<!"
    case .nonAtomicLookbehind:    return "(?<*"
    case .scriptRun:              return "(*sr:"
    case .atomicScriptRun:        return "(*asr:"

    case .changeMatchingOptions:
      return "(/* TODO: matchign options in canonical form */"
    }
  }
}

extension AST.Quantification.Amount {
  var _canonicalBase: String {
    switch self {
    case .zeroOrMore:      return "*"
    case .oneOrMore:       return "+"
    case .zeroOrOne:       return "?"
    case let .exactly(n):  return "{\(n.value)}"
    case let .nOrMore(n):  return "{\(n.value),}"
    case let .upToN(n):    return "{,\(n.value)}"
    case let .range(lower, upper):
      return "{\(lower),\(upper)}"
    }
  }
}
extension AST.Quantification.Kind {
  var _canonicalBase: String { self.rawValue }
}

extension AST.Atom {
  var _canonicalBase: String {
    if let anchor = self.assertionKind {
      return anchor.rawValue
    }
    if let lit = self.literalStringValue {
      // FIXME: We may have to re-introduce escapes
      // For example, `\.` will come back as "." instead
      // For now, catch the most common offender
      if lit == "." { return "\\." }
      return lit
    }
    switch self.kind {
    case .escaped(let e):
      return "\\\(e.character)"
    case .backreference(let br):
       return br._canonicalBase

    default:
      return "/* TODO: atom \(self) */"
    }
  }
}

extension AST.Reference {
  var _canonicalBase: String {
    if self.recursesWholePattern {
      return "(?R)"
    }
    switch kind {
    case .absolute(let i):
      // TODO: Which should we prefer, this or `\g{n}`?
      return "\\\(i)"
    case .relative:
      return "/* TODO: relative reference \(self) */"
    case .named:
      return "/* TODO: named reference \(self) */"
    }
  }
}

extension AST.CustomCharacterClass.Start {
  var _canonicalBase: String { self.rawValue }
}

extension AST.Group.BalancedCapture {
  var _canonicalBase: String {
    "\(name?.value ?? "")-\(priorName.value)"
  }
}

extension AST.GlobalMatchingOption.NewlineMatching {
  var _canonicalBase: String {
    switch self {
    case .carriageReturnOnly:          return "CR"
    case .linefeedOnly:                return "LF"
    case .carriageAndLinefeedOnly:     return "CRLF"
    case .anyCarriageReturnOrLinefeed: return "ANYCRLF"
    case .anyUnicode:                  return "ANY"
    case .nulCharacter:                return "NUL"
    }
  }
}

extension AST.GlobalMatchingOption.NewlineSequenceMatching {
  var _canonicalBase: String {
    switch self {
    case .anyCarriageReturnOrLinefeed: return "BSR_ANYCRLF"
    case .anyUnicode:                  return "BSR_UNICODE"
    }
  }
}

extension AST.GlobalMatchingOption.Kind {
  var _canonicalBase: String {
    switch self {
    case .limitDepth(let i):              return "LIMIT_DEPTH=\(i.value)"
    case .limitHeap(let i):               return "LIMIT_HEAP=\(i.value)"
    case .limitMatch(let i):              return "LIMIT_MATCH=\(i.value)"
    case .notEmpty:                       return "NOTEMPTY"
    case .notEmptyAtStart:                return "NOTEMPTY_ATSTART"
    case .noAutoPossess:                  return "NO_AUTO_POSSESS"
    case .noDotStarAnchor:                return "NO_DOTSTAR_ANCHOR"
    case .noJIT:                          return "NO_JIT"
    case .noStartOpt:                     return "NO_START_OPT"
    case .utfMode:                        return "UTF"
    case .unicodeProperties:              return "UCP"
    case .newlineMatching(let m):         return m._canonicalBase
    case .newlineSequenceMatching(let m): return m._canonicalBase
    }
  }
}

extension AST.GlobalMatchingOption {
  var _canonicalBase: String { "(*\(kind._canonicalBase))"}
}

extension AST.Trivia {
  var _canonicalBase: String {
    // TODO: We might want to output comments...
    ""
  }
}
