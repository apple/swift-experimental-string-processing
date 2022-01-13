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

extension Processor {

  // TODO: What all do we want to save? Configurable?
  // TODO: Do we need to save any registers?
  // TODO: Is this the right place to do function stack unwinding?
  struct SavePoint {
    var pc: InstructionAddress
    var pos: Position?

    // The end of the call stack, so we can slice it off
    // when failing inside a call.
    //
    // NOTE: Alternatively, also place return addresses on the
    // save point stack
    var stackEnd: CallStackAddress

    // FIXME: Save minimal info (e.g. stack position and
    // perhaps current start)
    var captureEnds: [_StoredCapture]

    var destructure: (
      pc: InstructionAddress,
      pos: Position?,
      stackEnd: CallStackAddress,
      captureEnds: [_StoredCapture]
    ) {
      (pc, pos, stackEnd, captureEnds)
    }
  }

  func makeSavePoint(
    _ pc: InstructionAddress,
    addressOnly: Bool = false
  ) -> SavePoint {
    SavePoint(
      pc: pc,
      pos: addressOnly ? nil : currentPosition,
      stackEnd: .init(callStack.count),
      captureEnds: storedCaptures)
  }
}


