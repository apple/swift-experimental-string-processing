
// TODO: Place shared formatting and trace infrastructure here

public protocol Traced {
  var enableTracing: Bool { get set }
}

public protocol TracedProcessor: ProcessorProtocol, Traced {
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
  public func formatRegisters() -> String {
    typealias E = ()
    if !registers.isEmpty {
      return "\(registers)\n"
    }
    return ""
  }
}

extension TracedProcessor {
  func printTrace() { print(formatTrace()) }

  public func trace() {
    if enableTracing { printTrace() }
  }

  // Helpers for the conformers
  public func formatCallStack() -> String {
    if !callStack.isEmpty {
      return "call stack: \(callStack)\n"
    }
    return ""
  }

  public func formatSavePoints() -> String {
    if !savePoints.isEmpty {
      return "save points: \(savePoints)\n"
    }
    return ""
  }

  public func formatRegisters() -> String {
     typealias E = ()
     if Registers.self == E.self {
       return ""
     }
     return "\(registers)\n"
   }
  public func formatInput() -> String{
    let dist = input.distance(from: input.startIndex, to: currentPosition)
    return """
      input: \(input)
             \(String(repeating: "~", count: dist))^
      """
  }

  public func formatInstructionWindow(
    windowSize: Int = 9
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

  public func formatTrace() -> String {
    var result = "\n--- cycle \(cycleCount) ---\n"
    result += formatCallStack()
    result += formatSavePoints()
    result += formatRegisters()
    result += formatInput()
    result += "\n"
    result += formatInstructionWindow()
    return result
  }

  public func formatInstruction(
    _ pc: InstructionAddress,
    depth: Int = 5
  ) -> String {
    instructions.formatInstruction(
      pc, atCurrent: pc == currentPC, depth: depth)
  }
}

extension Collection where Element: InstructionProtocol, Index == InstructionAddress {
  public func formatInstruction(
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
      result += " // \(pcChain(argPC, depth: depth))"
    }
    return result
  }
}



