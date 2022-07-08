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

class Compiler {
  let tree: DSLTree

  // TODO: Or are these stored on the tree?
  var options = MatchingOptions()
  private var compileOptions: CompileOptions = .default

  init(ast: AST) {
    self.tree = ast.dslTree
  }

  init(tree: DSLTree) {
    self.tree = tree
  }

  init(tree: DSLTree, compileOptions: CompileOptions) {
    self.tree = tree
    self.compileOptions = compileOptions
  }

  __consuming func emit() throws -> MEProgram {
    // TODO: Handle global options
    var codegen = ByteCodeGen(
      options: options,
      compileOptions:
        compileOptions,
      captureList: tree.captureList)
    return try codegen.emitRoot(tree.root)
  }
}

// An error produced when compiling a regular expression.
enum RegexCompilationError: Error, CustomStringConvertible {
  case uncapturedReference([DSLSourceLocation] = [])

  case incorrectOutputType(incorrect: Any.Type, correct: Any.Type)
  
  var description: String {
    switch self {
    case .uncapturedReference(let locs):
      var message = "Found a reference used before it captured any match."
      if !locs.isEmpty {
        message += " Used at:\n"
        for loc in locs {
          message += "- \(loc)\n"
        }
      }
      return message
    case .incorrectOutputType(let incorrect, let correct):
      return "Cast to incorrect type 'Regex<\(incorrect)>', expected 'Regex<\(correct)>'"
    }
  }
}

// Testing support
@available(SwiftStdlib 5.7, *)
func _compileRegex(
  _ regex: String,
  _ syntax: SyntaxOptions = .traditional,
  _ semanticLevel: RegexSemanticLevel? = nil
) throws -> Executor {
  let ast = try parse(regex, syntax)
  let dsl: DSLTree

  switch semanticLevel?.base {
  case .graphemeCluster:
    let sequence = AST.MatchingOptionSequence(adding: [.init(.graphemeClusterSemantics, location: .fake)])
    dsl = DSLTree(.nonCapturingGroup(.init(ast: .changeMatchingOptions(sequence)), ast.dslTree.root))
  case .unicodeScalar:
    let sequence = AST.MatchingOptionSequence(adding: [.init(.unicodeScalarSemantics, location: .fake)])
    dsl = DSLTree(.nonCapturingGroup(.init(ast: .changeMatchingOptions(sequence)), ast.dslTree.root))
  case .none:
    dsl = ast.dslTree
  }
  let program = try Compiler(tree: dsl).emit()
  return Executor(program: program)
}

extension Compiler {
  struct CompileOptions: OptionSet {
    let rawValue: Int
    static let disableOptimizations = CompileOptions(rawValue: 1)
    static let `default`: CompileOptions = []
  }
}
