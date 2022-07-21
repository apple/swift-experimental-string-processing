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

@_implementationOnly import _RegexParser

extension Instruction {
  /// An instruction's payload packs operands and destination
  /// registers.
  ///
  /// A payload is 56 bits and its contents structurally depend
  /// on the specific instruction
  struct Payload: RawRepresentable {
    var rawValue: UInt64
    init(rawValue: UInt64) {
      assert(rawValue == rawValue & _payloadMask)
      self.rawValue = rawValue
      // TODO: post conditions
    }
  }
}

extension Instruction.Payload {
  // For modeling, perhaps tooling, but likely not for
  // execution
  private enum Kind {
    // TODO: We should choose operand ordering based on codegen
    //
    // For now, we do:
    //   Immediate < InstAddr < ConsumeFuncReg < ElementReg
    //   (compile)   (link)     (link)           (link)
    //
    //   ... < BoolReg < IntReg
    //
    // That is, optimization-time constant, link-time constant,
    // and variables

    case string(StringRegister)
    case sequence(SequenceRegister)
    case position(PositionRegister)
    case optionalString(StringRegister?)
    case int(IntRegister)
    case distance(Distance)
    case bool(BoolRegister)
    case element(ElementRegister)
    case consumer(ConsumeFunctionRegister)
    case bitset(AsciiBitsetRegister)
    case addr(InstructionAddress)
    case capture(CaptureRegister)

    case packedImmInt(Int, IntRegister)
    case packedAddrBool(InstructionAddress, BoolRegister)
    case packedAddrInt(InstructionAddress, IntRegister)
    case packedAddrAddr(InstructionAddress, InstructionAddress)
    case packedBoolInt(BoolRegister, IntRegister)
    case packedEltBool(ElementRegister, BoolRegister)
    case packedPosPos(PositionRegister, PositionRegister)
    case packedCapTran(CaptureRegister, TransformRegister)
    case packedMatchVal(MatcherRegister, ValueRegister)
    case packedValueCapture(ValueRegister, CaptureRegister)
  }
}

// MARK: - Payload getters

extension Instruction.Payload {
  /// A `nil` payload, for e.g. StringRegister?
  static var nilPayload: Self {
    self.init(rawValue: _payloadMask)
  }

  private init(_ r: UInt64) {
    self.init(rawValue: r)
  }
  private init<👻>(_ r: TypedInt<👻>) {
    self.init(r.bits)
  }
  private init<👻>(_ r: TypedInt<👻>?) {
    if let r = r {
      self.init(r)
    } else {
      self = .nilPayload
    }
  }

  // Two values packed together
  //
  // For now, we just use 16 bits, because if that's good enough
  // for 1990s Unicode it's good enough for us.
  //
  // TODO: but really, let's come up with something
  private var firstSplitMask: UInt64 { 0x0000_FFFF }
  private var secondSplitMask: UInt64 { 0xFFFF_0000 }

  private var split: (first: UInt64, second: UInt64) {
    assert(rawValue == ((firstSplitMask|secondSplitMask) & rawValue))

    // TODO: Which order is better?
    let first = rawValue & firstSplitMask
    let second = (rawValue & secondSplitMask) &>> 16
    return (first, second)
  }

  private init(_ a: UInt64, _ b: UInt64) {
    self.init(a | (b &<< 16))
    assert(a == a & firstSplitMask)
    assert(b == b & firstSplitMask)
  }
  private init<👻>(_ a: UInt64, _ b: TypedInt<👻>) {
    self.init(a, b.bits)
  }
  private init<👻, 👺>(_ a: TypedInt<👻>, _ b: TypedInt<👺>) {
    self.init(a.bits, b.bits)
  }

  private func interpret<👻>(
    as: TypedInt<👻>.Type = TypedInt<👻>.self
  ) -> TypedInt<👻> {
    // TODO: We'd like to use shadow bits to assert on kind
    return TypedInt(rawValue)
  }

  private func interpretPair<👻>(
    secondAs: TypedInt<👻>.Type = TypedInt<👻>.self
  ) -> (UInt64, TypedInt<👻>) {
    (split.first, TypedInt(split.second) )
  }
  private func interpretPair<👻, 👺>(
    firstAs: TypedInt<👻>.Type = TypedInt<👻>.self,
    secondAs: TypedInt<👺>.Type = TypedInt<👺>.self
  ) -> (TypedInt<👻>, TypedInt<👺>) {
    (TypedInt(split.first), TypedInt(split.second) )
  }

  // MARK: Single operand payloads

  init(string: StringRegister) {
    self.init(string)
  }
  var string: StringRegister {
    interpret()
  }
  
  init(scalar: Unicode.Scalar) {
    self.init(UInt64(scalar.value))
  }
  var scalar: Unicode.Scalar {
    return Unicode.Scalar(_value: UInt32(self.rawValue))
  }

  init(scalar: Unicode.Scalar, caseInsensitive: Bool, boundaryCheck: Bool) {
    let raw = UInt64(scalar.value)
      + (caseInsensitive ? 1 << 55: 0)
      + (boundaryCheck ? 1 << 54 : 0)
    self.init(raw)
  }
  var scalarPayload: (Unicode.Scalar, caseInsensitive: Bool, boundaryCheck: Bool) {
    let caseInsensitive = (self.rawValue >> 55) & 1 == 1
    let boundaryCheck = (self.rawValue >> 54) & 1 == 1
    let scalar = Unicode.Scalar(_value: UInt32(self.rawValue & 0xFFFF_FFFF))
    return (scalar, caseInsensitive: caseInsensitive, boundaryCheck: boundaryCheck)
  }

  init(sequence: SequenceRegister) {
    self.init(sequence)
  }
  var sequence: SequenceRegister {
    interpret()
  }

  init(optionalString: StringRegister?) {
    self.init(optionalString)
  }
  var optionalString: StringRegister? {
    interpret()
  }

  init(position: PositionRegister) {
    self.init(position)
  }
  var position: PositionRegister {
    interpret()
  }

  init(int: IntRegister) {
    self.init(int)
  }
  var int: IntRegister {
    interpret()
  }

  init(distance: Distance) {
    self.init(distance)
  }
  var distance: Distance {
    interpret()
  }

  init(bool: BoolRegister) {
    self.init(bool)
  }
  var bool: BoolRegister {
    interpret()
  }

  init(element: ElementRegister, isCaseInsensitive: Bool) {
    self.init(isCaseInsensitive ? 1 : 0, element)
  }
  var elementPayload: (isCaseInsensitive: Bool, ElementRegister) {
    let pair: (UInt64, ElementRegister) = interpretPair()
    return (isCaseInsensitive: pair.0 == 1, pair.1)
  }

  init(bitset: AsciiBitsetRegister, isScalar: Bool) {
    self.init(isScalar ? 1 : 0, bitset)
  }
  var bitsetPayload: (isScalar: Bool, AsciiBitsetRegister) {
    let pair: (UInt64, AsciiBitsetRegister) = interpretPair()
    return (isScalar: pair.0 == 1, pair.1)
  }

  init(_ cc: _CharacterClassModel.Representation, _ isInverted: Bool, _ isStrict: Bool, _ isScalar: Bool) {
    self.init(CharacterClassPayload(cc, isInverted, isStrict, isScalar).rawValue)
  }
  var characterClassPayload: CharacterClassPayload{
    return CharacterClassPayload(rawValue: rawValue & _payloadMask)
  }

  init(quantify payload: QuantifyPayload) {
    self.init(rawValue: payload.rawValue)
  }
  var quantify: QuantifyPayload {
    QuantifyPayload.init(rawValue: self.rawValue & _payloadMask)
  }
  
  init(consumer: ConsumeFunctionRegister) {
    self.init(consumer)
  }
  var consumer: ConsumeFunctionRegister {
    interpret()
  }

  init(assertion payload: AssertionPayload) {
    self.init(rawValue: payload.rawValue)
  }
  var assertion: AssertionPayload {
    AssertionPayload.init(rawValue: self.rawValue & _payloadMask)
  }

  init(addr: InstructionAddress) {
    self.init(addr)
  }
  var addr: InstructionAddress {
    interpret()
  }

  init(capture: CaptureRegister) {
    self.init(capture)
  }
  var capture: CaptureRegister {
    interpret()
  }


  // MARK: Packed operand payloads

  init(immediate: UInt64, int: IntRegister) {
    self.init(immediate, int)
  }
  var pairedImmediateInt: (UInt64, IntRegister) {
    interpretPair()
  }

  init(immediate: UInt64, bool: BoolRegister) {
    self.init(immediate, bool)
  }
  var pairedImmediateBool: (UInt64, BoolRegister) {
    interpretPair()
  }

  init(addr: InstructionAddress, bool: BoolRegister) {
    self.init(addr, bool)
  }
  var pairedAddrBool: (InstructionAddress, BoolRegister) {
    interpretPair()
  }

  init(addr: InstructionAddress, int: IntRegister) {
    self.init(addr, int)
  }
  var pairedAddrInt: (InstructionAddress, IntRegister) {
    interpretPair()
  }

  init(addr: InstructionAddress, addr2: InstructionAddress) {
    self.init(addr, addr2)
  }
  var pairedAddrAddr: (InstructionAddress, InstructionAddress) {
    interpretPair()
  }

  init(bool: BoolRegister, int: IntRegister) {
    self.init(bool, int)
  }
  var pairedBoolInt: (BoolRegister, IntRegister) {
    interpretPair()
  }

  init(element: ElementRegister, bool: BoolRegister) {
    self.init(element, bool)
  }
  var pairedElementBool: (ElementRegister, BoolRegister) {
    interpretPair()
  }

  init(addr: InstructionAddress, position: PositionRegister) {
    self.init(addr, position)
  }
  var pairedAddrPos: (InstructionAddress, PositionRegister) {
    interpretPair()
  }

  init(capture: CaptureRegister, transform: TransformRegister) {
    self.init(capture, transform)
  }
  var pairedCaptureTransform: (
    CaptureRegister, TransformRegister
  ) {
    interpretPair()
  }

  init(value: ValueRegister, capture: CaptureRegister) {
    self.init(value, capture)
  }
  var pairedValueCapture: (
    ValueRegister, CaptureRegister
  ) {
    interpretPair()
  }

  init(matcher: MatcherRegister, value: ValueRegister) {
    self.init(matcher, value)
  }
  var pairedMatcherValue: (
    MatcherRegister, ValueRegister
  ) {
    interpretPair()
  }
}

struct QuantifyPayload: RawRepresentable {
  let rawValue: UInt64
  
  enum PayloadType: UInt64 {
    case bitset = 0
    case asciiChar = 1
    case any = 2
    case builtin = 4
  }
  
  // Future work: optimize this layout -> payload type should be a fast switch
  // The top 8 bits are reserved for the opcode so we have 56 bits to work with
  // b55-b38 - Unused
  // b38-b35 - Payload type (one of 4 types, stored on 3 bits)
  // b35-b27 - minTrips (8 bit int)
  // b27-b18 - extraTrips (8 bit value, one bit for nil)
  // b18-b16 - Quantification type (one of three types)
  // b16-b0  - Payload value (depends on payload type)
  static let quantKindShift: UInt64   = 16
  static let extraTripsShift: UInt64  = 18
  static let minTripsShift: UInt64    = 27
  static let typeShift: UInt64        = 35
  static let maxStorableTrips: UInt64 = (1 << 8) - 1
  
  var quantKindMask: UInt64  { 3 }
  var extraTripsMask: UInt64 { 0x1FF }
  var minTripsMask: UInt64   { 0xFF }
  var typeMask: UInt64       { 7 }
  var payloadMask: UInt64    { 0xFF_FF }
  
  static func packInfoValues(
    _ kind: AST.Quantification.Kind,
    _ minTrips: Int,
    _ extraTrips: Int?,
    _ type: PayloadType
  ) -> UInt64 {
    let kindVal: UInt64
    switch kind {
    case .eager:
      kindVal = 0
    case .reluctant:
      kindVal = 1
    case .possessive:
      kindVal = 2
    }
    let extraTripsVal: UInt64 = extraTrips == nil ? 1 : UInt64(extraTrips!) << 1
    return (kindVal << QuantifyPayload.quantKindShift) +
    (extraTripsVal << QuantifyPayload.extraTripsShift) +
    (UInt64(minTrips) << QuantifyPayload.minTripsShift) +
    (type.rawValue << QuantifyPayload.typeShift)
  }
  
  init(rawValue: UInt64) {
    self.rawValue = rawValue
    assert(rawValue & _opcodeMask == 0)
  }
  
  init(
    bitset: AsciiBitsetRegister,
    _ kind: AST.Quantification.Kind,
    _ minTrips: Int,
    _ extraTrips: Int?
  ) {
    assert(bitset.bits <= _payloadMask)
    self.rawValue = bitset.bits
      + QuantifyPayload.packInfoValues(kind, minTrips, extraTrips, .bitset)
  }
  
  init(
    asciiChar: UInt8,
    _ kind: AST.Quantification.Kind,
    _ minTrips: Int,
    _ extraTrips: Int?
  ) {
    self.rawValue = UInt64(asciiChar)
      + QuantifyPayload.packInfoValues(kind, minTrips, extraTrips, .asciiChar)
  }
  
  init(
    matchesNewlines: Bool,
    _ kind: AST.Quantification.Kind,
    _ minTrips: Int,
    _ extraTrips: Int?
  ) {
    self.rawValue = (matchesNewlines ? 1 : 0)
      + QuantifyPayload.packInfoValues(kind, minTrips, extraTrips, .any)
  }
  
  init(
    builtin: _CharacterClassModel.Representation,
    _ isStrict: Bool,
    _ isInverted: Bool,
    _ kind: AST.Quantification.Kind,
    _ minTrips: Int,
    _ extraTrips: Int?
  ) {
    assert(builtin.rawValue < 0xFF)
    let packedModel = builtin.rawValue
      + (isInverted ? 1 << 9 : 0)
      + (isStrict ? 1 << 10 : 0)
    self.rawValue = packedModel
      + QuantifyPayload.packInfoValues(kind, minTrips, extraTrips, .builtin)
  }
  
  var type: PayloadType {
    PayloadType(rawValue: (self.rawValue >> QuantifyPayload.typeShift) & 7)!
  }
  
  var quantKind: AST.Quantification.Kind {
    switch (self.rawValue >> QuantifyPayload.quantKindShift) & quantKindMask {
    case 0: return .eager
    case 1: return .reluctant
    case 2: return .possessive
    default:
      fatalError("Unreachable")
    }
  }
  
  var minTrips: UInt64 {
    (self.rawValue >> QuantifyPayload.minTripsShift) & minTripsMask
  }
  
  var extraTrips: UInt64? {
    let val = (self.rawValue >> QuantifyPayload.extraTripsShift) & extraTripsMask
    if val == 1 {
      return nil
    } else {
      return val >> 1
    }
  }
  
  var bitset: AsciiBitsetRegister {
    TypedInt(self.rawValue & payloadMask)
  }
  
  var asciiChar: UInt8 {
    UInt8(asserting: self.rawValue & payloadMask)
  }
  
  var anyMatchesNewline: Bool {
    (self.rawValue & 1) == 1
  }

  var builtin: _CharacterClassModel.Representation {
    _CharacterClassModel.Representation(rawValue: self.rawValue & 0xFF)!
  }
  var builtinIsInverted: Bool {
    (self.rawValue >> 9) & 1 == 1
  }
  var builtinIsStrict: Bool {
    (self.rawValue >> 10) & 1 == 1
  }
}

struct CharacterClassPayload: RawRepresentable {
  let rawValue: UInt64
  // Layout:
  // Top three bits are isInverted, isStrict, isScalar
  // Lower 16 bits are _CCM.Representation
  static let invertedShift: UInt64 = 55
  static let strictShift: UInt64 = 54
  static let scalarShift: UInt64 = 53
  static let ccMask: UInt64 = 0xFF
  init(rawValue: UInt64) {
    assert(rawValue & _opcodeMask == 0)
    self.rawValue = rawValue
  }
  init(_ cc: _CharacterClassModel.Representation, _ isInverted: Bool, _ isStrict: Bool, _ isScalar: Bool) {
    let invertedBit = isInverted ? 1 << CharacterClassPayload.invertedShift : 0
    let strictBit = isStrict ? 1 << CharacterClassPayload.strictShift : 0
    let scalarBit = isScalar ? 1 << CharacterClassPayload.scalarShift : 0
    assert(cc.rawValue <= CharacterClassPayload.ccMask) //
    self.init(rawValue: cc.rawValue + UInt64(invertedBit) + UInt64(strictBit) + UInt64(scalarBit))
  }
  
  var isInverted: Bool {
    (self.rawValue >> CharacterClassPayload.invertedShift) & 1 == 1
  }
  var isStrict: Bool {
    (self.rawValue >> CharacterClassPayload.strictShift) & 1 == 1
  }
  var isScalar: Bool {
    (self.rawValue >> CharacterClassPayload.scalarShift) & 1 == 1
  }
  var cc: _CharacterClassModel.Representation {
    _CharacterClassModel.Representation.init(rawValue: self.rawValue & CharacterClassPayload.ccMask)!
  }
}
