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

/// State used when to pretty-printing regex ASTs.
public struct PrettyPrinter {
  // Configuration

  /// The maximum number number of levels, from the root of the tree,
  /// at which to perform pattern conversion.
  ///
  /// A `nil` value indicates that there is no maximum,
  /// and pattern conversion always takes place.
  public var maxTopDownLevels: Int?

  /// The maximum number number of levels, from the leaf nodes of the tree,
  /// at which to perform pattern conversion.
  ///
  /// A `nil` value indicates that there is no maximum,
  /// and pattern conversion always takes place.
  public var minBottomUpLevels: Int?

  /// The number of spaces used for indentation.
  public var indentWidth = 2

  // Internal state

  // The output string we're building up
  fileprivate var result = ""

  // Whether next print needs to indent
  fileprivate var startOfLine = true

  // The indentation level
  fileprivate var indentLevel = 0
}

// MARK: - Raw interface
extension PrettyPrinter {
  // This might be necessary if `fileprivate` above suppresses
  // default struct inits.
  public init(
    maxTopDownLevels: Int? = nil,
    minBottomUpLevels: Int? = nil
  ) {
    self.maxTopDownLevels = maxTopDownLevels
    self.minBottomUpLevels = minBottomUpLevels
  }

  /// Outputs a string directly, without termination or
  /// indentation, and without updating any internal state.
  ///
  /// This is the low-level interface to the pretty printer.
  ///
  /// - Note: If `s` includes a newline, even at the end,
  ///   this method does not update any tracking state.
  public mutating func output(_ s: String) {
    result += s
  }

  /// Terminates a line, updating any relevant state.
  public mutating func terminateLine() {
    output("\n")
    startOfLine = true
  }

  /// Indents a new line, if at the start of a line, otherwise
  /// does nothing.
  ///
  /// This function updates internal state.
  public mutating func indent() {
    guard startOfLine else { return }
    let numCols = indentLevel * indentWidth
    output(String(repeating: " ", count: numCols))
    startOfLine = false
  }

  // Finish, flush, and clear.
  //
  // - Returns: The rendered output.
  public mutating func finish() -> String {
    defer { result = "" }
    return result
  }

  public var depth: Int { indentLevel }
}

// MARK: - Pretty-print interface
extension PrettyPrinter {
  /// Print out a new entry.
  ///
  /// This method indents `s`, updates any internal state,
  /// and terminates the current line.
  public mutating func print(_ s: String) {
    indent()
    output("\(s)")
    terminateLine()
  }

  /// Prints out a new entry by invoking `f` until it returns `nil`.
  ///
  /// This method indents `s`, updates any internal state,
  /// and terminates the current line.
  public mutating func printLine(_ f: () -> String?) {
    // TODO: What should we do if `f` never returns non-nil?
    indent()
    while let s = f() {
      output(s)
    }
    terminateLine()
  }

  /// Executes `f` at one increased level of indentation.
  public mutating func printIndented(
    _ f: (inout Self) -> ()
  ) {
    self.indentLevel += 1
    f(&self)
    self.indentLevel -= 1
  }

  /// Executes `f` inside an indented block, which has a header
  /// and delimiters.
  public mutating func printBlock(
    _ header: String,
    startDelimiter: String = "{",
    endDelimiter: String = "}",
    _ f: (inout Self) -> ()
  ) {
    print("\(header) \(startDelimiter)")
    printIndented(f)
    print(endDelimiter)
  }
}
