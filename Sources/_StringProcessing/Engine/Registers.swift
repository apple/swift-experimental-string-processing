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

struct SentinelValue: Hashable, CustomStringConvertible {
  var description: String { "<value sentinel>" }
}

extension Processor {
  /// Our register file
  struct Registers {

    // MARK: static / read-only, non-resettable

    // Verbatim elements to compare against
    var elements: [Element]

    // Verbatim sequences to compare against
    //
    // TODO: Degenericize Processor and store Strings
    var sequences: [[Element]] = []
    
    var bitsets: [DSLTree.CustomCharacterClass.AsciiBitset]

    var consumeFunctions: [MEProgram.ConsumeFunction]

    // Captured-value constructors
    var transformFunctions: [MEProgram.TransformFunction]

    // Value-constructing matchers
    var matcherFunctions: [MEProgram.MatcherFunction]

    // MARK: writeable, resettable

    // currently, useful for range-based quantification
    var ints: [Int]

    var values: [Any]

    var positions: [Input.Index]
  }
}

extension Processor.Registers {
  typealias Input = String

  subscript(_ i: SequenceRegister) -> [Input.Element] {
    sequences[i.rawValue]
  }
  subscript(_ i: IntRegister) -> Int {
    get { ints[i.rawValue] }
    set { ints[i.rawValue] = newValue }
  }
  subscript(_ i: ValueRegister) -> Any {
    get { values[i.rawValue] }
    set {
      values[i.rawValue] = newValue
    }
  }
  subscript(_ i: PositionRegister) -> Input.Index {
    get { positions[i.rawValue] }
    set {
      positions[i.rawValue] = newValue
    }
  }
  subscript(_ i: ElementRegister) -> Input.Element {
    elements[i.rawValue]
  }
  subscript(
    _ i: AsciiBitsetRegister
  ) -> DSLTree.CustomCharacterClass.AsciiBitset {
    bitsets[i.rawValue]
  }
  subscript(_ i: ConsumeFunctionRegister) -> MEProgram.ConsumeFunction {
    consumeFunctions[i.rawValue]
  }
  subscript(_ i: TransformRegister) -> MEProgram.TransformFunction {
    transformFunctions[i.rawValue]
  }
  subscript(_ i: MatcherRegister) -> MEProgram.MatcherFunction {
    matcherFunctions[i.rawValue]
  }
}

extension Processor.Registers {
  static let sentinelIndex = "".startIndex

  init(
    _ program: MEProgram,
    _ sentinel: String.Index
  ) {
    let info = program.registerInfo

    self.elements = program.staticElements
    assert(elements.count == info.elements)

    self.sequences = program.staticSequences
    assert(sequences.count == info.sequences)

    self.bitsets = program.staticBitsets
    assert(bitsets.count == info.bitsets)

    self.consumeFunctions = program.staticConsumeFunctions
    assert(consumeFunctions.count == info.consumeFunctions)

    self.transformFunctions = program.staticTransformFunctions
    assert(transformFunctions.count == info.transformFunctions)

    self.matcherFunctions = program.staticMatcherFunctions
    assert(matcherFunctions.count == info.matcherFunctions)

    self.ints = Array(repeating: 0, count: info.ints)

    self.values = Array(
      repeating: SentinelValue(), count: info.values)
    self.positions = Array(
      repeating: Processor.Registers.sentinelIndex,
      count: info.positions)
  }

  mutating func reset(sentinel: Input.Index) {
    self.ints._setAll(to: 0)
    self.values._setAll(to: SentinelValue())
    self.positions._setAll(to: Processor.Registers.sentinelIndex)
  }
}

// TODO: Productize into general algorithm
extension MutableCollection {
  mutating func _setAll(to e: Element) {
    for idx in self.indices {
      self[idx] = e
    }
  }
}

extension MEProgram {
  struct RegisterInfo {
    var elements = 0
    var sequences = 0
    var bools = 0
    var strings = 0
    var bitsets = 0
    var consumeFunctions = 0
    var transformFunctions = 0
    var matcherFunctions = 0
    var ints = 0
    var floats = 0
    var positions = 0
    var values = 0
    var instructionAddresses = 0
    var classStackAddresses = 0
    var positionStackAddresses = 0
    var savePointAddresses = 0
    var captures = 0
  }
}

extension Processor.Registers: CustomStringConvertible {
  var description: String {
    func formatRegisters<T>(
      _ name: String, _ regs: [T]
    ) -> String {
      // TODO: multi-line if long
      if regs.isEmpty { return "" }

      return "\(name): \(regs)\n"
    }

    return """
      \(formatRegisters("elements", elements))\
      \(formatRegisters("ints", ints))\

      """    
  }
}

