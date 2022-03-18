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

typealias Program = MEProgram<String>

/// A concrete CU. Somehow will run the concrete logic and
/// feed stuff back to generic code
struct Controller {
  var pc: InstructionAddress

  mutating func step() {
    pc.rawValue += 1
  }
}

struct Processor<
  Input: BidirectionalCollection
> where Input.Element: Equatable { // maybe Hashable?
  typealias Element = Input.Element

  let input: Input
  let bounds: Range<Position>
  let matchMode: MatchMode
  var currentPosition: Position

  let instructions: InstructionList<Instruction>
  var controller: Controller

  var cycleCount = 0

  /// Our register file
  var registers: Registers

  // Used for back tracking
  var savePoints: [SavePoint] = []

  var callStack: [InstructionAddress] = []

  var state: State = .inProgress

  var isTracingEnabled: Bool

  var storedCaptures: Array<_StoredCapture>
}

extension Processor {
  typealias Position = Input.Index

  var start: Position { bounds.lowerBound }
  var end: Position { bounds.upperBound }
}

extension Processor {
  init(
    program: MEProgram<Input>,
    input: Input,
    bounds: Range<Position>,
    matchMode: MatchMode,
    isTracingEnabled: Bool
  ) {
    self.controller = Controller(pc: 0)
    self.instructions = program.instructions
    self.input = input
    self.bounds = bounds
    self.matchMode = matchMode
    self.isTracingEnabled = isTracingEnabled
    self.currentPosition = bounds.lowerBound

    self.registers = Registers(program, bounds.upperBound)
    self.storedCaptures = Array(
       repeating: .init(), count: program.registerInfo.captures)

    _checkInvariants()
  }

  func _checkInvariants() {
    assert(end <= input.endIndex)
    assert(start >= input.startIndex)
    assert(currentPosition >= start)
    assert(currentPosition <= end)
  }
}

extension Processor {
  var slice: Input.SubSequence {
    // TODO: Should we whole-scale switch to slices, or
    // does that depend on options for some anchors?
    input[bounds]
  }

  // Advance in our input
  //
  // Returns whether the advance succeeded. On failure, our
  // save point was restored
  mutating func consume(_ n: Distance) -> Bool {
    // Want Collection to provide this behavior...
    if input.distance(from: currentPosition, to: end) < n.rawValue {
      signalFailure()
      return false
    }
    currentPosition = input.index(currentPosition, offsetBy: n.rawValue)
    return true
  }

  mutating func advance(to nextIndex: Input.Index) {
    assert(nextIndex >= bounds.lowerBound)
    assert(nextIndex <= bounds.upperBound)
    assert(nextIndex > currentPosition)
    currentPosition = nextIndex
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

  mutating func match(_ e: Element) {
    guard let cur = load(), cur == e else {
      signalFailure()
      return
    }
    if consume(1) {
      controller.step()
    }
  }
  mutating func matchSeq<C: Collection>(
    _ seq: C
  ) where C.Element == Input.Element {
    let count = seq.count

    guard let inputSlice = load(count: count),
          seq.elementsEqual(inputSlice)
    else {
      signalFailure()
      return
    }
    guard consume(.init(count)) else {
      fatalError("unreachable")
    }
    controller.step()
  }

  mutating func signalFailure() {
    guard let (pc, pos, stackEnd, capEnds, intRegisters) =
            savePoints.popLast()?.destructure
    else {
      state = .fail
      return
    }
    // assert(stackEnd.rawValue <= callStack.count)
    assert(capEnds.count == storedCaptures.count)

    controller.pc = pc
    currentPosition = pos ?? currentPosition
    if stackEnd.rawValue <= callStack.count {
      callStack.removeLast(callStack.count - stackEnd.rawValue)
    }
    storedCaptures = capEnds
    registers.ints = intRegisters
  }

  mutating func tryAccept() {
    switch (currentPosition, matchMode) {
    // When reaching the end of the match bounds or when we are only doing a
    // prefix match, transition to accept.
    case (bounds.upperBound, _), (_, .partialFromFront):
      state = .accept

    // When we are doing a full match but did not reach the end of the match
    // bounds, backtrack if possible.
    case (_, .wholeString):
      signalFailure()
    }
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
    case .nop:
      if checkComments,
         let s = payload.optionalString
      {
        doPrint(registers[s])
      }
      controller.step()

    case .decrement:
      let (bool, int) = payload.pairedBoolInt
      let newValue = registers[int] - 1
      registers[bool] = newValue == 0
      registers[int] = newValue
      controller.step()

    case .moveImmediate:
      let (imm, reg) = payload.pairedImmediateInt
      let int = Int(asserting: imm)
      assert(int == imm)

      registers[reg] = int
      controller.step()

    case .movePosition:
      let reg = payload.position
      registers[reg] = currentPosition
      controller.step()

    case .branch:
      controller.pc = payload.addr

    case .condBranch:
      let (addr, cond) = payload.pairedAddrBool
      if registers[cond] {
        controller.pc = addr
      } else {
        controller.step()
      }

    case .condBranchZeroElseDecrement:
      let (addr, int) = payload.pairedAddrInt
      if registers[int] == 0 {
        controller.pc = addr
      } else {
        registers[int] -= 1
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
        fatalError("TODO: What should we do here?")
      }

    case .peek:
      fatalError()

    case .restore:
      signalFailure()

    case .push:
      fatalError()

    case .pop:
      fatalError()

    case .call:
      controller.step()
      callStack.append(controller.pc)
      controller.pc = payload.addr

    case .ret:
      // TODO: Should empty stack mean success?
      guard let r = callStack.popLast() else {
        tryAccept()
        return
      }
      controller.pc = r

    case .abort:
      // TODO: throw or otherwise propagate
      if let s = payload.optionalString {
        doPrint(registers[s])
      }
      state = .fail

    case .accept:
      tryAccept()

    case .fail:
      signalFailure()

    case .advance:
      if consume(payload.distance) {
        controller.step()
      }

    case .match:
      let reg = payload.element
      match(registers[reg])

    case .matchSequence:
      let reg = payload.sequence
      let seq = registers[reg]
      matchSeq(seq)

    case .matchSlice:
      let (lower, upper) = payload.pairedPosPos
      let range = registers[lower]..<registers[upper]
      let slice = input[range]
      matchSeq(slice)

    case .consumeBy:
      let reg = payload.consumer
      guard currentPosition < bounds.upperBound,
            let nextIndex = registers[reg](
              input, currentPosition..<bounds.upperBound)
      else {
        signalFailure()
        return
      }
      advance(to: nextIndex)
      controller.step()

    case .assertBy:
      let reg = payload.assertion
      let assertion = registers[reg]
      guard assertion(input, currentPosition, bounds) else {
        signalFailure()
        return
      }
      controller.step()

    case .matchBy:
      let (matcherReg, valReg) = payload.pairedMatcherValue
      let matcher = registers[matcherReg]
      guard let (nextIdx, val) = matcher(
        input, currentPosition, bounds
      ) else {
        signalFailure()
        return
      }
      registers[valReg] = val
      advance(to: nextIdx)
      controller.step()

    case .print:
      // TODO: Debug stream
      doPrint(registers[payload.string])

    case .assertion:
      let (element, cond) =
        payload.pairedElementBool
      let result: Bool
      if let cur = load(), cur == registers[element] {
        result = true
      } else {
        result = false
      }
      registers[cond] = result
      controller.step()

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
      guard let range = cap.latest else {
        signalFailure()
        return
      }
      matchSeq(input[range])

    case .beginCapture:
      let capNum = Int(
        asserting: payload.capture.rawValue)

       let sp = makeSavePoint(self.currentPC)
       storedCaptures[capNum].startCapture(
         currentPosition, initial: sp)
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

      guard let range = storedCaptures[capNum].latest else {
        fatalError(
          "Unreachable: transforming without a capture")
      }
      // FIXME: Pass input or the slice?
      guard let value = transform(input, range) else {
        signalFailure()
        return
      }
      storedCaptures[capNum].registerValue(value)

      controller.step()

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
