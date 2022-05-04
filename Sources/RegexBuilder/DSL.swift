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

import _RegexParser
@_spi(RegexBuilder) import _StringProcessing

@available(SwiftStdlib 5.7, *)
extension Regex {
  public init<Content: RegexComponent>(
    @RegexComponentBuilder _ content: () -> Content
  ) where Content.RegexOutput == Output {
    self = content().regex
  }
}

// A convenience protocol for builtin regex components that are initialized with
// a `DSLTree` node.
@available(SwiftStdlib 5.7, *)
internal protocol _BuiltinRegexComponent: RegexComponent {
  init(_ regex: Regex<RegexOutput>)
}

@available(SwiftStdlib 5.7, *)
extension _BuiltinRegexComponent {
  init(node: DSLTree.Node) {
    self.init(Regex(node: node))
  }
}

// MARK: - Primitive regex components

@available(SwiftStdlib 5.7, *)
extension String: RegexComponent {
  public typealias Output = Substring

  public var regex: Regex<Output> {
    .init(node: .quotedLiteral(self))
  }
}

@available(SwiftStdlib 5.7, *)
extension Substring: RegexComponent {
  public typealias Output = Substring

  public var regex: Regex<Output> {
    .init(node: .quotedLiteral(String(self)))
  }
}

@available(SwiftStdlib 5.7, *)
extension Character: RegexComponent {
  public typealias Output = Substring

  public var regex: Regex<Output> {
    .init(node: .atom(.char(self)))
  }
}

@available(SwiftStdlib 5.7, *)
extension UnicodeScalar: RegexComponent {
  public typealias Output = Substring

  public var regex: Regex<Output> {
    .init(node: .atom(.scalar(self)))
  }
}

// MARK: - Combinators

// MARK: Concatenation

// Note: Concatenation overloads are currently gyb'd.

// TODO: Variadic generics
// struct Concatenation<W0, C0..., R0: RegexComponent, W1, C1..., R1: RegexComponent>
// where R0.Match == (W0, C0...), R1.Match == (W1, C1...)
// {
//   typealias Match = (Substring, C0..., C1...)
//   let regex: Regex<Output>
//   init(_ first: R0, _ second: R1) {
//     regex = .init(concat(r0, r1))
//   }
// }

// MARK: Quantification

// Note: Quantifiers are currently gyb'd.

extension DSLTree.Node {
  // Individual public API functions are in the generated Variadics.swift file.
  /// Generates a DSL tree node for a repeated range of the given node.
  @available(SwiftStdlib 5.7, *)
  static func repeating(
    _ range: Range<Int>,
    _ behavior: RegexRepetitionBehavior?,
    _ node: DSLTree.Node
  ) -> DSLTree.Node {
    // TODO: Throw these as errors
    assert(range.lowerBound >= 0, "Cannot specify a negative lower bound")
    assert(!range.isEmpty, "Cannot specify an empty range")
    
    let kind: DSLTree.QuantificationKind = behavior.map { .explicit($0.dslTreeKind) } ?? .default

    switch (range.lowerBound, range.upperBound) {
    case (0, Int.max): // 0...
      return .quantification(.zeroOrMore, kind, node)
    case (1, Int.max): // 1...
      return .quantification(.oneOrMore, kind, node)
    case _ where range.count == 1: // ..<1 or ...0 or any range with count == 1
      // Note: `behavior` is ignored in this case
      return .quantification(.exactly(.init(faking: range.lowerBound)), .default, node)
    case (0, _): // 0..<n or 0...n or ..<n or ...n
      return .quantification(.upToN(.init(faking: range.upperBound)), kind, node)
    case (_, Int.max): // n...
      return .quantification(.nOrMore(.init(faking: range.lowerBound)), kind, node)
    default: // any other range
      return .quantification(.range(.init(faking: range.lowerBound), .init(faking: range.upperBound)), kind, node)
    }
  }
}

@available(SwiftStdlib 5.7, *)
public struct OneOrMore<Output>: _BuiltinRegexComponent {
  public var regex: Regex<Output>

  internal init(_ regex: Regex<Output>) {
    self.regex = regex
  }

  // Note: Public initializers and operators are currently gyb'd. See
  // Variadics.swift.
}

@available(SwiftStdlib 5.7, *)
public struct ZeroOrMore<Output>: _BuiltinRegexComponent {
  public var regex: Regex<Output>

  internal init(_ regex: Regex<Output>) {
    self.regex = regex
  }

  // Note: Public initializers and operators are currently gyb'd. See
  // Variadics.swift.
}

@available(SwiftStdlib 5.7, *)
public struct Optionally<Output>: _BuiltinRegexComponent {
  public var regex: Regex<Output>

  internal init(_ regex: Regex<Output>) {
    self.regex = regex
  }

  // Note: Public initializers and operators are currently gyb'd. See
  // Variadics.swift.
}

@available(SwiftStdlib 5.7, *)
public struct Repeat<Output>: _BuiltinRegexComponent {
  public var regex: Regex<Output>

  internal init(_ regex: Regex<Output>) {
    self.regex = regex
  }

  // Note: Public initializers and operators are currently gyb'd. See
  // Variadics.swift.
}

// MARK: Alternation

// TODO: Variadic generics
// @resultBuilder
// struct AlternationBuilder {
//   @_disfavoredOverload
//   func buildBlock<R: RegexComponent>(_ regex: R) -> R
//   func buildBlock<
//     R: RegexComponent, W0, C0...
//   >(
//     _ regex: R
//   ) -> R where R.Match == (W, C...)
// }

@available(SwiftStdlib 5.7, *)
@resultBuilder
public struct AlternationBuilder {
  @_disfavoredOverload
  public static func buildPartialBlock<R: RegexComponent>(
    first component: R
  ) -> ChoiceOf<R.RegexOutput> {
    .init(component.regex)
  }

  public static func buildExpression<R: RegexComponent>(_ regex: R) -> R {
    regex
  }

  public static func buildEither<R: RegexComponent>(first component: R) -> R {
    component
  }

  public static func buildEither<R: RegexComponent>(second component: R) -> R {
    component
  }
}

@available(SwiftStdlib 5.7, *)
public struct ChoiceOf<Output>: _BuiltinRegexComponent {
  public var regex: Regex<Output>

  internal init(_ regex: Regex<Output>) {
    self.regex = regex
  }

  public init(@AlternationBuilder _ builder: () -> Self) {
    self = builder()
  }
}

// MARK: - Capture

@available(SwiftStdlib 5.7, *)
public struct Capture<Output>: _BuiltinRegexComponent {
  public var regex: Regex<Output>

  internal init(_ regex: Regex<Output>) {
    self.regex = regex
  }

  // Note: Public initializers are currently gyb'd. See Variadics.swift.
}

@available(SwiftStdlib 5.7, *)
public struct TryCapture<Output>: _BuiltinRegexComponent {
  public var regex: Regex<Output>

  internal init(_ regex: Regex<Output>) {
    self.regex = regex
  }

  // Note: Public initializers are currently gyb'd. See Variadics.swift.
}

// MARK: - Groups

/// An atomic group.
///
/// This group opens a local backtracking scope which, upon successful exit,
/// discards any remaining backtracking points from within the scope.
@available(SwiftStdlib 5.7, *)
public struct Local<Output>: _BuiltinRegexComponent {
  public var regex: Regex<Output>

  internal init(_ regex: Regex<Output>) {
    self.regex = regex
  }
}

// MARK: - Backreference

@available(SwiftStdlib 5.7, *)
/// A backreference.
public struct Reference<Capture>: RegexComponent {
  let id = ReferenceID()

  public init(_ captureType: Capture.Type = Capture.self) {}

  public var regex: Regex<Capture> {
    .init(node: .atom(.symbolicReference(id)))
  }
}

@available(SwiftStdlib 5.7, *)
extension Regex.Match {
  public subscript<Capture>(_ reference: Reference<Capture>) -> Capture {
    self[reference.id]
  }
}
