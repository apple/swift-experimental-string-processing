import _MatchingEngine

extension Compiler {
  struct ByteCodeGen {
    var options: MatchingOptions
    var builder = Program.Builder()

    mutating func finish(
    ) throws -> Program {
      builder.buildAccept()
      return try builder.assemble()
    }
  }
}

extension Compiler.ByteCodeGen {
  mutating func emitAtom(_ a: DSLTree.Atom) throws {
    switch a {
    case .any:
      emitAny()

    case let .char(c):
      try emitCharacter(c)
      
    case let .scalar(s):
      try emitScalar(s)
      
    case let .assertion(kind):
      try emitAssertion(kind)

    case let .backreference(ref):
      try emitBackreference(ref)

    case let .subpattern(ref):
      try emitSubpattern(ref)

    case let .symbolicReference(id):
      builder.buildUnresolvedReference(id: id)

    case let .unconverted(astAtom):
      if let consumer = try astAtom.generateConsumer(options) {
        builder.buildConsume(by: consumer)
      } else {
        throw Unsupported("\(astAtom._patternBase)")
      }
    }
  }

  mutating func emitSubpattern(_ ref: AST.Reference) throws {
    switch ref.kind {
    case .absolute(let i):
      builder.buildCallSubpattern(i)
    case .relative, .named:
      throw Unsupported("Subpattern kind: \(ref)")
    }
  }

  mutating func emitBackreference(
    _ ref: AST.Reference
  ) throws {
    if ref.recursesWholePattern {
      // TODO: A recursive call isn't a backreference, but
      // we could in theory match the whole match so far...
      throw Unsupported("Backreference kind: \(ref)")
    }

    switch ref.kind {
    case .absolute(let i):
      // Backreferences number starting at 1
      builder.buildBackreference(.init(i-1))
    case .relative, .named:
      throw Unsupported("Backreference kind: \(ref)")
    }
  }

  mutating func emitAssertion(
    _ kind: AST.Atom.AssertionKind
  ) throws {
    // FIXME: Depends on API model we have... We may want to
    // think through some of these with API interactions in mind
    //
    // This might break how we use `bounds` for both slicing
    // and things like `firstIndex`, that is `firstIndex` may
    // need to supply both a slice bounds and a per-search bounds.
    switch kind {
    case .startOfSubject:
      builder.buildAssert { (input, pos, bounds) in
        pos == input.startIndex
      }

    case .endOfSubjectBeforeNewline:
      builder.buildAssert { (input, pos, bounds) in
        if pos == input.endIndex { return true }
        return input.index(after: pos) == input.endIndex
         && input[pos].isNewline
      }

    case .endOfSubject:
      builder.buildAssert { (input, pos, bounds) in
        pos == input.endIndex
      }

    case .resetStartOfMatch:
      // FIXME: Figure out how to communicate this out
      throw Unsupported(#"\K (reset/keep assertion)"#)

    case .firstMatchingPositionInSubject:
      // TODO: We can probably build a nice model with API here
      builder.buildAssert { (input, pos, bounds) in
        pos == bounds.lowerBound
      }

    case .textSegment:
      builder.buildAssert { (input, pos, _) in
        // FIXME: Grapheme or word based on options
        input.isOnGraphemeClusterBoundary(pos)
      }

    case .notTextSegment:
      builder.buildAssert { (input, pos, _) in
        // FIXME: Grapheme or word based on options
        !input.isOnGraphemeClusterBoundary(pos)
      }

    case .startOfLine:
      builder.buildAssert { (input, pos, bounds) in
        pos == input.startIndex ||
        input[input.index(before: pos)].isNewline
      }

    case .endOfLine:
      builder.buildAssert { (input, pos, bounds) in
        pos == input.endIndex || input[pos].isNewline
      }

    case .wordBoundary:
      // TODO: May want to consider Unicode level
      builder.buildAssert { (input, pos, bounds) in
        // TODO: How should we handle bounds?
        CharacterClass.word.isBoundary(
          input, at: pos, bounds: bounds)
      }

    case .notWordBoundary:
      // TODO: May want to consider Unicode level
      builder.buildAssert { (input, pos, bounds) in
        // TODO: How should we handle bounds?
        !CharacterClass.word.isBoundary(
          input, at: pos, bounds: bounds)
      }
    }
  }
  
  mutating func emitScalar(_ s: UnicodeScalar) throws {
    // TODO: Native instruction buildMatchScalar(s)
    if options.isCaseInsensitive {
      // TODO: e.g. buildCaseInsensitiveMatchScalar(s)
      builder.buildConsume(by: consumeScalar {
        $0.properties.lowercaseMapping == s.properties.lowercaseMapping
      })
    } else {
      builder.buildConsume(by: consumeScalar {
        $0 == s
      })
    }
  }
  
  mutating func emitCharacter(_ c: Character) throws {
    // FIXME: Does semantic level matter?
    if options.isCaseInsensitive && c.isCased {
      // TODO: buildCaseInsensitiveMatch(c) or buildMatch(c, caseInsensitive: true)
      builder.buildConsume { input, bounds in
        let inputChar = input[bounds.lowerBound].lowercased()
        let matchChar = c.lowercased()
        return inputChar == matchChar
          ? input.index(after: bounds.lowerBound)
          : nil
      }
    } else {
      builder.buildMatch(c)
    }
  }

  mutating func emitAny() {
    switch (options.semanticLevel, options.dotMatchesNewline) {
    case (.graphemeCluster, true):
      builder.buildAdvance(1)
    case (.graphemeCluster, false):
      builder.buildConsume { input, bounds in
        input[bounds.lowerBound].isNewline
        ? nil
        : input.index(after: bounds.lowerBound)
      }

    case (.unicodeScalar, true):
      // TODO: builder.buildAdvanceUnicodeScalar(1)
      builder.buildConsume { input, bounds in
        input.unicodeScalars.index(after: bounds.lowerBound)
      }
    case (.unicodeScalar, false):
      builder.buildConsume { input, bounds in
        input[bounds.lowerBound].isNewline
        ? nil
        : input.unicodeScalars.index(after: bounds.lowerBound)
      }
    }
  }

  mutating func emitAlternation(
    _ children: [DSLTree.Node]
  ) throws {
    // Alternation: p0 | p1 | ... | pn
    //     save next_p1
    //     <code for p0>
    //     branch done
    //   next_p1:
    //     save next_p2
    //     <code for p1>
    //     branch done
    //   next_p2:
    //     save next_p...
    //     <code for p2>
    //     branch done
    //   ...
    //   next_pn:
    //     <code for pn>
    //   done:
    let done = builder.makeAddress()
    for component in children.dropLast() {
      let next = builder.makeAddress()
      builder.buildSave(next)
      try emitNode(component)
      builder.buildBranch(to: done)
      builder.label(next)
    }
    try emitNode(children.last!)
    builder.label(done)
  }

  mutating func emitConcatenationComponent(
    _ node: DSLTree.Node
  ) throws {
    // TODO: Should we do anything special since we can
    // be glueing sub-grapheme components together?
    try emitNode(node)
  }

  mutating func emitLookaround(
    _ kind: (forwards: Bool, positive: Bool),
    _ child: DSLTree.Node
  ) throws {
    guard kind.forwards else {
      throw Unsupported("backwards assertions")
    }

    let positive = kind.positive
    /*
      save(restoringAt: success)
      save(restoringAt: intercept)
      <sub-pattern>    // failure restores at intercept
      clearSavePoint   // remove intercept
      <if negative>:
        clearSavePoint // remove success
      fail             // positive->success, negative propagates
    intercept:
      <if positive>:
        clearSavePoint // remove success
      fail             // positive propagates, negative->success
    success:
      ...
    */

    let intercept = builder.makeAddress()
    let success = builder.makeAddress()

    builder.buildSave(success)
    builder.buildSave(intercept)
    try emitNode(child)
    builder.buildClear()
    if !positive {
      builder.buildClear()
    }
    builder.buildFail()

    builder.label(intercept)
    if positive {
      builder.buildClear()
    }
    builder.buildFail()

    builder.label(success)
  }

  mutating func emitMatcher(
    _ matcher: @escaping _MatcherInterface,
    into capture: CaptureRegister? = nil
  ) {

    // TODO: Consider emitting consumer interface if
    // not captured. This may mean we should store
    // an existential instead of a closure...

    let matcher = builder.makeMatcherFunction(matcher)

    let valReg = builder.makeValueRegister()
    builder.buildMatcher(matcher, into: valReg)

    // TODO: Instruction to store directly
    if let cap = capture {
      builder.buildMove(valReg, into: cap)
    }
  }

  mutating func emitGroup(
    _ kind: AST.Group.Kind,
    _ child: DSLTree.Node,
    _ referenceID: ReferenceID?
  ) throws -> CaptureRegister? {
    guard kind.isCapturing || referenceID == nil else {
      throw Unreachable("Reference ID shouldn't exist for non-capturing groups")
    }

    options.beginScope()
    defer { options.endScope() }

    // If we have a strong type, write result directly into
    // the capture register.
    //
    // FIXME: Unify with .groupTransform
    if kind.isCapturing, case let .matcher(_, m) = child {
      let cap = builder.makeCapture(id: referenceID)
      emitMatcher(m, into: cap)
      return cap
    }

    if let lookaround = kind.lookaroundKind {
      try emitLookaround(lookaround, child)
      return nil
    }

    switch kind {
    case .lookahead, .negativeLookahead,
        .lookbehind, .negativeLookbehind:
      throw Unreachable("TODO: reason")

    case .capture, .namedCapture:
      let cap = builder.makeCapture(id: referenceID)
      builder.buildBeginCapture(cap)
      let subpatternCaller = builder.makeAddress()
      builder.buildBranch(to: subpatternCaller)
      let subpatternFn = builder.makeSubpatternAddress(cap)
      builder.label(subpatternFn)
      try emitNode(child)
      builder.buildRet()
      builder.label(subpatternCaller)
      builder.buildCall(subpatternFn)
      builder.buildEndCapture(cap)
      return cap

    case .changeMatchingOptions(let optionSequence, _):
      options.apply(optionSequence)
      try emitNode(child)
      return nil

    default:
      // FIXME: Other kinds...
      try emitNode(child)
      return nil
    }
  }

  mutating func emitQuantification(
    _ amount: AST.Quantification.Amount,
    _ kind: AST.Quantification.Kind,
    _ child: DSLTree.Node
  ) throws {
    let kind = kind.applying(options)

    let (low, high) = amount.bounds
    switch (low, high) {
    case (_, 0):
      // TODO: Should error out earlier, maybe DSL and parser
      // has validation logic?
      return
    case let (n, m?) where n > m:
      // TODO: Should error out earlier, maybe DSL and parser
      // has validation logic?
      return

    case let (n, m) where m == nil || n <= m!:
      // Ok
      break
    default:
      throw Unreachable("TODO: reason")
    }

    // Compiler and/or parser should enforce these invariants
    // before we are called
    assert(high != 0)
    assert((0...(high ?? Int.max)).contains(low))

    let extraTrips: Int?
    if let h = high {
      extraTrips = h - low
    } else {
      extraTrips = nil
    }
    let minTrips = low
    assert((extraTrips ?? 1) >= 0)

    // The below is a general algorithm for bounded and unbounded
    // quantification. It can be specialized when the min
    // is 0 or 1, or when extra trips is 1 or unbounded.
    //
    // Stuff inside `<` and `>` are decided at compile time,
    // while run-time values stored in registers start with a `%`
    _ = """
      min-trip-count control block:
        if %minTrips is zero:
          goto exit-policy control block
        else:
          decrement %minTrips and fallthrough

      loop-body:
        evaluate the subexpression
        goto min-trip-count control block

      exit-policy control block:
        if %extraTrips is zero:
          goto exit
        else:
          decrement %extraTrips and fallthrough

        <if eager>:
          save exit and goto loop-body
        <if possessive>:
          ratchet and goto loop
        <if reluctant>:
          save loop-body and fallthrough (i.e. goto exit)

      exit
        ... the rest of the program ...
    """

    // Specialization based on `minTrips` for 0 or 1:
    _ = """
      min-trip-count control block:
        <if minTrips == 0>:
          goto exit-policy
        <if minTrips == 1>:
          /* fallthrough */

      loop-body:
        evaluate the subexpression
        <if minTrips <= 1>
          /* fallthrough */
    """

    // Specialization based on `extraTrips` for 0 or unbounded
    _ = """
      exit-policy control block:
        <if extraTrips == 0>:
          goto exit
        <if extraTrips == .unbounded>:
          /* fallthrough */
    """

    /*
      NOTE: These specializations don't emit the optimal
      code layout (e.g. fallthrough vs goto), but that's better
      done later (not prematurely) and certainly better
      done by an optimizing compiler.

      NOTE: We're intentionally emitting essentially the same
      algorithm for all quantifications for now, for better
      testing and surfacing difficult bugs. We can specialize
      for other things, like `.*`, later.

      When it comes time for optimizing, we can also look into
      quantification instructions (e.g. reduce save-point traffic)
    */

    let minTripsControl = builder.makeAddress()
    let loopBody = builder.makeAddress()
    let exitPolicy = builder.makeAddress()
    let exit = builder.makeAddress()

    // We'll need registers if we're (non-trivially) bounded
    let minTripsReg: IntRegister?
    if minTrips > 1 {
      minTripsReg = builder.makeIntRegister(
        initialValue: minTrips)
    } else {
      minTripsReg = nil
    }

    let extraTripsReg: IntRegister?
    if (extraTrips ?? 0) > 0 {
      extraTripsReg = builder.makeIntRegister(
        initialValue: extraTrips!)
    } else {
      extraTripsReg = nil
    }

    // Set up a dummy save point for possessive to update
    if kind == .possessive {
      builder.pushEmptySavePoint()
    }

    // min-trip-count:
    //   condBranch(to: exitPolicy, ifZeroElseDecrement: %min)
    builder.label(minTripsControl)
    switch minTrips {
    case 0: builder.buildBranch(to: exitPolicy)
    case 1: break
    default:
      assert(minTripsReg != nil, "logic inconsistency")
      builder.buildCondBranch(
        to: exitPolicy, ifZeroElseDecrement: minTripsReg!)
    }

    // FIXME: Possessive needs a "dummy" save point to ratchet

    // loop:
    //   <subexpression>
    //   branch min-trip-count
    builder.label(loopBody)
    try emitNode(child)
    if minTrips <= 1 {
      // fallthrough
    } else {
      builder.buildBranch(to: minTripsControl)
    }

    // exit-policy:
    //   condBranch(to: exit, ifZeroElseDecrement: %extraTrips)
    //   <eager: split(to: loop, saving: exit)>
    //   <possesive:
    //     clearSavePoint
    //     split(to: loop, saving: exit)>
    //   <reluctant: save(restoringAt: loop)
    builder.label(exitPolicy)
    switch extraTrips {
    case nil: break
    case 0:   builder.buildBranch(to: exit)
    default:
      assert(extraTripsReg != nil, "logic inconsistency")
      builder.buildCondBranch(
        to: exit, ifZeroElseDecrement: extraTripsReg!)
    }

    switch kind {
    case .eager:
      builder.buildSplit(to: loopBody, saving: exit)
    case .possessive:
      builder.buildClear()
      builder.buildSplit(to: loopBody, saving: exit)
    case .reluctant:
      builder.buildSave(loopBody)
      // FIXME: Is this re-entrant? That is would nested
      // quantification break if trying to restore to a prior
      // iteration because the register got overwritten?
      //
    }

    builder.label(exit)
  }

  mutating func emitCustomCharacterClass(
    _ ccc: DSLTree.CustomCharacterClass
  ) throws {
    let consumer = try ccc.generateConsumer(options)
    builder.buildConsume(by: consumer)
  }

  mutating func emitNode(_ node: DSLTree.Node) throws {
    switch node {
      
    case let .alternation(children):
      try emitAlternation(children)

    case let .concatenation(children):
      for child in children {
        try emitConcatenationComponent(child)
      }

    case let .group(kind, child, referenceID):
      _ = try emitGroup(kind, child, referenceID)

    case .conditional:
      throw Unsupported("Conditionals")

    case let .quantification(amt, kind, child):
      try emitQuantification(amt, kind, child)

    case let .customCharacterClass(ccc):
      try emitCustomCharacterClass(ccc)

    case let .atom(a):
      try emitAtom(a)

    case let .quotedLiteral(s):
      // TODO: Should this incorporate options?
      if options.isCaseInsensitive {
        // TODO: buildCaseInsensitiveMatchSequence(c) or alternative
        builder.buildConsume { input, bounds in
          var iterator = s.makeIterator()
          var currentIndex = bounds.lowerBound
          while let ch = iterator.next() {
            guard currentIndex < bounds.upperBound,
                  ch.lowercased() == input[currentIndex].lowercased()
            else { return nil }
            input.formIndex(after: &currentIndex)
          }
          return currentIndex
        }
      } else {
        builder.buildMatchSequence(s)
      }

    case let .regexLiteral(l):
      try emitNode(l.dslTreeNode)

    case let .convertedRegexLiteral(n, _):
      try emitNode(n)

    case let .groupTransform(kind, child, t, referenceID):
      guard let cap = try emitGroup(kind, child, referenceID) else {
        assertionFailure("""
          What does it mean to not have a capture to transform?
          """)
        return
      }

      // FIXME: Is this how we want to do it?
      let transform = builder.makeTransformFunction {
        input, range in
        t(input[range])
      }

      builder.buildTransformCapture(cap, transform)

    case .absentFunction:
      throw Unsupported("absent function")
    case .consumer:
      throw Unsupported("consumer")

    case let .matcher(_, f):
      emitMatcher(f)

    case .characterPredicate:
      throw Unsupported("character predicates")

    case .trivia, .empty:
      return
    }
  }
}

