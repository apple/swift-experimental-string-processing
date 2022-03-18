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

import _MatchingEngine // For errors

extension MEProgram where Input.Element: Hashable {
  struct Builder {
    var instructions: [Instruction] = []

    var elements = TypedSetVector<Input.Element, _ElementRegister>()
    var sequences = TypedSetVector<[Input.Element], _SequenceRegister>()
    var strings = TypedSetVector<String, _StringRegister>()

    var consumeFunctions: [ConsumeFunction] = []
    var assertionFunctions: [AssertionFunction] = []
    var transformFunctions: [TransformFunction] = []
    var matcherFunctions: [MatcherFunction] = []

    // Map tokens to actual addresses
    var addressTokens: [InstructionAddress?] = [.init(0)]
    var addressFixups: [(InstructionAddress, AddressFixup)] = []

    // Registers
    var nextBoolRegister = BoolRegister(0)
    var nextIntRegister = IntRegister(0)
    var nextPositionRegister = PositionRegister(0)
    var nextCaptureRegister = CaptureRegister(0)
    var nextValueRegister = ValueRegister(0)

    // Special addresses or instructions
    var failAddressToken: AddressToken? = nil

    // TODO: Should we have better API for building this up
    // as we compile?
    var captureStructure: CaptureStructure = .empty

    // Symbolic reference resolution
    var unresolvedReferences: [ReferenceID: [InstructionAddress]] = [:]
    var referencedCaptureOffsets: [ReferenceID: Int] = [:]
    var captureCount: Int {
      // We currently deduce the capture count from the capture register number.
      nextCaptureRegister.rawValue
    }

    // Subpattern resolution
    var subpatternFunctionTable: [Int: AddressToken] = [:]
    var unresolvedSubpatterns: [Int: [InstructionAddress]] = [:]

    init() {}
  }
}

extension MEProgram.Builder {
  struct AddressFixup {
    var first: AddressToken
    var second: AddressToken? = nil

    init(_ a: AddressToken) { self.first = a }
    init(_ a: AddressToken, _ b: AddressToken) {
      self.first = a
      self.second = b
    }
  }
}

extension MEProgram.Builder {
  // TODO: We want a better strategy for fixups, leaving
  // the operand in a different form isn't great...

  init<S: Sequence>(staticElements: S) where S.Element == Input.Element {
    staticElements.forEach { elements.store($0) }
  }

  var lastInstructionAddress: InstructionAddress {
    .init(instructions.endIndex - 1)
  }

  mutating func buildNop(_ r: StringRegister? = nil) {
    instructions.append(.init(.nop, .init(optionalString: r)))
  }
  mutating func buildNop(_ s: String) {
    buildNop(strings.store(s))
  }

  mutating func buildDecrement(
    _ i: IntRegister, nowZero: BoolRegister
  ) {
    instructions.append(.init(
      .decrement, .init(bool: nowZero, int: i)))
  }

  mutating func buildMoveImmediate(
    _ value: UInt64, into: IntRegister
  ) {
    instructions.append(.init(
      .moveImmediate, .init(immediate: value, int: into)))
  }

  // TODO: generic
  mutating func buildMoveImmediate(
    _ value: Int, into: IntRegister
  ) {
    let uint = UInt64(asserting: value)
    buildMoveImmediate(uint, into: into)
  }

  mutating func buildMoveCurrentPosition(
    into: PositionRegister
  ) {
    instructions.append(.init(
      .movePosition, .init(position: into)))
  }

  mutating func buildBranch(to t: AddressToken) {
    instructions.append(.init(.branch))
    fixup(to: t)
  }
  mutating func buildCondBranch(
    _ condition: BoolRegister, to t: AddressToken
  ) {
    instructions.append(
      .init(.condBranch, .init(bool: condition)))
    fixup(to: t)
  }

  mutating func buildCondBranch(
    to t: AddressToken, ifZeroElseDecrement i: IntRegister
  ) {
    instructions.append(
      .init(.condBranchZeroElseDecrement, .init(int: i)))
    fixup(to: t)
  }

  mutating func buildSave(_ t: AddressToken) {
    instructions.append(.init(.save))
    fixup(to: t)
  }
  mutating func buildSaveAddress(_ t: AddressToken) {
    instructions.append(.init(.saveAddress))
    fixup(to: t)
  }
  mutating func buildSplit(
    to: AddressToken, saving: AddressToken
  ) {
    instructions.append(.init(.splitSaving))
    fixup(to: (to, saving))
  }

  mutating func buildClear() {
    instructions.append(.init(.clear))
  }
  mutating func buildRestore() {
    instructions.append(.init(.restore))
  }
  mutating func buildFail() {
    instructions.append(.init(.fail))
  }
  mutating func buildCall(_ t: AddressToken) {
    instructions.append(.init(.call))
    fixup(to: t)
  }
  mutating func buildCallSubpattern(_ index: Int) {
    instructions.append(.init(.call))
    unresolvedSubpatterns[index, default: []].append(lastInstructionAddress)
  }
  mutating func buildRet() {
    instructions.append(.init(.ret))
  }

  mutating func buildAbort(_ s: StringRegister? = nil) {
    instructions.append(.init(
      .abort, .init(optionalString: s)))
  }
  mutating func buildAbort(_ s: String) {
    buildAbort(strings.store(s))
  }

  mutating func buildAdvance(_ n: Distance) {
    instructions.append(.init(.advance, .init(distance: n)))
  }

  mutating func buildMatch(_ e: Input.Element) {
    instructions.append(.init(
      .match, .init(element: elements.store(e))))
  }

  mutating func buildMatchSequence<S: Sequence>(
    _ s: S
  ) where S.Element == Input.Element {
    instructions.append(.init(
      .matchSequence,
      .init(sequence: sequences.store(.init(s)))))
  }

  mutating func buildMatchSlice(
    lower: PositionRegister, upper: PositionRegister
  ) {
    instructions.append(.init(
      .matchSlice,
      .init(pos: lower, pos2: upper)))
  }

  mutating func buildConsume(
    by p: @escaping MEProgram.ConsumeFunction
  ) {
    instructions.append(.init(
      .consumeBy, .init(consumer: makeConsumeFunction(p))))
  }

  mutating func buildAssert(
    by p: @escaping MEProgram.AssertionFunction
  ) {
    instructions.append(.init(
      .assertBy, .init(assertion: makeAssertionFunction(p))))
  }

  mutating func buildAssert(
    _ e: Input.Element, into cond: BoolRegister
  ) {
    instructions.append(.init(.assertion, .init(
      element: elements.store(e), bool: cond)))
  }

  mutating func buildAccept() {
    instructions.append(.init(.accept))
  }

  mutating func buildPrint(_ s: StringRegister) {
    instructions.append(.init(.print, .init(string: s)))
  }

  mutating func buildBeginCapture(
    _ cap: CaptureRegister
  ) {
    instructions.append(
      .init(.beginCapture, .init(capture: cap)))
  }

  mutating func buildEndCapture(
    _ cap: CaptureRegister
  ) {
    instructions.append(
      .init(.endCapture, .init(capture: cap)))
  }

  mutating func buildTransformCapture(
    _ cap: CaptureRegister, _ trans: TransformRegister
  ) {
    instructions.append(.init(
      .transformCapture,
      .init(capture: cap, transform: trans)))
  }

  mutating func buildMatcher(
    _ fun: MatcherRegister, into reg: ValueRegister
  ) {
    instructions.append(.init(
      .matchBy,
      .init(matcher: fun, value: reg)))
  }

  mutating func buildMove(
    _ value: ValueRegister, into capture: CaptureRegister
  ) {
    instructions.append(.init(
      .captureValue,
      .init(value: value, capture: capture)))
  }

  mutating func buildBackreference(
    _ cap: CaptureRegister
  ) {
    instructions.append(
      .init(.backreference, .init(capture: cap)))
  }

  mutating func buildUnresolvedReference(id: ReferenceID) {
    buildBackreference(.init(0))
    unresolvedReferences[id, default: []].append(lastInstructionAddress)
  }

  // TODO: Mutating because of fail address fixup, drop when
  // that's removed
  mutating func assemble() throws -> MEProgram {
    try resolveReferences()

    // TODO: This will add a fail instruction at the end every
    // time it's assembled. Better to do to the local instruction
    // list copy, but that complicates logic. It's possible we
    // end up going a different route all-together eventually,
    // though.
    if let tok = failAddressToken {
      label(tok)
      buildFail()
    }

    // Do a pass to map address tokens to addresses
    var instructions = instructions
    for (instAddr, tok) in addressFixups {
      // FIXME: based on opcode, decide if we split...
      // Unfortunate...
      let inst = instructions[instAddr.rawValue]
      let addr = addressTokens[tok.first.rawValue]!
      let payload: Instruction.Payload

      switch inst.opcode {
      case .condBranch:
        payload = .init(addr: addr, bool: inst.payload.bool)

      case .condBranchZeroElseDecrement:
        payload = .init(addr: addr, int: inst.payload.int)

      case .branch, .save, .saveAddress, .call:
        payload = .init(addr: addr)

      case .splitSaving:
        guard let fix2 = tok.second else {
          throw Unreachable("TODO: reason")
        }
        let saving = addressTokens[fix2.rawValue]!
        payload = .init(addr: addr, addr2: saving)

      default: throw Unreachable("TODO: reason")

      }

      instructions[instAddr.rawValue] = .init(
        inst.opcode, payload)
    }

    var regInfo = MEProgram.RegisterInfo()
    regInfo.elements = elements.count
    regInfo.sequences = sequences.count
    regInfo.strings = strings.count
    regInfo.bools = nextBoolRegister.rawValue
    regInfo.ints = nextIntRegister.rawValue
    regInfo.positions = nextPositionRegister.rawValue
    regInfo.values = nextValueRegister.rawValue
    regInfo.consumeFunctions = consumeFunctions.count
    regInfo.assertionFunctions = assertionFunctions.count
    regInfo.transformFunctions = transformFunctions.count
    regInfo.matcherFunctions = matcherFunctions.count
    regInfo.captures = nextCaptureRegister.rawValue

    return MEProgram(
      instructions: InstructionList(instructions),
      staticElements: elements.stored,
      staticSequences: sequences.stored,
      staticStrings: strings.stored,
      staticConsumeFunctions: consumeFunctions,
      staticAssertionFunctions: assertionFunctions,
      staticTransformFunctions: transformFunctions,
      staticMatcherFunctions: matcherFunctions,
      registerInfo: regInfo,
      captureStructure: captureStructure,
      referencedCaptureOffsets: referencedCaptureOffsets)
  }

  mutating func reset() { self = Self() }
}

// Address-agnostic interfaces for label-like support
extension MEProgram.Builder {
  enum _AddressToken {}
  typealias AddressToken = TypedInt<_AddressToken>

  mutating func makeAddress() -> AddressToken {
    defer { addressTokens.append(nil) }
    return AddressToken(addressTokens.count)
  }

  mutating func makeSubpatternAddress(
    _ cap: CaptureRegister
  ) -> AddressToken {
    let addr = makeAddress()
    let preexistingValue = subpatternFunctionTable.updateValue(
      addr, forKey: cap.rawValue)
    assert(preexistingValue == nil)
    return addr
  }

  var entryAddress: AddressToken {
    AddressToken(rawValue: 0)
  }

  func subpatternAddress(forCaptureOffset captureOffset: Int) -> AddressToken {
    if captureOffset == 0 {
      return entryAddress
    }
    guard let addr = subpatternFunctionTable[captureOffset] else {
      // FIXME: Should we create a variant of `buildCall` that takes a
      // subpattern offset?
      fatalError("FIXME: Forward-referencing a subpattern not supported")
    }
    return addr
  }

  // Resolves the address token to the most recently added
  // instruction, updating prior and future address references
  mutating func resolve(_ t: AddressToken) {
    assert(!instructions.isEmpty)

    addressTokens[t.rawValue] =
      InstructionAddress(instructions.count &- 1)
  }

  // Resolves the address token to the next instruction (one past the most
  // recently added one), updating prior and future address references.
  mutating func label(_ t: AddressToken) {
    addressTokens[t.rawValue] =
      InstructionAddress(instructions.count)
  }

  // Associate the most recently added instruction with
  // the provided token, ensuring it is fixed up during
  // assembly
  mutating func fixup(to t: AddressToken) {
    assert(!instructions.isEmpty)
    addressFixups.append(
      (InstructionAddress(instructions.endIndex-1), .init(t)))
  }

  // Associate the most recently added instruction with
  // the provided tokens, ensuring it is fixed up during
  // assembly
  mutating func fixup(
    to ts: (AddressToken, AddressToken)
  ) {
    assert(!instructions.isEmpty)
    addressFixups.append((
      InstructionAddress(instructions.endIndex-1),
      .init(ts.0, ts.1)))
  }

  // Push an "empty" save point which will, upon restore, just restore from
  // the next save point. Currently, this is modelled by a branch to a "fail"
  // instruction, which the builder will ensure exists for us.
  //
  // This is useful for possessive quantification that needs some initial save
  // point to "ratchet" upon a successful match.
  mutating func pushEmptySavePoint() {
    if failAddressToken == nil {
      failAddressToken = makeAddress()
    }
    buildSaveAddress(failAddressToken!)
  }

}

// Reference and subpattern resolution helpers
fileprivate extension MEProgram.Builder {
  mutating func resolveReferences() throws {
    for (id, uses) in unresolvedReferences {
      guard let offset = referencedCaptureOffsets[id] else {
        throw RegexCompilationError.uncapturedReference
      }
      for use in uses {
        instructions[use.rawValue] =
          Instruction(.backreference, .init(capture: .init(offset)))
      }
    }
  }

  mutating func resolveSubpatterns() throws {
    for (offset, calls) in unresolvedSubpatterns {
      let addr = subpatternAddress(forCaptureOffset: offset)
      for call in calls {
        addressFixups.append((call, AddressFixup(addr)))
      }
    }
  }
}

// Register helpers
extension MEProgram.Builder {
  mutating func makeCapture(id: ReferenceID?) -> CaptureRegister {
    defer { nextCaptureRegister.rawValue += 1 }
    // Register the capture for later lookup via symbolic references.
    if let id = id {
      let preexistingValue = referencedCaptureOffsets.updateValue(
        captureCount, forKey: id)
      assert(preexistingValue == nil)
    }
    return nextCaptureRegister
  }

  mutating func makeBoolRegister() -> BoolRegister {
    defer { nextBoolRegister.rawValue += 1 }
    return nextBoolRegister
  }
  mutating func makeIntRegister() -> IntRegister {
    defer { nextIntRegister.rawValue += 1 }
    return nextIntRegister
  }
  mutating func makePositionRegister() -> PositionRegister {
    defer { nextPositionRegister.rawValue += 1 }
    return nextPositionRegister
  }
  mutating func makeValueRegister() -> ValueRegister {
    defer { nextValueRegister.rawValue += 1 }
    return nextValueRegister
  }

  // Allocate and initialize a register
  mutating func makeIntRegister(
    initialValue: Int
  ) -> IntRegister {
    let r = makeIntRegister()
    self.buildMoveImmediate(initialValue, into: r)
    return r
  }

  // Allocate and initialize a register
  mutating func makePositionRegister(
    initializingWithCurrentPosition: ()
  ) -> PositionRegister {
    let r = makePositionRegister()
    self.buildMoveCurrentPosition(into: r)
    return r
  }

  // 'kill' or release allocated registers
  mutating func kill(_ r: IntRegister) {
    // TODO: Release/reuse registers, for now nop makes
    // reading the code easier
    buildNop("kill \(r)")
  }
  mutating func kill(_ r: BoolRegister) {
    // TODO: Release/reuse registers, for now nop makes
    // reading the code easier
    buildNop("kill \(r)")
  }
  mutating func kill(_ r: PositionRegister) {
    // TODO: Release/reuse registers, for now nop makes
    // reading the code easier
    buildNop("kill \(r)")
  }

  // TODO: A register-mapping helper struct, which could release
  // registers without monotonicity required

  mutating func makeConsumeFunction(
    _ f: @escaping MEProgram.ConsumeFunction
  ) -> ConsumeFunctionRegister {
    defer { consumeFunctions.append(f) }
    return ConsumeFunctionRegister(consumeFunctions.count)
  }
  mutating func makeAssertionFunction(
    _ f: @escaping MEProgram.AssertionFunction
  ) -> AssertionFunctionRegister {
    defer { assertionFunctions.append(f) }
    return AssertionFunctionRegister(assertionFunctions.count)
  }
  mutating func makeTransformFunction(
    _ f: @escaping MEProgram.TransformFunction
  ) -> TransformRegister {
    defer { transformFunctions.append(f) }
    return TransformRegister(transformFunctions.count)
  }
  mutating func makeMatcherFunction(
    _ f: @escaping MEProgram.MatcherFunction
  ) -> MatcherRegister {
    defer { matcherFunctions.append(f) }
    return MatcherRegister(matcherFunctions.count)
  }
}

