import Util

extension Program where Element: Hashable {
  public struct Builder {
    var instructions = Array<Instruction>()

    var elements = TypedSetVector<Element, _ElementRegister>()
    var strings = TypedSetVector<String, _StringRegister>()

    // Map tokens to actual addresses
    var addressTokens = Array<InstructionAddress?>()
    var addressFixups = Array<(InstructionAddress, AddressToken)>()

    // Registers
    var nextBoolRegister = BoolRegister(0)

    public init() {}
  }
}

extension Program.Builder {
  public init<S: Sequence>(staticElements: S) where S.Element == Element {
    staticElements.forEach { elements.store($0) }
  }

  public mutating func buildNop(_ r: StringRegister? = nil) {
    instructions.append(.nop(r))
  }
  public mutating func buildNop(_ s: String) {
    buildNop(strings.store(s))
  }

  public mutating func buildBranch(to t: AddressToken) {
    instructions.append(.branch())
    fixup(to: t)
  }
  public mutating func buildCondBranch(
    _ condition: BoolRegister, to t: AddressToken
  ) {
    instructions.append(.condBranch(condition: condition))
    fixup(to: t)
  }

  public mutating func buildSave(_ t: AddressToken) {
    instructions.append(.save())
    fixup(to: t)
  }
  public mutating func buildSaveAddress(_ t: AddressToken) {
    instructions.append(.saveAddress())
    fixup(to: t)
  }

  public mutating func buildClear() {
    instructions.append(.clear())
  }
  public mutating func buildRestore() {
    instructions.append(.restore())
  }
  public mutating func buildFail() {
    instructions.append(.fail())
  }
  public mutating func buildCall(_ t: AddressToken) {
    instructions.append(.call())
    fixup(to: t)
  }
  public mutating func buildRet() {
    instructions.append(.ret())
  }

  public mutating func buildAbort(_ s: StringRegister? = nil) {
    instructions.append(.abort(s))
  }
  public mutating func buildAbort(_ s: String) {
    buildAbort(strings.store(s))
  }

  public mutating func buildConsume(_ n: Distance) {
    instructions.append(.consume(n))
  }

  public mutating func buildMatch(_ e: Element) {
    instructions.append(.match(elements.store(e)))
  }

  public mutating func buildAssert(_ e: Element, into c: BoolRegister) {
    instructions.append(.assertion(condition: c, elements.store(e)))
  }

  public mutating func buildAccept() {
    instructions.append(.accept())
  }

  public mutating func buildPrint(_ s: StringRegister) {
    instructions.append(.print(s))
  }

  public func assemble() -> Program {
    // Do a pass to map address tokens to addresses
    var instructions = instructions
    for (instAddr, tok) in addressFixups {
      instructions[instAddr.rawValue].operand.initializePayload(
        addressTokens[tok.rawValue]!
      )
    }

    var regInfo = Program.RegisterInfo()
    regInfo.elements = elements.count
    regInfo.strings = strings.count
    regInfo.bools = nextBoolRegister.rawValue

    return Program(
      instructions: InstructionList(instructions),
      staticElements: elements.stored,
      staticStrings: strings.stored,
      registerInfo: regInfo)
  }

  public mutating func reset() { self = Self() }
}

// Address-agnostic interfaces for label-like support
extension Program.Builder {
  public enum _AddressToken {}
  public typealias AddressToken = TypedInt<_AddressToken>

  public mutating func createAddress() -> AddressToken {
    defer { addressTokens.append(nil) }
    return AddressToken(addressTokens.count)
  }

  // Resolves the address token to the most recently added
  // instruction, updating prior and future address references
  public mutating func resolve(_ t: AddressToken) {
    assert(!instructions.isEmpty)
    assert(addressTokens[t.rawValue] == nil)

    addressTokens[t.rawValue] =
      InstructionAddress(instructions.count &- 1)
  }

  // Associate the most recently added instruction with
  // the provided token, ensuring it is fixed up during
  // assembly
  public mutating func fixup(to t: AddressToken) {
    assert(!instructions.isEmpty)
    addressFixups.append(
      (InstructionAddress(instructions.endIndex-1), t))
  }
}

// Register helpers
extension Program.Builder {
  public mutating func createRegister() -> BoolRegister {
    defer { nextBoolRegister.rawValue += 1 }
    return nextBoolRegister
  }
}

