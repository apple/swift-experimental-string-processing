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

struct MEProgram {
  typealias Input = String

  typealias ConsumeFunction = (Input, Range<Input.Index>) -> Input.Index?
  typealias TransformFunction =
    (Input, Processor._StoredCapture) throws -> Any?
  typealias MatcherFunction =
    (Input, Input.Index, Range<Input.Index>) throws -> (Input.Index, Any)?

  var instructions: InstructionList<Instruction>

  var staticElements: [Input.Element]
  var staticSequences: [[Input.Element]]
  var staticBitsets: [DSLTree.CustomCharacterClass.AsciiBitset]
  var staticConsumeFunctions: [ConsumeFunction]
  var staticTransformFunctions: [TransformFunction]
  var staticMatcherFunctions: [MatcherFunction]

  var registerInfo: RegisterInfo

  var enableTracing: Bool = false

  let captureList: CaptureList
  let referencedCaptureOffsets: [ReferenceID: Int]
  
  var initialOptions: MatchingOptions
}

extension MEProgram: CustomStringConvertible {
  var description: String {
    var result = """
    Elements: \(staticElements)

    """
    if !staticConsumeFunctions.isEmpty {
      result += "Consume functions: \(staticConsumeFunctions)"
    }

    // TODO: Extract into formatting code

    for idx in instructions.indices {
      let inst = instructions[idx]
      result += "[\(idx.rawValue)] \(inst)"
      if let ia = inst.instructionAddress {
        result += " // \(instructions[ia])"
      }
      result += "\n"
    }
    return result
  }
}
