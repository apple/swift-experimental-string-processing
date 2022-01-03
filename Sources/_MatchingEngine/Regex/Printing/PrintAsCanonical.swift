// TODO: Round-tripping tests

extension AST {
  /// Render using Swift's preferred regex literal syntax
  public func renderAsCanonical(
    showDelimiters delimiters: Bool = false
  ) -> String {
    var printer = PrettyPrinter()
    printer.printAsCanonical(self, delimiters: delimiters)
    return printer.finish()
  }
}

extension PrettyPrinter {
  /// Will output `ast` in canonical form, taking care to
  /// also indent and terminate the line (updating internal state)
  mutating func printAsCanonical(
    _ ast: AST, delimiters: Bool = false
  ) {
    indent()
    if delimiters { output("'/") }
    outputAsCanonical(ast)
    if delimiters { output("/'") }
    terminateLine()
  }

  /// Output the `ast` in canonical form, does not indent, terminate,
  /// or affect internal state
  mutating func outputAsCanonical(_ ast: AST) {
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

    case let .quantification(q):
      outputAsCanonical(q.child)
      output(q.amount.value._canonicalBase)
      output(q.kind.value._canonicalBase)

    case let .quote(q):
      // TODO: Is this really what we want?
      output("\\Q\(q.literal)\\E")

    case let .trivia(t):
      // TODO: We might want to output comments...
      _ = t
      output("")

    case let .atom(a):
      output(a._canonicalBase)

    case let .customCharacterClass(ccc):
      outputAsCanonical(ccc)

    case .empty:
      output("")

    case .groupTransform:
      output("/* TODO: get groupTransform out of AST */")
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
    case .range(let a, let b):
      output(a._canonicalBase)
      output("-")
      output(b._canonicalBase)
    case .atom(let a):
      output(a._canonicalBase)
    case .setOperation:
      output("/* TODO: set operation \(self) */")
    }
  }
}

extension AST.Group.Kind {
  var _canonicalBase: String {
    switch self {
    case .capture:              return "("
    case .namedCapture(let n):  return "(?<\(n.value)>"
    case .nonCapture:           return "(?:"
    case .nonCaptureReset:      return "(?|"
    case .atomicNonCapturing:   return "(?>"
    case .lookahead:            return "(?="
    case .negativeLookahead:    return "(?!"
    case .nonAtomicLookahead:   return "(?*"
    case .lookbehind:           return "(?<="
    case .negativeLookbehind:   return "(?<!"
    case .nonAtomicLookbehind:  return "(?<*"
    case .scriptRun:            return "(*sr:"
    case .atomicScriptRun:      return "(*asr:"

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

    default:
      return "/* TODO: atom \(self) */"
    }
  }
}

extension AST.CustomCharacterClass.Start {
  var _canonicalBase: String { self.rawValue }
}
