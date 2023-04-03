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


// TODO: Place shared formatting and trace infrastructure here

protocol Traced {
  var isTracingEnabled: Bool { get }
}

protocol TracedProcessor: ProcessorProtocol, Traced {
  // Empty defaulted
  func formatCallStack() -> String // empty default
  func formatSavePoints() -> String // empty default
  func formatRegisters() -> String // empty default

  // Non-empty defaulted
  func formatTrace() -> String
  func formatInput() -> String
  func formatInstructionWindow(windowSize: Int) -> String
}

func lineNumber(_ i: Int) -> String {
  "[\(i)]"
}
func lineNumber(_ pc: InstructionAddress) -> String {
  lineNumber(pc.rawValue)
}

extension TracedProcessor where Registers: Collection{
  func formatRegisters() -> String {
    typealias E = ()
    if !registers.isEmpty {
      return "\(registers)\n"
    }
    return ""
  }
}

extension TracedProcessor {
  func printTrace() { print(formatTrace()) }

  func trace() {
    if isTracingEnabled { printTrace() }
  }

  // Helpers for the conformers
  func formatCallStack() -> String {
    if !callStack.isEmpty {
      return "call stack: \(callStack)\n"
    }
    return ""
  }

  func formatSavePoints() -> String {
    if !savePoints.isEmpty {
      var result = "save points:\n"
      for point in savePoints {
        result += "  \(point)\n"
      }
      return result
    }
    return ""
  }

  func formatRegisters() -> String {
     typealias E = ()
     if Registers.self == E.self {
       return ""
     }
     return "\(registers)\n"
  }

  func formatInput() -> String {
    let distanceFromStart = input.distance(
      from: input.startIndex,
      to: currentPosition)

    // Cut a reasonably sized substring from the input to print
    let start = input.index(
      currentPosition,
      offsetBy: -30,
      limitedBy: input.startIndex) ?? input.startIndex
    let end = input.index(
      currentPosition,
      offsetBy: 30,
      limitedBy: input.endIndex) ?? input.endIndex
    let input = input[start..<end]
    
    // String override for printing sub-character information.
    if !input.indices.contains(currentPosition) {
      // Format unicode scalars as:
      //     abcde\u{0301}e\u{0301}
      //     .....^~~~~~~~
      func _format<S: StringProtocol>(_ input: S) -> String {
        let currentPosition = currentPosition as! S.Index
        let matchedHighlightWidth = input.unicodeScalars
          .prefix(upTo: currentPosition).map {
            $0.isASCII ? 1 : 8
          }.reduce(0, +)
        let nextHighlightWidth =
          currentPosition == input.endIndex || input[currentPosition].isASCII
          ? 1 : 8
        return """
          input: \(input.unicodeScalars
                    .map { $0.escaped(asASCII: true).description }
                    .joined())
                 \(String(repeating: ".", count: matchedHighlightWidth))\
          ^\(String(repeating: "~", count: nextHighlightWidth - 1))
          position: \(distanceFromStart)
          """
      }
      if let string = input as? String {
        return _format(string)
      } else if let substring = input as? Substring {
        return _format(substring)
      }
    }
    let dist = input.distance(from: start, to: currentPosition)
    return """
      input: \(input)
             \(String(repeating: "~", count: dist))^
      position: \(distanceFromStart)
      """
  }

  func formatInstructionWindow(
    windowSize: Int = 12
  ) -> String {
    if isAcceptState { return "ACCEPT" }
    if isFailState { return "FAIL" }

    let lower = instructions.index(
      currentPC,
      offsetBy: -(windowSize/2),
      limitedBy: instructions.startIndex) ?? instructions.startIndex
    let upper = instructions.index(
      currentPC,
      offsetBy: 1+windowSize/2,
      limitedBy: instructions.endIndex) ?? instructions.endIndex

    var result = ""
    for idx in instructions[lower..<upper].indices {
      result += instructions.formatInstruction(
        idx, atCurrent: idx == currentPC, depth: 3)
      result += "\n"
    }
    return result
  }

  func formatTrace() -> String {
    var result = "\n--- cycle \(cycleCount) ---\n"
    result += formatCallStack()
    result += formatSavePoints()
    result += formatRegisters()
    result += formatInput()
    result += "\n"
    result += formatInstructionWindow()
    return result
  }

  func formatInstruction(
    _ pc: InstructionAddress,
    depth: Int = 5
  ) -> String {
    instructions.formatInstruction(
      pc, atCurrent: pc == currentPC, depth: depth)
  }
}

extension Collection where Element: InstructionProtocol, Index == InstructionAddress {
  func formatInstruction(
    _ pc: InstructionAddress,
    atCurrent: Bool,
    depth: Int
  ) -> String {
    func pcChain(
      _ pc: InstructionAddress,
      depth: Int,
      rec: Bool = false
    ) -> String {
      guard depth > 0 else { return "" }

      let inst = self[pc]
      var result = "\(lineNumber(pc)) \(inst)"

      if let argPC = inst.operandPC, depth > 1 {
        result += " | \(pcChain(argPC, depth: depth-1))"
      }
      return result
    }

    let inst = self[pc]
    let indent = atCurrent ? ">" : " "
    var result = """
      \(indent)\(lineNumber(pc)) \(inst)
      """

    if let argPC = inst.operandPC, depth > 0 {
      // TODO: consider pruning anything in the rendered
      // instruction window...
      //result += " // \(pcChain(argPC, depth: depth))"
      _ = argPC
      result += ""
    }
    return result
  }
}



