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


enum MatchMode {
  case wholeString
  case partialFromFront
}

/// A concrete CU. Somehow will run the concrete logic and
/// feed stuff back to generic code
struct Controller {
  var pc: InstructionAddress

  mutating func step() {
    pc.rawValue += 1
  }
}

struct Processor {
  typealias Input = String
  typealias Element = Input.Element

  /// The base collection of the subject to search.
  ///
  /// Taken together, `input` and `subjectBounds` define the actual subject
  /// of the search. `input` can be a "supersequence" of the subject, while
  /// `input[subjectBounds]` is the logical entity that is being searched.
  let input: Input

  /// The bounds of the logical subject in `input`.
  ///
  /// `subjectBounds` represents the bounds of the string or substring that a
  /// regex operation is invoked upon. Anchors like `^` and `.startOfSubject`
  /// always use `subjectBounds` as their reference points, instead of
  /// `input`'s boundaries or `searchBounds`.
  ///
  /// `subjectBounds` is always equal to or a subrange of
  /// `input.startIndex..<input.endIndex`.
  let subjectBounds: Range<Position>

  /// The bounds within the subject for an individual search.
  ///
  /// `searchBounds` is equal to `subjectBounds` in some cases, but can be a
  /// subrange when performing operations like searching for matches iteratively
  /// or calling `str.replacing(_:with:subrange:)`.
  ///
  /// Anchors like `^` and `.startOfSubject` use `subjectBounds` instead of
  /// `searchBounds`. The "start of matching" anchor `\G` uses `searchBounds`
  /// as its starting point.
  let searchBounds: Range<Position>

  let matchMode: MatchMode
  let instructions: InstructionList<Instruction>

  // MARK: Resettable state

  /// The current search position while processing.
  ///
  /// `currentPosition` must always be in the range `subjectBounds` or equal
  /// to `subjectBounds.upperBound`.
  var currentPosition: Position

  var controller: Controller

  var registers: Registers

  var savePoints: [SavePoint] = []

  var callStack: [InstructionAddress] = []

  var storedCaptures: Array<_StoredCapture>

  var wordIndexCache: Set<String.Index>? = nil
  var wordIndexMaxIndex: String.Index? = nil

  var state: State = .inProgress

  var failureReason: Error? = nil

  var metrics: ProcessorMetrics
}

extension Processor {
  typealias Position = Input.Index

  var start: Position { searchBounds.lowerBound }
  var end: Position { searchBounds.upperBound }
}

extension Processor {
  init(
    program: MEProgram,
    input: Input,
    subjectBounds: Range<Position>,
    searchBounds: Range<Position>,
    matchMode: MatchMode,
    isTracingEnabled: Bool,
    shouldMeasureMetrics: Bool
  ) {
    self.controller = Controller(pc: 0)
    self.instructions = program.instructions
    self.input = input
    self.subjectBounds = subjectBounds
    self.searchBounds = searchBounds
    self.matchMode = matchMode

    self.metrics = ProcessorMetrics(
      isTracingEnabled: isTracingEnabled,
      shouldMeasureMetrics: shouldMeasureMetrics)

    self.currentPosition = searchBounds.lowerBound

    // Initialize registers with end of search bounds
    self.registers = Registers(program, searchBounds.upperBound)
    self.storedCaptures = Array(
      repeating: .init(), count: program.registerInfo.captures)

    _checkInvariants()
  }

  mutating func reset(currentPosition: Position) {
    self.currentPosition = currentPosition

    self.controller = Controller(pc: 0)

    self.registers.reset(sentinel: searchBounds.upperBound)

    self.savePoints.removeAll(keepingCapacity: true)
    self.callStack.removeAll(keepingCapacity: true)

    for idx in storedCaptures.indices {
      storedCaptures[idx] = .init()
    }

    self.state = .inProgress
    self.failureReason = nil

    metrics.addReset()
    _checkInvariants()
  }

  func _checkInvariants() {
    assert(searchBounds.lowerBound >= subjectBounds.lowerBound)
    assert(searchBounds.upperBound <= subjectBounds.upperBound)
    assert(subjectBounds.lowerBound >= input.startIndex)
    assert(subjectBounds.upperBound <= input.endIndex)
    assert(currentPosition >= searchBounds.lowerBound)
    assert(currentPosition <= searchBounds.upperBound)
  }
}

extension Processor {
  func fetch() -> (Instruction.OpCode, Instruction.Payload) {
    instructions[controller.pc].destructure
  }

  var slice: Input.SubSequence {
    // TODO: Should we whole-scale switch to slices, or
    // does that depend on options for some anchors?
    input[searchBounds]
  }

  // Advance in our input
  //
  // Returns whether the advance succeeded. On failure, our
  // save point was restored
  mutating func consume(_ n: Distance) -> Bool {
    // TODO: needs benchmark coverage
    guard let idx = input.index(
      currentPosition, offsetBy: n.rawValue, limitedBy: end
    ) else {
      signalFailure()
      return false
    }
    currentPosition = idx
    return true
  }

  // Advances in unicode scalar view
  mutating func consumeScalar(_ n: Distance) -> Bool {
    // TODO: needs benchmark coverage
    guard let idx = input.unicodeScalars.index(
      currentPosition, offsetBy: n.rawValue, limitedBy: end
    ) else {
      signalFailure()
      return false
    }
    currentPosition = idx
    return true
  }

  /// Continue matching at the specified index.
  ///
  /// - Precondition: `bounds.contains(index) || index == bounds.upperBound`
  /// - Precondition: `index >= currentPosition`
  mutating func resume(at index: Input.Index) {
    assert(index >= searchBounds.lowerBound)
    assert(index <= searchBounds.upperBound)
    assert(index >= currentPosition)
    currentPosition = index
  }

  func doPrint(_ s: String) {
    var enablePrinting: Bool { false }
    if enablePrinting {
      print(s)
    }
  }

  func load() -> Element? {
    currentPosition < end ? input[currentPosition] : nil
  }

  // MARK: Match functions
  //
  // TODO: refactor these such that `cycle()` calls the corresponding String
  //       method directly, and all the step, signalFailure, and
  //       currentPosition logic is collected into a single place inside
  //       cycle().

  // Match against the current input element. Returns whether
  // it succeeded vs signaling an error.
  mutating func match(
    _ e: Element, isCaseInsensitive: Bool
  ) -> Bool {
    guard let next = input.match(
      e,
      at: currentPosition,
      limitedBy: end,
      isCaseInsensitive: isCaseInsensitive
    ) else {
      signalFailure()
      return false
    }
    currentPosition = next
    return true
  }

  // Match against the current input prefix. Returns whether
  // it succeeded vs signaling an error.
  mutating func matchSeq(
    _ seq: Substring,
    isScalarSemantics: Bool
  ) -> Bool  {
    guard let next = input.matchSeq(
      seq,
      at: currentPosition,
      limitedBy: end,
      isScalarSemantics: isScalarSemantics
    ) else {
      signalFailure()
      return false
    }

    currentPosition = next
    return true
  }

  mutating func matchScalar(
    _ s: Unicode.Scalar,
    boundaryCheck: Bool,
    isCaseInsensitive: Bool
  ) -> Bool {
    guard let next = input.matchScalar(
      s,
      at: currentPosition,
      limitedBy: end,
      boundaryCheck: boundaryCheck,
      isCaseInsensitive: isCaseInsensitive
    ) else {
      signalFailure()
      return false
    }
    currentPosition = next
    return true
  }

  // If we have a bitset we know that the CharacterClass only matches against
  // ascii characters, so check if the current input element is ascii then
  // check if it is set in the bitset
  mutating func matchBitset(
    _ bitset: DSLTree.CustomCharacterClass.AsciiBitset,
    isScalarSemantics: Bool
  ) -> Bool {
    guard let next = input.matchASCIIBitset(
      bitset,
      at: currentPosition,
      limitedBy: end,
      isScalarSemantics: isScalarSemantics
    ) else {
      signalFailure()
      return false
    }
    currentPosition = next
    return true
  }

  // Matches the next character/scalar if it is not a newline
  mutating func matchAnyNonNewline(
    isScalarSemantics: Bool
  ) -> Bool {
    guard let next = input.matchAnyNonNewline(
      at: currentPosition,
      limitedBy: end,
      isScalarSemantics: isScalarSemantics
    ) else {
      signalFailure()
      return false
    }
    currentPosition = next
    return true
  }

  mutating func signalFailure() {
    guard !savePoints.isEmpty else {
      state = .fail
      return
    }
    let (pc, pos, stackEnd, capEnds, intRegisters, posRegisters): (
      pc: InstructionAddress,
      pos: Position?,
      stackEnd: CallStackAddress,
      captureEnds: [_StoredCapture],
      intRegisters: [Int],
      PositionRegister: [Input.Index]
    )

    let idx = savePoints.index(before: savePoints.endIndex)

    // If we have a quantifier save point, move the next range position into
    // pos instead of removing it
    if savePoints[idx].isQuantified {
      savePoints[idx].takePositionFromQuantifiedRange(input)
      (pc, pos, stackEnd, capEnds, intRegisters, posRegisters) = savePoints[idx].destructure
    } else {
      (pc, pos, stackEnd, capEnds, intRegisters, posRegisters) = savePoints.removeLast().destructure
    }

    assert(stackEnd.rawValue <= callStack.count)
    assert(capEnds.count == storedCaptures.count)

    controller.pc = pc
    currentPosition = pos ?? currentPosition
    callStack.removeLast(callStack.count - stackEnd.rawValue)
    storedCaptures = capEnds
    registers.ints = intRegisters
    registers.positions = posRegisters

    metrics.addBacktrack()
  }

  mutating func abort(_ e: Error? = nil) {
    if let e = e {
      self.failureReason = e
    }
    self.state = .fail
  }

  mutating func tryAccept() {
    switch (currentPosition, matchMode) {
    // When reaching the end of the match bounds or when we are only doing a
    // prefix match, transition to accept.
    case (searchBounds.upperBound, _), (_, .partialFromFront):
      state = .accept

    // When we are doing a full match but did not reach the end of the match
    // bounds, backtrack if possible.
    case (_, .wholeString):
      signalFailure()
    }
  }

  mutating func clearThrough(_ address: InstructionAddress) {
    while let sp = savePoints.popLast() {
      if sp.pc == address {
        controller.step()
        return
      }
    }
    // TODO: What should we do here?
    fatalError("Invalid code: Tried to clear save points when empty")
  }

  mutating func cycle() {
    _checkInvariants()
    assert(state == .inProgress)

    startCycleMetrics()
    defer { endCycleMetrics() }

    let (opcode, payload) = fetch()
    switch opcode {
    case .invalid:
      fatalError("Invalid program")

    case .moveImmediate:
      let (imm, reg) = payload.pairedImmediateInt
      let int = Int(asserting: imm)
      assert(int == imm)

      registers[reg] = int
      controller.step()
    case .moveCurrentPosition:
      let reg = payload.position
      registers[reg] = currentPosition
      controller.step()
    case .branch:
      controller.pc = payload.addr

    case .condBranchZeroElseDecrement:
      let (addr, int) = payload.pairedAddrInt
      if registers[int] == 0 {
        controller.pc = addr
      } else {
        registers[int] -= 1
        controller.step()
      }
    case .condBranchSamePosition:
      let (addr, pos) = payload.pairedAddrPos
      if registers[pos] == currentPosition {
        controller.pc = addr
      } else {
        controller.step()
      }
    case .save:
      let resumeAddr = payload.addr
      let sp = makeSavePoint(resumingAt: resumeAddr)
      savePoints.append(sp)
      controller.step()

    case .saveAddress:
      let resumeAddr = payload.addr
      let sp = makeAddressOnlySavePoint(resumingAt: resumeAddr)
      savePoints.append(sp)
      controller.step()

    case .splitSaving:
      let (nextPC, resumeAddr) = payload.pairedAddrAddr
      let sp = makeSavePoint(resumingAt: resumeAddr)
      savePoints.append(sp)
      controller.pc = nextPC

    case .clear:
      if let _ = savePoints.popLast() {
        controller.step()
      } else {
        // TODO: What should we do here?
        fatalError("Invalid code: Tried to clear save points when empty")
      }

    case .clearThrough:
      clearThrough(payload.addr)

    case .accept:
      tryAccept()

    case .fail:
      signalFailure()

    case .advance:
      let (isScalar, distance) = payload.distance
      if isScalar {
        if consumeScalar(distance) {
          controller.step()
        }
      } else {
        if consume(distance) {
          controller.step()
        }
      }
    case .matchAnyNonNewline:
      if matchAnyNonNewline(isScalarSemantics: payload.isScalar) {
        controller.step()
      }
    case .match:
      let (isCaseInsensitive, reg) = payload.elementPayload
      if match(registers[reg], isCaseInsensitive: isCaseInsensitive) {
        controller.step()
      }

    case .matchScalar:
      let (scalar, caseInsensitive, boundaryCheck) = payload.scalarPayload
      if matchScalar(
        scalar,
        boundaryCheck: boundaryCheck,
        isCaseInsensitive: caseInsensitive
      ) {
        controller.step()
      }

    case .matchBitset:
      let (isScalar, reg) = payload.bitsetPayload
      let bitset = registers[reg]
      if matchBitset(bitset, isScalarSemantics: isScalar) {
        controller.step()
      }

    case .matchBuiltin:
      let payload = payload.characterClassPayload
      if matchBuiltinCC(
        payload.cc,
        isInverted: payload.isInverted,
        isStrictASCII: payload.isStrictASCII,
        isScalarSemantics: payload.isScalarSemantics
      ) {
        controller.step()
      }
    case .quantify:
      let quantPayload = payload.quantify
      let matched: Bool
      switch (quantPayload.quantKind, quantPayload.minTrips, quantPayload.maxExtraTrips) {
      case (.reluctant, _, _):
        assertionFailure(".reluctant is not supported by .quantify")
        return
      case (.eager, 0, nil):
        runEagerZeroOrMoreQuantify(quantPayload)
        matched = true
      case (.eager, 1, nil):
        matched = runEagerOneOrMoreQuantify(quantPayload)
      case (_, 0, 1):
        matched = runZeroOrOneQuantify(quantPayload)
      default:
        matched = runQuantify(quantPayload)
      }
      if matched {
        controller.step()
      }

    case .consumeBy:
      let reg = payload.consumer
      let consumer = registers[reg]
      guard currentPosition < searchBounds.upperBound,
            let nextIndex = consumer(input, currentPosition..<searchBounds.upperBound),
            nextIndex <= end
      else {
        signalFailure()
        return
      }
      resume(at: nextIndex)
      controller.step()

    case .assertBy:
      let payload = payload.assertion
      do {
        guard try builtinAssert(by: payload) else {
          signalFailure()
          return
        }
      } catch {
        abort(error)
        return
      }
      controller.step()

    case .matchBy:
      let (matcherReg, valReg) = payload.pairedMatcherValue
      let matcher = registers[matcherReg]
      do {
        guard let (nextIdx, val) = try matcher(
          input, currentPosition, searchBounds
        ), nextIdx <= end else {
          signalFailure()
          return
        }
        registers[valReg] = val
        resume(at: nextIdx)
        controller.step()
      } catch {
        abort(error)
        return
      }

    case .backreference:
      let (isScalarMode, capture) = payload.captureAndMode
      let capNum = Int(
        asserting: capture.rawValue)
      guard capNum < storedCaptures.count else {
        fatalError("Should this be an assert?")
      }
      // TODO:
      //   Should we assert it's not finished yet?
      //   What's the behavior there?
      let cap = storedCaptures[capNum]
      guard let range = cap.range else {
        signalFailure()
        return
      }
      if matchSeq(input[range], isScalarSemantics: isScalarMode) {
        controller.step()
      }

    case .beginCapture:
      let capNum = Int(
        asserting: payload.capture.rawValue)
      storedCaptures[capNum].startCapture(currentPosition)
      controller.step()

    case .endCapture:
      let capNum = Int(
        asserting: payload.capture.rawValue)
      storedCaptures[capNum].endCapture(currentPosition)
      controller.step()

    case .transformCapture:
      let (cap, trans) = payload.pairedCaptureTransform
      let transform = registers[trans]
      let capNum = Int(asserting: cap.rawValue)

      do {
        // FIXME: Pass input or the slice?
        guard let value = try transform(input, storedCaptures[capNum]) else {
          signalFailure()
          return
        }
        storedCaptures[capNum].registerValue(value)
        controller.step()
      } catch {
        abort(error)
        return
      }

    case .captureValue:
      let (val, cap) = payload.pairedValueCapture
      let value = registers[val]
      let capNum = Int(asserting: cap.rawValue)
      storedCaptures[capNum].registerValue(value)
      controller.step()
    }
  }
}

// MARK: String matchers
//
// TODO: Refactor into separate file, formalize patterns

extension String {

  func match(
    _ char: Character,
    at pos: Index,
    limitedBy end: String.Index,
    isCaseInsensitive: Bool
  ) -> Index? {
    // TODO: This can be greatly sped up with string internals
    // TODO: This is also very much quick-check-able
    guard let (stringChar, next) = characterAndEnd(at: pos, limitedBy: end)
    else { return nil }

    if isCaseInsensitive {
      guard stringChar.lowercased() == char.lowercased() else { return nil }
    } else {
      guard stringChar == char else { return nil }
    }

    return next
  }

  func matchSeq(
    _ seq: Substring,
    at pos: Index,
    limitedBy end: Index,
    isScalarSemantics: Bool
  ) -> Index? {
    // TODO: This can be greatly sped up with string internals
    // TODO: This is also very much quick-check-able
    var cur = pos

    if isScalarSemantics {
      for e in seq.unicodeScalars {
        guard cur < end, unicodeScalars[cur] == e else { return nil }
        self.unicodeScalars.formIndex(after: &cur)
      }
    } else {
      for e in seq {
        guard let (char, next) = characterAndEnd(at: cur, limitedBy: end),
              char == e
        else { return nil }
        cur = next
      }
    }

    guard cur <= end else { return nil }
    return cur
  }

  func matchScalar(
    _ scalar: Unicode.Scalar,
    at pos: Index,
    limitedBy end: String.Index,
    boundaryCheck: Bool,
    isCaseInsensitive: Bool
  ) -> Index? {
    // TODO: extremely quick-check-able
    // TODO: can be sped up with string internals
    guard pos < end else { return nil }
    let curScalar = unicodeScalars[pos]

    if isCaseInsensitive {
      guard curScalar.properties.lowercaseMapping == scalar.properties.lowercaseMapping
      else {
        return nil
      }
    } else {
      guard curScalar == scalar else { return nil }
    }

    let idx = unicodeScalars.index(after: pos)
    assert(idx <= end, "Input is a substring with a sub-scalar endIndex.")

    if boundaryCheck && !isOnGraphemeClusterBoundary(idx) {
      return nil
    }

    return idx
  }

  func matchASCIIBitset(
    _ bitset: DSLTree.CustomCharacterClass.AsciiBitset,
    at pos: Index,
    limitedBy end: Index,
    isScalarSemantics: Bool
  ) -> Index? {

    // FIXME: Inversion should be tracked and handled in only one place.
    // That is, we should probably store it as a bit in the instruction, so that
    // bitset matching and bitset inversion is bit-based rather that semantically
    // inverting the notion of a match or not. As-is, we need to track both
    // meanings in some code paths.
    let isInverted = bitset.isInverted

    guard let (asciiByte, isCRLF: isCRLF, next) = _quickASCIICharacter(
      at: pos,
      limitedBy: end,
      isScalarSemantics: isScalarSemantics
    ) else {
      if isScalarSemantics {
        guard pos < end else { return nil }
        guard bitset.matches(unicodeScalars[pos]) else { return nil }
        return unicodeScalars.index(after: pos)
      } else {
        guard let (char, next) = characterAndEnd(at: pos, limitedBy: end),
              bitset.matches(char) else { return nil }
        return next
      }
    }

    guard bitset.matches(asciiByte) else {
      // FIXME: check inversion here after refactored out of bitset
      return nil
    }

    // CR-LF should only match `[\r]` in scalar semantic mode or if inverted
    if isCRLF && !isScalarSemantics && !isInverted {
      return nil
    }

    return next
  }
}
