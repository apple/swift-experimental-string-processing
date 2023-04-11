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

extension Processor: TracedProcessor {
  var isFailState: Bool { state == .fail }
  var isAcceptState: Bool { state == .accept }

  var currentPC: InstructionAddress { controller.pc }

  func formatSavePoints() -> String {
    if !savePoints.isEmpty {
      var result = "save points:\n"
      for point in savePoints {
        result += "  \(point.describe(in: input))\n"
      }
      return result
    }
    return ""
  }
}

extension Instruction: CustomStringConvertible {
  var description: String {
    switch opcode {
    case .advance:
      return "\(opcode) \(payload.distance)"
    case .assertBy:
      return "\(opcode) \(payload.assertion)"
    case .backreference:
      return "\(opcode) \(payload.capture.rawValue)"
    case .beginCapture:
      return "\(opcode) \(payload.capture.rawValue)"
    case .branch:
      return "\(opcode) \(payload.addr)"
    case .captureValue:
      let (val, cap) = payload.pairedValueCapture
      return "\(opcode) vals[\(val)] -> captures[\(cap)]"
    case .condBranchSamePosition:
      let (addr, pos) = payload.pairedAddrPos
      return "\(opcode) \(addr) pos[\(pos)]"
    case .condBranchZeroElseDecrement:
      let (addr, int) = payload.pairedAddrInt
      return "\(opcode) \(addr) int[\(int)]"
    case .consumeBy:
      return "\(opcode) consumer[\(payload.consumer)]"
    case .endCapture:
      return "\(opcode) \(payload.capture.rawValue)"
    case .match:
      let (isCaseInsensitive, reg) = payload.elementPayload
      if isCaseInsensitive {
        return "matchCaseInsensitive char[\(reg)]"
      } else {
        return "match char[\(reg)]"
      }
    case .matchBitset:
      let (isScalar, reg) = payload.bitsetPayload
      if isScalar {
        return "matchBitsetScalar bitset[\(reg)]"
      } else {
        return "matchBitset bitset[\(reg)]"
      }
    case .matchBuiltin:
      let payload = payload.characterClassPayload
      return "matchBuiltin \(payload.cc) (\(payload.isInverted))"
    case .matchBy:
      let (matcherReg, valReg) = payload.pairedMatcherValue
      return "\(opcode) match[\(matcherReg)] -> val[\(valReg)]"
    case .matchScalar:
      let (scalar, caseInsensitive, boundaryCheck) = payload.scalarPayload
      if caseInsensitive {
        return "matchScalarCaseInsensitive '\(scalar)' boundaryCheck: \(boundaryCheck)"
      } else {
        return "matchScalar '\(scalar)' boundaryCheck: \(boundaryCheck)"
      }
    case .moveCurrentPosition:
      let reg = payload.position
      return "\(opcode) -> pos[\(reg)]"
    case .moveImmediate:
      let (imm, reg) = payload.pairedImmediateInt
      return "\(opcode) \(imm) -> int[\(reg)]"
    case .quantify:
      let payload = payload.quantify
      return "\(opcode) \(payload.type) \(payload.minTrips) \(payload.extraTrips?.description ?? "unbounded" )"
    case .save, .saveAddress:
      let payload = payload.savePayload
      let resumeAddr = payload.addr
      if payload.hasID {
        return "\(opcode) \(resumeAddr) keepsCaptures? \(payload.keepsCaptures) id: \(payload.id)"
      }
      return "\(opcode) \(resumeAddr) keepsCaptures? \(payload.keepsCaptures)"
    case .splitSaving:
      let payload = payload.savePayload
      if payload.hasID {
        return "\(opcode) saving: \(payload.addr) (id: \(payload.id)) jumpingTo: \(payload.split)"
      }
      return "\(opcode) saving: \(payload.addr) jumpingTo: \(payload.split)"
    case .clearPossessiveQuantDummy:
      return "\(opcode) clearingIfLatestSavePointID == \(payload.saveID)"
    case .transformCapture:
      let (cap, trans) = payload.pairedCaptureTransform
      return "\(opcode) trans[\(trans)](\(cap))"
    default:
      return "\(opcode)"
    }
  }
}

extension Processor.SavePoint {
  func describe(in input: String) -> String {
    let posStr: String
    if let p = self.pos {
      posStr = "\(input.distance(from: input.startIndex, to: p))"
    } else {
      if rangeIsEmpty {
        posStr = "<none>"
      } else {
        let startStr = "\(input.distance(from: input.startIndex, to: rangeStart!))"
        let endStr = "\(input.distance(from: input.startIndex, to: rangeEnd!))"
        posStr = "\(startStr)...\(endStr)"
      }
    }
    let idStr: String
    if let id = self.id {
      idStr = ", id: \(id)"
    } else {
      idStr = ""
    }
    return """
      pc: \(self.pc), pos: \(posStr), stackEnd: \(stackEnd), keepsCaptures? \(self.captureEnds == nil)\(idStr)
      """
  }
}
