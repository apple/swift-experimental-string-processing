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


/// A type that represents a regular expression.
@available(SwiftStdlib 5.7, *)
public protocol RegexComponent {
  associatedtype RegexOutput
  var regex: Regex<RegexOutput> { get }
}

/// A regular expression.
///
///     let regex = try Regex("a(.*)b")
///     let match = "cbaxb".firstMatch(of: regex)
///     print(match.0) // "axb"
///     print(match.1) // "x"
///
@available(SwiftStdlib 5.7, *)
public struct Regex<Output>: RegexComponent {
  let program: Program

  var hasCapture: Bool {
    program.tree.hasCapture
  }

  init(ast: AST) {
    self.program = Program(ast: ast)
  }
  init(ast: AST.Node) {
    self.program = Program(ast: .init(ast, globalOptions: nil))
  }

  // Compiler interface. Do not change independently.
  @usableFromInline
  init(_regexString pattern: String) {
    self.init(ast: try! parse(pattern, .traditional))
  }

  // Compiler interface. Do not change independently.
  @usableFromInline
  init(_regexString pattern: String, version: Int) {
    assert(version == currentRegexLiteralFormatVersion)
    // The version argument is passed by the compiler using the value defined
    // in libswiftParseRegexLiteral.
    self.init(ast: try! parseWithDelimiters(pattern))
  }

  public var regex: Regex<Output> {
    self
  }
}

@available(SwiftStdlib 5.7, *)
extension Regex {
  /// A program representation that caches any lowered representation for
  /// execution.
  internal class Program {
    /// The underlying IR.
    ///
    /// FIXME: If Regex is the unit of composition, then it should be a Node instead,
    /// and we should have a separate type that handled both global options and,
    /// likely, compilation/caching.
    let tree: DSLTree

    /// The program for execution with the matching engine.
    lazy private(set) var loweredProgram = try! Compiler(tree: tree).emit()

    init(ast: AST) {
      self.tree = ast.dslTree
    }

    init(tree: DSLTree) {
      self.tree = tree
    }
  }
}

@available(SwiftStdlib 5.7, *)
extension Regex {
  @_spi(RegexBuilder)
  public var root: DSLTree.Node {
    program.tree.root
  }

  @_spi(RegexBuilder)
  public init(node: DSLTree.Node) {
    self.program = Program(tree: .init(node, options: nil))
  }
}
