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


// Just a phantom-typed Int wrapper.
struct TypedInt<👻>: RawRepresentable, Hashable {
  var rawValue: Int

  init(rawValue: Int) {
    self.rawValue = rawValue
  }

  init(_ rawValue: Int) {
    self.init(rawValue: rawValue)
  }

  init(_ uint: UInt64) {
    assert(uint.leadingZeroBitCount > 0)
    self.init(Int(asserting: uint))
  }
}
extension TypedInt: Comparable {
  static func <(lhs: TypedInt, rhs: TypedInt) -> Bool {
    return lhs.rawValue < rhs.rawValue
  }
}
extension TypedInt: CustomStringConvertible {
  var description: String { return "#\(rawValue)" }
}
extension TypedInt: ExpressibleByIntegerLiteral {
  init(integerLiteral value: Int) {
    self.init(rawValue: value)
  }
}

protocol TypedIntProtocol {
  associatedtype 👻
}
extension TypedInt: TypedIntProtocol { }

// A placeholder type for when we must supply a type.
// When the phantom type appears, it says boo
enum _Boo {}

// Easier for clients to just have their own typealias
typealias TypedInt_ = TypedInt

// TODO: BinaryInteger, etc.
extension TypedInt {
  static func +(lhs: TypedInt, rhs: Int) -> TypedInt {
    return TypedInt(lhs.rawValue + rhs)
  }

  var bits: UInt64 {
    UInt64(asserting: self.rawValue)
  }
}

struct TypedSetVector<Element: Hashable, 👻> {
  typealias Idx = TypedInt<👻>

  // TODO: Replace with real set vector
  var lookup: Dictionary<Element, Idx> = [:]

  var stored: Array<Element> = []

  func load(_ idx: Idx) -> Element { stored[idx.rawValue] }

  @discardableResult
  mutating func store(_ e: Element) -> Idx {
    if let reg = lookup[e] { return reg }
    let reg = Idx(stored.count)
    stored.append(e)
    lookup[e] = reg
    return reg
  }

  var count: Int { stored.count }

  init() {}
}

// MARK: - Strongly typed int wrappers

/// A distance in the Input, e.g. `n` in consume(n)
typealias Distance = TypedInt<_Distance>
enum _Distance {}

/// An instruction address, i.e. the index into our instruction list
typealias InstructionAddress = TypedInt<_InstructionAddress>
enum _InstructionAddress {}

/// A position in the call stack, i.e. for save point restores
typealias CallStackAddress = TypedInt<_CallStackAddress>
enum _CallStackAddress {}

/// A position in a position stack, i.e. for NFA simulation
typealias PositionStackAddress = TypedInt<_PositionStackAddress>
enum _PositionStackAddress {}

/// A position in the save point stack, i.e. for backtracking
typealias SavePointStackAddress = TypedInt<_SavePointAddress>
enum _SavePointAddress {}


// MARK: - Registers

/// The register number for a stored element
///
/// NOTE: Currently just used for static data, but e.g. could be
/// used to save the most recently seen element satisfying some
/// property
typealias ElementRegister = TypedInt<_ElementRegister>
enum _ElementRegister {}

typealias SequenceRegister = TypedInt<_SequenceRegister>
enum _SequenceRegister {}

/// The register number for a stored boolean value
///
/// E.g. used for conditional branches
typealias BoolRegister = TypedInt<_BoolRegister>
enum _BoolRegister {}

/// The register number for a string (e.g. comment, failure reason)
typealias StringRegister = TypedInt<_StringRegister>
enum _StringRegister {}

/// Used for matching sets of ascii values via bitsets
typealias AsciiBitsetRegister = TypedInt<_AsciiBitsetRegister>
enum _AsciiBitsetRegister {}

/// Used for consume functions, e.g. character classes
typealias ConsumeFunctionRegister = TypedInt<_ConsumeFunctionRegister>
enum _ConsumeFunctionRegister {}

/// Used for capture transforms, etc
typealias TransformRegister = TypedInt<_TransformRegister>
enum _TransformRegister {}

/// Used for value-producing matchers
typealias MatcherRegister = TypedInt<_MatcherRegister>
enum _MatcherRegister {}

/// UNIMPLEMENTED
typealias IntRegister = TypedInt<_IntRegister>
enum _IntRegister {}

/// UNIMPLEMENTED
typealias FloatRegister = TypedInt<_FloatRegister>
enum _FloatRegister {}

/// UNIMPLEMENTED
///
/// NOTE: This, along with a position stack, might
/// serve NFA-simulation style execution models
typealias PositionRegister = TypedInt<_PositionRegister>
enum _PositionRegister {}

typealias ValueRegister = TypedInt<_ValueRegister>
enum _ValueRegister {}

typealias CaptureRegister = TypedInt<_CaptureRegister>
enum _CaptureRegister {}

/// UNIMPLEMENTED
typealias InstructionAddressRegister = TypedInt<_InstructionAddressRegister>
enum _InstructionAddressRegister {}

/// UNIMPLEMENTED
typealias CallStackAddressRegister = TypedInt<_CallStackAddressRegister>
enum _CallStackAddressRegister {}

/// UNIMPLEMENTED
typealias PositionStackAddressRegister = TypedInt<_PositionStackAddressRegister>
enum _PositionStackAddressRegister {}

/// UNIMPLEMENTED
typealias SavePointAddressRegister = TypedInt<_SavePointAddressRegister>
enum _SavePointAddressRegister {}

/// A numbered label
typealias LabelId = TypedInt<_LabelId>
enum _LabelId {}

/// A numbered function
typealias FunctionId = TypedInt<_FunctionId>
enum _FunctionId {}

/// A numbered capture
typealias CaptureId = TypedInt<_CaptureId>
enum _CaptureId {}


