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

  // MARK: Metrics, debugging, etc.
  var cycleCount = 0
  var isTracingEnabled: Bool
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
    isTracingEnabled: Bool
  ) {
    self.controller = Controller(pc: 0)
    self.instructions = program.instructions
    self.input = input
    self.subjectBounds = subjectBounds
    self.searchBounds = searchBounds
    self.matchMode = matchMode
    self.isTracingEnabled = isTracingEnabled
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
  var slice: Input.SubSequence {
    // TODO: Should we whole-scale switch to slices, or
    // does that depend on options for some anchors?
    input[searchBounds]
  }

  // Advance in our input, without any checks or failure signalling
  mutating func _uncheckedForcedConsumeOne() {
    assert(currentPosition != end)
    input.formIndex(after: &currentPosition)
  }

  // Advance in our input
  //
  // Returns whether the advance succeeded. On failure, our
  // save point was restored
  mutating func consume(_ n: Distance) -> Bool {
    guard let idx = input.index(
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
  func load(count: Int) -> Input.SubSequence? {
    let slice = self.slice[currentPosition...].prefix(count)
    guard slice.count == count else { return nil }
    return slice
  }

  // Match against the current input element. Returns whether
  // it succeeded vs signaling an error.
  mutating func match(_ e: Element) -> Bool {
    guard let cur = load(), cur == e else {
      signalFailure()
      return false
    }
    _uncheckedForcedConsumeOne()
    return true
  }

  mutating func matchCaseInsensitive(_ e: Element) -> Bool {
    guard let cur = load(), cur.lowercased() == e.lowercased() else {
      signalFailure()
      return false
    }
    _uncheckedForcedConsumeOne()
    return true
  }

  // Match against the current input prefix. Returns whether
  // it succeeded vs signaling an error.
  mutating func matchSeq<C: Collection>(
    _ seq: C
  ) -> Bool where C.Element == Input.Element {
    for e in seq {
      guard match(e) else { return false }
    }
    return true
  }

  func loadScalar() -> Unicode.Scalar? {
    currentPosition < end ? input.unicodeScalars[currentPosition] : nil
  }
  
  func _doMatchScalar(_ s: Unicode.Scalar, _ boundaryCheck: Bool) -> Input.Index? {
    if s == loadScalar(),
       let idx = input.unicodeScalars.index(
        currentPosition,
        offsetBy: 1,
        limitedBy: end),
       (!boundaryCheck || input.isOnGraphemeClusterBoundary(idx)) {
      return idx
    } else {
      return nil
    }
  }
  
  mutating func matchScalar(_ s: Unicode.Scalar, boundaryCheck: Bool) -> Bool {
    guard let next = _doMatchScalar(s, boundaryCheck) else {
      signalFailure()
      return false
    }
    currentPosition = next
    return true
  }

  mutating func matchScalarCaseInsensitive(
    _ s: Unicode.Scalar,
    boundaryCheck: Bool
  ) -> Bool {
    guard let curScalar = loadScalar(),
          s.properties.lowercaseMapping == curScalar.properties.lowercaseMapping,
          let idx = input.unicodeScalars.index(
            currentPosition,
            offsetBy: 1,
            limitedBy: end),
          (!boundaryCheck || input.isOnGraphemeClusterBoundary(idx))
    else {
      signalFailure()
      return false
    }
    currentPosition = idx
    return true
  }

  func _doMatchBitset(_ bitset: DSLTree.CustomCharacterClass.AsciiBitset) -> Input.Index? {
    if let cur = load(), bitset.matches(char: cur) {
      return input.index(after: currentPosition)
    } else {
      return nil
    }
  }

  // If we have a bitset we know that the CharacterClass only matches against
  // ascii characters, so check if the current input element is ascii then
  // check if it is set in the bitset
  mutating func matchBitset(
    _ bitset: DSLTree.CustomCharacterClass.AsciiBitset
  ) -> Bool {
    guard let next = _doMatchBitset(bitset) else {
      signalFailure()
      return false
    }
    currentPosition = next
    return true
  }

  // Equivalent of matchBitset but emitted when in unicode scalar semantic mode
  mutating func matchBitsetScalar(
    _ bitset: DSLTree.CustomCharacterClass.AsciiBitset
  ) -> Bool {
    guard let curScalar = loadScalar(),
          bitset.matches(scalar: curScalar),
          let idx = input.unicodeScalars.index(currentPosition, offsetBy: 1, limitedBy: end) else {
      signalFailure()
      return false
    }
    currentPosition = idx
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
    // If we have a quantifier save point, move the next range position into pos
    if !savePoints[idx].rangeIsEmpty {
      savePoints[idx].takePositionFromRange(input)
    }
    // If we have a normal save point or an empty quantifier save point, remove it
    if savePoints[idx].rangeIsEmpty {
      (pc, pos, stackEnd, capEnds, intRegisters, posRegisters) = savePoints.removeLast().destructure
    } else {
      (pc, pos, stackEnd, capEnds, intRegisters, posRegisters) = savePoints[idx].destructure
    }

    assert(stackEnd.rawValue <= callStack.count)
    assert(capEnds.count == storedCaptures.count)

    controller.pc = pc
    currentPosition = pos ?? currentPosition
    callStack.removeLast(callStack.count - stackEnd.rawValue)
    storedCaptures = capEnds
    registers.ints = intRegisters
    registers.positions = posRegisters
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
    if cycleCount == 0 { trace() }
    defer {
      cycleCount += 1
      trace()
      _checkInvariants()
    }
    let (opcode, payload) = fetch().destructure
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
      let sp = makeSavePoint(resumeAddr)
      savePoints.append(sp)
      controller.step()

    case .saveAddress:
      let resumeAddr = payload.addr
      let sp = makeSavePoint(resumeAddr, addressOnly: true)
      savePoints.append(sp)
      controller.step()

    case .splitSaving:
      let (nextPC, resumeAddr) = payload.pairedAddrAddr
      let sp = makeSavePoint(resumeAddr)
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
      if consume(payload.distance) {
        controller.step()
      }

    case .match:
      let (isCaseInsensitive, reg) = payload.elementPayload
      if isCaseInsensitive {
        if matchCaseInsensitive(registers[reg]) {
          controller.step()
        }
      } else {
        if match(registers[reg]) {
          controller.step()
        }
      }

    case .matchScalar:
      let (scalar, caseInsensitive, boundaryCheck) = payload.scalarPayload
      if caseInsensitive {
        if matchScalarCaseInsensitive(scalar, boundaryCheck: boundaryCheck) {
          controller.step()
        }
      } else {
        if matchScalar(scalar, boundaryCheck: boundaryCheck) {
          controller.step()
        }
      }

    case .matchBitset:
      let (isScalar, reg) = payload.bitsetPayload
      let bitset = registers[reg]
      if isScalar {
        if matchBitsetScalar(bitset) {
          controller.step()
        }
      } else {
        if matchBitset(bitset) {
          controller.step()
        }
      }

    case .matchBuiltin:
      let payload = payload.characterClassPayload
      if payload.isScalar {
        if matchBuiltinScalar(payload.cc, payload.isInverted, payload.isStrict) {
          controller.step()
        }
      } else {
        if matchBuiltin(payload.cc, payload.isInverted, payload.isStrict) {
          controller.step()
        }
      }
    case .quantify:
      let quantPayload = payload.quantify
      let matched: Bool
      switch (quantPayload.quantKind, quantPayload.minTrips, quantPayload.extraTrips) {
      case (.eager, 0, nil):
        matched = runEagerZeroOrMoreQuantify(quantPayload)
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
      guard currentPosition < searchBounds.upperBound,
            let nextIndex = registers[reg](
              input, currentPosition..<searchBounds.upperBound)
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
        ) else {
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
      let capNum = Int(
        asserting: payload.capture.rawValue)
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
      if matchSeq(input[range]) {
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
      let sp = makeSavePoint(self.currentPC)
      storedCaptures[capNum].registerValue(
        value, overwriteInitial: sp)
      controller.step()
    }
  }
}
