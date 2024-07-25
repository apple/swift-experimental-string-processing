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

internal import _RegexParser

/// A type that represents a regular expression.
///
/// You can use types that conform to `RegexComponent` as parameters to string
/// searching operations and inside `RegexBuilder` closures.
@available(SwiftStdlib 5.7, *)
public protocol RegexComponent<RegexOutput> {
  /// The output type for this regular expression.
  ///
  /// A `Regex` instance's output type depends on whether the `Regex` has
  /// captures and how it is created.
  ///
  /// - A `Regex` created from a string using the ``init(_:)`` initializer
  ///   has an output type of ``AnyRegexOutput``, whether it has captures or
  ///   not.
  /// - A `Regex` without captures created from a regex literal, the
  ///   ``init(_:as:)`` initializer, or a `RegexBuilder` closure has a
  ///   `Substring` output type, where the substring is the portion of the
  ///   string that was matched.
  /// - A `Regex` with captures created from a regex literal or the
  ///   ``init(_:as:)`` initializer has a tuple of substrings as its output
  ///   type. The first component of the tuple is the full portion of the string
  ///   that was matched, with the remaining components holding the captures.
  associatedtype RegexOutput
  
  /// The regular expression represented by this component.
  var regex: Regex<RegexOutput> { get }
}

/// A regular expression.
///
/// Regular expressions are a concise way of describing a pattern, which can
/// help you match or extract portions of a string. You can create a `Regex`
/// instance using regular expression syntax, either in a regex literal or a
/// string.
///
///     // 'keyAndValue' is created using a regex literal
///     let keyAndValue = /(.+?): (.+)/
///     // 'simpleDigits' is created from a pattern in a string
///     let simpleDigits = try Regex("[0-9]+")
///
/// You can use a `Regex` to search for a pattern in a string or substring.
/// Call `contains(_:)` to check for the presence of a pattern, or
/// `firstMatch(of:)` or `matches(of:)` to find matches.
///
///     let setting = "color: 161 103 230"
///     if setting.contains(simpleDigits) {
///         print("'\(setting)' contains some digits.")
///     }
///     // Prints "'color: 161 103 230' contains some digits."
///
/// When you find a match, the resulting ``Match`` type includes an
/// ``Match/output`` property that contains the matched substring along with
/// any captures:
///
///     if let match = setting.firstMatch(of: keyAndValue) {
///         print("Key: \(match.1)")
///         print("Value: \(match.2)")
///     }
///     // Key: color
///     // Value: 161 103 230
///
/// When you import the `RegexBuilder` module, you can also create `Regex`
/// instances using a clear and flexible declarative syntax. Using this
/// style, you can combine, capture, and transform regexes, `RegexBuilder`
/// types, and custom parsers.
///
/// > Note:
/// > Prior to Swift 6,
/// > you might need to write `#/myregex/#` instead of `/myregex/`
/// > when you make a regular expression using a literal.
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
    self.program = Program(ast:
        .init(ast, globalOptions: nil, diags: Diagnostics()))
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
  @available(*, deprecated, renamed: "init(verbatim:)")
  public init(quoting _string: String) {
    self.init(node: .quotedLiteral(_string))
  }
}


@available(SwiftStdlib 5.7, *)
extension Regex {
  /// A program representation that caches any lowered representation for
  /// execution.
  internal final class Program {

    // This stored property should be stored at offset zero.  We perform atomic
    // operations on it.
    //
    /// Do not access this property directly - all accesses must go through `_loweredProgramStoragePtr `.
    fileprivate var _loweredProgramStorage: AnyObject? = nil

    /// The underlying IR.
    ///
    /// FIXME: If Regex is the unit of composition, then it should be a Node instead,
    /// and we should have a separate type that handled both global options and,
    /// likely, compilation/caching.
    let tree: DSLTree

    /// OptionSet of compiler options for testing purposes
    fileprivate var compileOptions: _CompileOptions = .default

    private final class ProgramBox {
      let value: MEProgram
      init(_ value: MEProgram) { self.value = value }
    }

    fileprivate var _loweredProgramStoragePtr: UnsafeMutablePointer<AnyObject?> {
      _getUnsafePointerToStoredProperties(self)
        .assumingMemoryBound(to: Optional<AnyObject>.self)
    }

    /// The program for execution with the matching engine.
    var loweredProgram: MEProgram {
      /// Atomically loads the compiled program if it has already been stored.
      func loadProgram() -> MEProgram? {
        guard let loweredObject = _stdlib_atomicLoadARCRef(object: _loweredProgramStoragePtr)
          else { return nil }
        return unsafeDowncast(loweredObject, to: ProgramBox.self).value
      }
      
      // Use the previously compiled program, if available.
      if let program = loadProgram() {
        return program
      }
      
      // Compile the DSLTree into a lowered program and store it atomically.
      let compiledProgram = try! Compiler(tree: tree, compileOptions: compileOptions).emit()
      let storedNewProgram = _stdlib_atomicInitializeARCRef(
        object: _loweredProgramStoragePtr,
        desired: ProgramBox(compiledProgram))
      
      // Return the winner of the storage race. We're guaranteed at this point
      // to have compiled program stored in `_loweredProgramStorage`.
      return storedNewProgram
        ? compiledProgram
        : loadProgram()!
    }

    init(ast: AST) {
      self.tree = ast.dslTree
    }

    init(tree: DSLTree) {
      self.tree = tree
    }
  }
  
  /// The set of matching options that applies to the start of this regex.
  ///
  /// Note that the initial options may not apply to the entire regex. For
  /// example, in this regex, only case insensitivity (`i`) and Unicode scalar
  /// semantics (set by API) apply to the entire regex, while ASCII character
  /// classes (`P`) is part of `initialOptions` but not global:
  ///
  ///     let regex = /(?i)(?P:\d+\s*)abc/.semanticLevel(.unicodeScalar)
  var initialOptions: MatchingOptions {
    program.loweredProgram.initialOptions
  }
}

@available(SwiftStdlib 5.7, *)
extension Regex {
  var root: DSLTree.Node {
    program.tree.root
  }

  init(node: DSLTree.Node) {
    self.program = Program(tree: .init(node))
  }
}

@available(SwiftStdlib 5.7, *)
@_spi(RegexBenchmark)
extension Regex {
  public enum _RegexInternalAction {
    case recompile
    case addOptions(_CompileOptions)
  }
  
  /// Internal API for RegexBenchmark
  /// Forces the regex to perform the given action, returning if it was successful
  public mutating func _forceAction(_ action: _RegexInternalAction) -> Bool {
    do {
      switch action {
      case .addOptions(let opts):
        program.compileOptions.insert(opts)
        program._loweredProgramStorage = nil
        return true
      case .recompile:
        let _ = try Compiler(
          tree: program.tree,
          compileOptions: program.compileOptions).emit()
        return true
      }
    } catch {
      return false
    }
  }
}
