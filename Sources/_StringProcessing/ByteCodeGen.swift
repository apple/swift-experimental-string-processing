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

@_spi(_Unicode)
import Swift

@_implementationOnly import _RegexParser

extension Compiler {
  struct ByteCodeGen {
    var options: MatchingOptions
    var builder = MEProgram.Builder()
    /// A Boolean indicating whether the first matchable atom has been emitted.
    /// This is used to determine whether to apply initial options.
    var hasEmittedFirstMatchableAtom = false

    private let compileOptions: CompileOptions
    fileprivate var optimizationsEnabled: Bool { !compileOptions.contains(.disableOptimizations) }

    init(
      options: MatchingOptions,
      compileOptions: CompileOptions,
      captureList: CaptureList
    ) {
      self.options = options
      self.compileOptions = compileOptions
      self.builder.captureList = captureList
    }
  }
}

extension Compiler.ByteCodeGen {
  mutating func emitRoot(_ root: DSLTree.Node) throws -> MEProgram {
    // The whole match (`.0` element of output) is equivalent to an implicit
    // capture over the entire regex.
    try emitNode(.capture(name: nil, reference: nil, root))
    builder.buildAccept()
    return try builder.assemble()
  }
}

fileprivate extension Compiler.ByteCodeGen {
  mutating func emitAtom(_ a: DSLTree.Atom) throws {
    defer {
      if a.isMatchable {
        hasEmittedFirstMatchableAtom = true
      }
    }
    switch a {
    case .any:
      emitAny()

    case .anyNonNewline:
      emitAnyNonNewline()

    case .dot:
      emitDot()

    case let .char(c):
      emitCharacter(c)

    case let .scalar(s):
      if options.semanticLevel == .graphemeCluster {
        emitCharacter(Character(s))
      } else {
        emitMatchScalar(s)
      }

    case let .characterClass(cc):
      emitCharacterClass(cc)

    case let .assertion(kind):
      try emitAssertion(kind)

    case let .backreference(ref):
      try emitBackreference(ref.ast)

    case let .symbolicReference(id):
      builder.buildUnresolvedReference(id: id)

    case let .changeMatchingOptions(optionSequence):
      if !hasEmittedFirstMatchableAtom {
        builder.initialOptions.apply(optionSequence.ast)
      }
      options.apply(optionSequence.ast)

    case let .unconverted(astAtom):
      if let consumer = try astAtom.ast.generateConsumer(options) {
        builder.buildConsume(by: consumer)
      } else {
        throw Unsupported("\(astAtom.ast._patternBase)")
      }
    }
  }

  mutating func emitQuotedLiteral(_ s: String) {
    guard options.semanticLevel == .graphemeCluster else {
      for char in s {
        for scalar in char.unicodeScalars {
          emitMatchScalar(scalar)
        }
      }
      return
    }

    // Fast path for eliding boundary checks for an all ascii quoted literal
    if optimizationsEnabled && s.allSatisfy(\.isASCII) {
      let lastIdx = s.unicodeScalars.indices.last!
      for idx in s.unicodeScalars.indices {
        let boundaryCheck = idx == lastIdx
        let scalar = s.unicodeScalars[idx]
        if options.isCaseInsensitive && scalar.properties.isCased {
          builder.buildMatchScalarCaseInsensitive(scalar, boundaryCheck: boundaryCheck)
        } else {
          builder.buildMatchScalar(scalar, boundaryCheck: boundaryCheck)
        }
      }
      return
    }

    for c in s { emitCharacter(c) }
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
    case .absolute(let n):
      guard let i = n.value else {
        throw Unreachable("Expected a value")
      }
      builder.buildBackreference(.init(i))
    case .named(let name):
      try builder.buildNamedReference(name)
    case .relative:
      throw Unsupported("Backreference kind: \(ref)")
    }
  }

  mutating func emitAssertion(
    _ kind: DSLTree.Atom.Assertion
  ) throws {
    if kind == .resetStartOfMatch {
      throw Unsupported(#"\K (reset/keep assertion)"#)
    }
    builder.buildAssert(
      by: kind,
      options.anchorsMatchNewlines,
      options.usesSimpleUnicodeBoundaries,
      options.usesASCIIWord,
      options.semanticLevel)
  }

  mutating func emitCharacterClass(_ cc: DSLTree.Atom.CharacterClass) {
    builder.buildMatchBuiltin(
      cc.model,
      cc.model.isStrictAscii(options: options),
      isScalar: options.semanticLevel == .unicodeScalar)
  }

  mutating func emitMatchScalar(_ s: UnicodeScalar) {
    assert(options.semanticLevel == .unicodeScalar)
    if options.isCaseInsensitive && s.properties.isCased {
      builder.buildMatchScalarCaseInsensitive(s, boundaryCheck: false)
    } else {
      builder.buildMatchScalar(s, boundaryCheck: false)
    }
  }
  
  mutating func emitCharacter(_ c: Character) {
    // Unicode scalar mode matches the specific scalars that comprise a character
    if options.semanticLevel == .unicodeScalar {
      for scalar in c.unicodeScalars {
        emitMatchScalar(scalar)
      }
      return
    }
    
    if options.isCaseInsensitive && c.isCased {
      if optimizationsEnabled && c.isASCII {
        // c.isCased ensures that c is not CR-LF,
        // so we know that c is a single scalar
        assert(c.unicodeScalars.count == 1)
        builder.buildMatchScalarCaseInsensitive(
          c.unicodeScalars.last!,
          boundaryCheck: true)
      } else {
        builder.buildMatch(c, isCaseInsensitive: true)
      }
      return
    }
    
    if optimizationsEnabled && c.isASCII {
      let lastIdx = c.unicodeScalars.indices.last!
      for idx in c.unicodeScalars.indices {
        builder.buildMatchScalar(c.unicodeScalars[idx], boundaryCheck: idx == lastIdx)
      }
      return
    }
      
    builder.buildMatch(c, isCaseInsensitive: false)
  }

  mutating func emitAny() {
    switch options.semanticLevel {
    case .graphemeCluster:
      builder.buildAdvance(1)
    case .unicodeScalar:
      // TODO: builder.buildAdvanceUnicodeScalar(1)
      builder.buildConsume { input, bounds in
        input.unicodeScalars.index(after: bounds.lowerBound)
      }
    }
  }

  mutating func emitAnyNonNewline() {
    switch options.semanticLevel {
    case .graphemeCluster:
      builder.buildConsume { input, bounds in
        input[bounds.lowerBound].isNewline
        ? nil
        : input.index(after: bounds.lowerBound)
      }
    case .unicodeScalar:
      builder.buildConsume { input, bounds in
        input[bounds.lowerBound].isNewline
        ? nil
        : input.unicodeScalars.index(after: bounds.lowerBound)
      }
    }
  }

  mutating func emitDot() {
    if options.dotMatchesNewline {
      emitAny()
    } else {
      emitAnyNonNewline()
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
      clearThrough(intercept) // remove intercept and any leftovers from <sub-pattern>
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
    builder.buildClearThrough(intercept)
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

  mutating func emitAtomicNoncapturingGroup(
    _ child: DSLTree.Node
  ) throws {
    /*
      save(continuingAt: success)
      save(restoringAt: intercept)
      <sub-pattern>    // failure restores at intercept
      clearThrough(intercept) // remove intercept and any leftovers from <sub-pattern>
      fail             // ->success
    intercept:
      clearSavePoint   // remove success
      fail             // propagate failure
    success:
      ...
    */

    let intercept = builder.makeAddress()
    let success = builder.makeAddress()

    builder.buildSaveAddress(success)
    builder.buildSave(intercept)
    try emitNode(child)
    builder.buildClearThrough(intercept)
    builder.buildFail()

    builder.label(intercept)
    builder.buildClear()
    builder.buildFail()

    builder.label(success)
  }

  mutating func emitMatcher(
    _ matcher: @escaping _MatcherInterface
  ) -> ValueRegister {

    // TODO: Consider emitting consumer interface if
    // not captured. This may mean we should store
    // an existential instead of a closure...

    let matcher = builder.makeMatcherFunction { input, start, range in
      try matcher(input, start, range)
    }

    let valReg = builder.makeValueRegister()
    builder.buildMatcher(matcher, into: valReg)
    return valReg
  }

  mutating func emitNoncapturingGroup(
    _ kind: AST.Group.Kind,
    _ child: DSLTree.Node
  ) throws {
    assert(!kind.isCapturing)

    options.beginScope()
    defer { options.endScope() }

    if let lookaround = kind.lookaroundKind {
      try emitLookaround(lookaround, child)
      return
    }

    switch kind {
    case .lookahead, .negativeLookahead,
        .lookbehind, .negativeLookbehind:
      throw Unreachable("TODO: reason")

    case .capture, .namedCapture, .balancedCapture:
      throw Unreachable("These should produce a capture node")

    case .changeMatchingOptions(let optionSequence):
      if !hasEmittedFirstMatchableAtom {
        builder.initialOptions.apply(optionSequence)
      }
      options.apply(optionSequence)
      try emitNode(child)
      
    case .atomicNonCapturing:
      try emitAtomicNoncapturingGroup(child)

    default:
      // FIXME: Other kinds...
      try emitNode(child)
    }
  }

  mutating func emitQuantification(
    _ amount: AST.Quantification.Amount,
    _ kind: DSLTree.QuantificationKind,
    _ child: DSLTree.Node
  ) throws {
    let updatedKind: AST.Quantification.Kind
    switch kind {
    case .explicit(let kind):
      updatedKind = kind.ast
    case .syntax(let kind):
      updatedKind = kind.ast.applying(options)
    case .default:
      updatedKind = options.defaultQuantificationKind
    }

    let (low, high) = amount.bounds
    guard let low = low else {
      throw Unreachable("Must have a lower bound")
    }
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

    // We want to specialize common quantification cases
    // Allowed nodes are:
    // - .char
    // - .customCharacterClass
    // - built in character classes
    // - .any, .anyNonNewline, .dot
    // We do this by wrapping a single instruction in a .quantify instruction
    if optimizationsEnabled
        && child.shouldDoFastQuant(options)
        && minTrips <= QuantifyPayload.maxStorableTrips
        && extraTrips ?? 0 <= QuantifyPayload.maxStorableTrips
        && options.matchLevel == .graphemeCluster
        && updatedKind != .reluctant {
      emitFastQuant(child, updatedKind, minTrips, extraTrips)
      return
    }

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
        <if can't guarantee forward progress && extraTrips = nil>:
          mov currentPosition %pos
        evaluate the subexpression
        <if can't guarantee forward progress && extraTrips = nil>:
          if %pos is currentPosition:
            goto exit
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
    if updatedKind == .possessive {
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

    // if we aren't sure if the child node will have forward progress and
    // we have an unbounded quantification
    let startPosition: PositionRegister?
    let emitPositionChecking =
      (!optimizationsEnabled || !child.guaranteesForwardProgress) &&
      extraTrips == nil

    if emitPositionChecking {
      startPosition = builder.makePositionRegister()
      builder.buildMoveCurrentPosition(into: startPosition!)
    } else {
      startPosition = nil
    }
    try emitNode(child)
    if emitPositionChecking {
      // in all quantifier cases, no matter what minTrips or extraTrips is,
      // if we have a successful non-advancing match, branch to exit because it
      // can match an arbitrary number of times
      builder.buildCondBranch(to: exit, ifSamePositionAs: startPosition!)
    }

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

    switch updatedKind {
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

  mutating func emitFastQuant(
    _ child: DSLTree.Node,
    _ kind: AST.Quantification.Kind,
    _ minTrips: Int,
    _ extraTrips: Int?
  ) {
    // These cases must stay in sync with DSLTree.Node.shouldDoFastQuant
    // as well as the compilation paths for these nodes outside of quantification

    // All assumptions made by the processor in runQuantify() must be checked here
    // If an error is thrown here, there must be a mistake in shouldDoFastQuant
    // letting in an invalid case
    
    // Coupling is bad but we do it for _speed_
    switch child {
    case .customCharacterClass(let ccc):
      if let bitset = ccc.asAsciiBitset(options) {
        builder.buildQuantify(bitset: bitset, kind, minTrips, extraTrips)
      } else {
        fatalError("Entered emitFastQuant with an invalid case: Unable to generate bitset")
      }
    case .atom(let atom):
      switch atom {
      case .char(let c):
        if let val = c._singleScalarAsciiValue {
          builder.buildQuantify(asciiChar: val, kind, minTrips, extraTrips)
        } else {
          fatalError("Entered emitFastQuant with an invalid case: Character is not single scalar ascii")
        }
      case .any:
        builder.buildQuantifyAny(matchesNewlines: true, kind, minTrips, extraTrips)
      case .anyNonNewline:
        builder.buildQuantifyAny(matchesNewlines: false, kind, minTrips, extraTrips)
      case .dot:
        builder.buildQuantifyAny(matchesNewlines: options.dotMatchesNewline, kind, minTrips, extraTrips)
      case .characterClass(let cc):
        let model = cc.model
        assert(model.consumesSingleGrapheme,
               "Entered emitFastQuant with an invalid case: Builtin class that does not consume a single grapheme")
        builder.buildQuantify(
          builtin: model.cc,
          isStrict: model.isStrictAscii(options: options),
          isInverted: model.isInverted,
          kind,
          minTrips,
          extraTrips)
      default:
        fatalError("Entered emitFastQuant with an invalid case: DSLTree.Node.shouldDoFastQuant is out of sync")
      }
    case .convertedRegexLiteral(let node, _):
      emitFastQuant(node, kind, minTrips, extraTrips)
    case .nonCapturingGroup(let groupKind, let node):
      assert(groupKind.ast == .nonCapture, "Entered emitFastQuant with an invalid case: Invalid nonCapturingGroup type")
      emitFastQuant(node, kind, minTrips, extraTrips)
    default:
      fatalError("Entered emitFastQuant with an invalid case: DSLTree.Node.shouldDoFastQuant is out of sync")
    }
  }

  mutating func emitCustomCharacterClass(
    _ ccc: DSLTree.CustomCharacterClass
  ) throws {
    if let asciiBitset = ccc.asAsciiBitset(options),
        optimizationsEnabled {
      if options.semanticLevel == .unicodeScalar {
        builder.buildScalarMatchAsciiBitset(asciiBitset)
      } else {
        builder.buildMatchAsciiBitset(asciiBitset)
      }
      return
    }
    let consumer = try ccc.generateConsumer(options)
    builder.buildConsume(by: consumer)
  }

  @discardableResult
  mutating func emitNode(_ node: DSLTree.Node) throws -> ValueRegister? {
    switch node {
      
    case let .orderedChoice(children):
      try emitAlternation(children)

    case let .concatenation(children):
      for child in children {
        try emitConcatenationComponent(child)
      }

    case let .capture(name, refId, child, transform):
      options.beginScope()
      defer { options.endScope() }

      let cap = builder.makeCapture(id: refId, name: name)
      builder.buildBeginCapture(cap)
      let value = try emitNode(child)
      builder.buildEndCapture(cap)
      // If the child node produced a custom capture value, e.g. the result of
      // a matcher, this should override the captured substring.
      if let value {
        builder.buildMove(value, into: cap)
      }
      // If there's a capture transform, apply it now.
      if let transform = transform {
        let fn = builder.makeTransformFunction { input, cap in
          // If it's a substring capture with no custom value, apply the
          // transform directly to the substring to avoid existential traffic.
          //
          // FIXME: separate out this code path. This is fragile,
          // slow, and these are clearly different constructs
          if let range = cap.range, cap.value == nil {
            return try transform(input[range])
          }

          let value = constructExistentialOutputComponent(
             from: input,
             component: cap.deconstructed,
             optionalCount: 0)
          return try transform(value)
        }
        builder.buildTransformCapture(cap, fn)
      }

    case let .nonCapturingGroup(kind, child):
      try emitNoncapturingGroup(kind.ast, child)

    case .conditional:
      throw Unsupported("Conditionals")

    case let .quantification(amt, kind, child):
      try emitQuantification(amt.ast, kind, child)

    case let .customCharacterClass(ccc):
      if ccc.containsDot {
        if !ccc.isInverted {
          emitDot()
        } else {
          throw Unsupported("Inverted any")
        }
      } else {
        try emitCustomCharacterClass(ccc)
      }

    case let .atom(a):
      try emitAtom(a)

    case let .quotedLiteral(s):
      emitQuotedLiteral(s)

    case let .convertedRegexLiteral(n, _):
      return try emitNode(n)

    case .absentFunction:
      throw Unsupported("absent function")
    case .consumer:
      throw Unsupported("consumer")

    case let .matcher(_, f):
      return emitMatcher(f)

    case .characterPredicate:
      throw Unsupported("character predicates")

    case .trivia, .empty:
      return nil
    }
    return nil
  }
}

extension DSLTree.Node {
  var guaranteesForwardProgress: Bool {
    switch self {
    case .orderedChoice(let children):
      return children.allSatisfy { $0.guaranteesForwardProgress }
    case .concatenation(let children):
      return children.contains(where: { $0.guaranteesForwardProgress })
    case .capture(_, _, let node, _):
      return node.guaranteesForwardProgress
    case .nonCapturingGroup(let kind, let child):
      switch kind.ast {
      case .lookahead, .negativeLookahead, .lookbehind, .negativeLookbehind:
        return false
      default: return child.guaranteesForwardProgress
      }
    case .atom(let atom):
      switch atom {
      case .changeMatchingOptions, .assertion: return false
      default: return true
      }
    case .trivia, .empty:
      return false
    case .quotedLiteral(let string):
      return !string.isEmpty
    case .convertedRegexLiteral(let node, _):
      return node.guaranteesForwardProgress
    case .consumer, .matcher:
      // Allow zero width consumers and matchers
     return false
    case .customCharacterClass:
      return true
    case .quantification(let amount, _, let child):
      let (atLeast, _) = amount.ast.bounds
      return atLeast ?? 0 > 0 && child.guaranteesForwardProgress
    default: return false
    }
  }

  /// If the given node can be wrapped in a .quantify instruction
  /// Currently only allows nodes that match a single grapheme
  func shouldDoFastQuant(_ opts: MatchingOptions) -> Bool {
    switch self {
    case .customCharacterClass(let ccc):
      // Only quantify ascii only character classes
      return ccc.asAsciiBitset(opts) != nil
    case .atom(let atom):
      switch atom {
      case .char(let c):
        // Only quantify the most common path -> Single scalar ascii values
        return c._singleScalarAsciiValue != nil
      case .dot, .any, .anyNonNewline:
        // Always quantify any/dot
        return true
      case .characterClass(let cc):
        // Only quantify if it consumes a single grapheme
        return cc.model.consumesSingleGrapheme
      default:
        return false
      }
    case .convertedRegexLiteral(let node, _):
      return node.shouldDoFastQuant(opts)
    case .nonCapturingGroup(let kind, let child):
      switch kind.ast {
      case .nonCapture:
        return child.shouldDoFastQuant(opts)
      default:
        return false
      }
    case .orderedChoice:
      // Future work: Could we support ordered choice by compacting our payload
      // representation and supporting an alternation of up to N supported nodes?
      return false
    default:
      return false
    }
  }
}
