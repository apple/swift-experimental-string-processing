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

@_spi(RegexBuilder)
public struct DSLTree {
  var root: Node

  init(_ r: Node) {
    self.root = r
  }
}

extension DSLTree {
  indirect enum Node {
    /// Matches each node in order.
    ///
    ///     ... | ... | ...
    case orderedChoice([Node])

    /// Match each node in sequence.
    ///
    ///     ... ...
    case concatenation([Node])

    /// Captures the result of a subpattern.
    ///
    ///     (...), (?<name>...)
    case capture(
      name: String? = nil, reference: ReferenceID? = nil, Node,
      CaptureTransform? = nil)

    /// Matches a noncapturing subpattern.
    case nonCapturingGroup(_AST.GroupKind, Node)

    // TODO: Consider splitting off grouped conditions, or have
    // our own kind

    /// Matches a choice of two nodes, based on a condition.
    ///
    ///     (?(cond) true-branch | false-branch)
    ///
    case conditional(
      _AST.ConditionKind, Node, Node)

    case quantification(
      _AST.QuantificationAmount,
      QuantificationKind,
      Node)

    case customCharacterClass(CustomCharacterClass)

    case atom(Atom)

    /// Comments, non-semantic whitespace, and so on.
    // TODO: Do we want this? Could be interesting
    case trivia(String)

    // TODO: Probably some atoms, built-ins, etc.

    case empty

    case quotedLiteral(String)

    // TODO: What should we do here?
    ///
    /// TODO: Consider splitting off expression functions, or have our own kind
    case absentFunction(_AST.AbsentFunction)

    // MARK: - Tree conversions

    /// The target of AST conversion.
    ///
    /// Keeps original AST around for rich syntactic and source information
    case convertedRegexLiteral(Node, _AST.ASTNode)

    // MARK: - Extensibility points

    case consumer(_ConsumerInterface)

    case matcher(Any.Type, _MatcherInterface)

    // TODO: Would this just boil down to a consumer?
    case characterPredicate(_CharacterPredicateInterface)
  }
}

extension DSLTree {
  enum QuantificationKind {
    /// The default quantification kind, as set by options.
    case `default`
    /// An explicitly chosen kind, overriding any options.
    case explicit(_AST.QuantificationKind)
    /// A kind set via syntax, which can be affected by options.
    case syntax(_AST.QuantificationKind)
    
    var ast: AST.Quantification.Kind? {
      switch self {
      case .default: return nil
      case .explicit(let kind), .syntax(let kind):
        return kind.ast
      }
    }
  }
  
  @_spi(RegexBuilder)
  public struct CustomCharacterClass {
    var members: [Member]
    var isInverted: Bool
    
    var containsDot: Bool {
      members.contains { member in
        switch member {
        case .atom(.dot): return true
        case .custom(let ccc): return ccc.containsDot
        default:
          return false
        }
      }
    }
    
    public init(members: [DSLTree.CustomCharacterClass.Member], isInverted: Bool = false) {
      self.members = members
      self.isInverted = isInverted
    }
    
    public static func generalCategory(_ category: Unicode.GeneralCategory) -> Self {
      let property = AST.Atom.CharacterProperty(.generalCategory(category.extendedGeneralCategory!), isInverted: false, isPOSIX: false)
      let astAtom = AST.Atom(.property(property), .fake)
      return .init(members: [.atom(.unconverted(.init(ast: astAtom)))])
    }
    
    public var inverted: CustomCharacterClass {
      var result = self
      result.isInverted.toggle()
      return result
    }

    @_spi(RegexBuilder)
    public enum Member {
      case atom(Atom)
      case range(Atom, Atom)
      case custom(CustomCharacterClass)

      case quotedLiteral(String)

      case trivia(String)

      indirect case intersection(CustomCharacterClass, CustomCharacterClass)
      indirect case subtraction(CustomCharacterClass, CustomCharacterClass)
      indirect case symmetricDifference(CustomCharacterClass, CustomCharacterClass)
    }
  }

  @_spi(RegexBuilder)
  public enum Atom {
    case char(Character)
    case scalar(Unicode.Scalar)

    /// Any character, including newlines.
    case any

    /// Any character, excluding newlines. This differs from '.', as it is not
    /// affected by single line mode.
    case anyNonNewline

    /// The DSL representation of '.' in a regex literal. This does not match
    /// newlines unless single line mode is enabled.
    case dot

    case assertion(Assertion)
    case backreference(_AST.Reference)
    case symbolicReference(ReferenceID)

    case changeMatchingOptions(_AST.MatchingOptionSequence)

    case unconverted(_AST.Atom)
  }
}

extension DSLTree.Atom {
  @_spi(RegexBuilder)
  public enum Assertion: Hashable {
    /// \A
    case startOfSubject

    /// \Z
    case endOfSubjectBeforeNewline

    /// \z
    case endOfSubject

    /// \K
    case resetStartOfMatch

    /// \G
    case firstMatchingPositionInSubject

    /// \y
    case textSegment

    /// \Y
    case notTextSegment

    /// The DSL's Anchor.startOfLine, which matches the start of a line
    /// even if `anchorsMatchNewlines` is false.
    case startOfLine

    /// The DSL's Anchor.endOfLine, which matches the end of a line
    /// even if `anchorsMatchNewlines` is false.
    case endOfLine

    /// ^
    case caretAnchor

    /// $
    case dollarAnchor

    /// \b (from outside a custom character class)
    case wordBoundary

    /// \B
    case notWordBoundary
  }
}

extension Unicode.GeneralCategory {
  var extendedGeneralCategory: Unicode.ExtendedGeneralCategory? {
    switch self {
    case .uppercaseLetter: return .uppercaseLetter
    case .lowercaseLetter: return .lowercaseLetter
    case .titlecaseLetter: return .titlecaseLetter
    case .modifierLetter: return .modifierLetter
    case .otherLetter: return .otherLetter
    case .nonspacingMark: return .nonspacingMark
    case .spacingMark: return .spacingMark
    case .enclosingMark: return .enclosingMark
    case .decimalNumber: return .decimalNumber
    case .letterNumber: return .letterNumber
    case .otherNumber: return .otherNumber
    case .connectorPunctuation: return .connectorPunctuation
    case .dashPunctuation: return .dashPunctuation
    case .openPunctuation: return .openPunctuation
    case .closePunctuation: return .closePunctuation
    case .initialPunctuation: return .initialPunctuation
    case .finalPunctuation: return .finalPunctuation
    case .otherPunctuation: return .otherPunctuation
    case .mathSymbol: return .mathSymbol
    case .currencySymbol: return .currencySymbol
    case .modifierSymbol: return .modifierSymbol
    case .otherSymbol: return .otherSymbol
    case .spaceSeparator: return .spaceSeparator
    case .lineSeparator: return .lineSeparator
    case .paragraphSeparator: return .paragraphSeparator
    case .control: return .control
    case .format: return .format
    case .surrogate: return .surrogate
    case .privateUse: return .privateUse
    case .unassigned: return .unassigned
    @unknown default: return nil
    }
  }
}

// CollectionConsumer
typealias _ConsumerInterface = (
  String, Range<String.Index>
) throws -> String.Index?

// Type producing consume
// TODO: better name
typealias _MatcherInterface = (
  String, String.Index, Range<String.Index>
) throws -> (String.Index, Any)?

// Character-set (post grapheme segmentation)
typealias _CharacterPredicateInterface = (
  (Character) -> Bool
)

/*

 TODO: Use of syntactic types, like group kinds, is a
 little suspect. We may want to figure out a model here.

 TODO: Do capturing groups need explicit numbers?

 TODO: Are storing closures better/worse than existentials?

 */

extension DSLTree.Node {
  @_spi(RegexBuilder)
  public var children: [DSLTree.Node] {
    switch self {
      
    case let .orderedChoice(v):   return v
    case let .concatenation(v): return v

    case let .convertedRegexLiteral(n, _):
      // Treat this transparently
      return n.children

    case let .capture(_, _, n, _):        return [n]
    case let .nonCapturingGroup(_, n):    return [n]
    case let .quantification(_, _, n):    return [n]

    case let .conditional(_, t, f): return [t,f]

    case .trivia, .empty, .quotedLiteral,
        .consumer, .matcher, .characterPredicate,
        .customCharacterClass, .atom:
      return []

    case let .absentFunction(abs):
      return abs.ast.children.map(\.dslTreeNode)
    }
  }
}

extension DSLTree.Node {
  var astNode: AST.Node? {
    switch self {
    case let .convertedRegexLiteral(_, literal): return literal.ast
    default: return nil
    }
  }

  /// If this node is for a converted literal, look through it.
  var lookingThroughConvertedLiteral: Self {
    switch self {
    case let .convertedRegexLiteral(n, _): return n
    default: return self
    }
  }
}

extension DSLTree.Atom {
  // Return the Character or promote a scalar to a Character
  var literalCharacterValue: Character? {
    switch self {
    case let .char(c):   return c
    case let .scalar(s): return Character(s)
    default: return nil
    }
  }
}

extension DSLTree {
  struct Options {
    // TBD
  }
}

extension DSLTree {
  var hasCapture: Bool {
    root.hasCapture
  }
}
extension DSLTree.Node {
  var hasCapture: Bool {
    switch self {
    case .capture:
      return true
    case let .convertedRegexLiteral(n, re):
      assert(n.hasCapture == re.ast.hasCapture)
      return n.hasCapture

    default:
      return self.children.any(\.hasCapture)
    }
  }
}

extension DSLTree.Node {
  func appending(_ newNode: DSLTree.Node) -> DSLTree.Node {
    if case .concatenation(let components) = self {
      return .concatenation(components + [newNode])
    }
    return .concatenation([self, newNode])
  }

  func appendingAlternationCase(
    _ newNode: DSLTree.Node
  ) -> DSLTree.Node {
    if case .orderedChoice(let components) = self {
      return .orderedChoice(components + [newNode])
    }
    return .orderedChoice([self, newNode])
  }
}

@_spi(RegexBuilder)
public struct ReferenceID: Hashable {
  private static var counter: Int = 0
  var base: Int

  public var _raw: Int {
    base
  }
  
  public init() {
    base = Self.counter
    Self.counter += 1
  }
  
  init(_ base: Int) {
    self.base = base
  }
}

struct CaptureTransform: Hashable, CustomStringConvertible {
  enum Closure {
    /// A failable transform.
    case failable((Any) throws -> Any?)
    /// Specialized case of `failable` for performance.
    case substringFailable((Substring) throws -> Any?)
    /// A non-failable transform.
    case nonfailable((Any) throws -> Any)
    /// Specialized case of `failable` for performance.
    case substringNonfailable((Substring) throws -> Any?)
  }
  let argumentType: Any.Type
  let resultType: Any.Type
  let closure: Closure

  init(argumentType: Any.Type, resultType: Any.Type, closure: Closure) {
    self.argumentType = argumentType
    self.resultType = resultType
    self.closure = closure
  }

  init<Argument, Result>(
    _ userSpecifiedTransform: @escaping (Argument) throws -> Result
  ) {
    let closure: Closure
    if let substringTransform = userSpecifiedTransform
      as? (Substring) throws -> Result {
      closure = .substringNonfailable(substringTransform)
    } else {
      closure = .nonfailable {
        try userSpecifiedTransform($0 as! Argument) as Any
      }
    }
    self.init(
      argumentType: Argument.self,
      resultType: Result.self,
      closure: closure)
  }

  init<Argument, Result>(
    _ userSpecifiedTransform: @escaping (Argument) throws -> Result?
  ) {
    let closure: Closure
    if let substringTransform = userSpecifiedTransform
      as? (Substring) throws -> Result? {
      closure = .substringFailable(substringTransform)
    } else {
      closure = .failable {
        try userSpecifiedTransform($0 as! Argument) as Any?
      }
    }
    self.init(
      argumentType: Argument.self,
      resultType: Result.self,
      closure: closure)
  }

  func callAsFunction(_ input: Any) throws -> Any? {
    switch closure {
    case .nonfailable(let transform):
      let result = try transform(input)
      assert(type(of: result) == resultType)
      return result
    case .substringNonfailable(let transform):
      let result = try transform(input as! Substring)
      assert(type(of: result) == resultType)
      return result
    case .failable(let transform):
      guard let result = try transform(input) else {
        return nil
      }
      assert(type(of: result) == resultType)
      return result
    case .substringFailable(let transform):
      guard let result = try transform(input as! Substring) else {
        return nil
      }
      assert(type(of: result) == resultType)
      return result
    }
  }

  func callAsFunction(_ input: Substring) throws -> Any? {
    switch closure {
    case .substringFailable(let transform):
      return try transform(input)
    case .substringNonfailable(let transform):
      return try transform(input)
    case .failable(let transform):
      return try transform(input)
    case .nonfailable(let transform):
      return try transform(input)
    }
  }

  static func == (lhs: CaptureTransform, rhs: CaptureTransform) -> Bool {
    unsafeBitCast(lhs.closure, to: (Int, Int).self) ==
      unsafeBitCast(rhs.closure, to: (Int, Int).self)
  }

  func hash(into hasher: inout Hasher) {
    let (fn, ctx) = unsafeBitCast(closure, to: (Int, Int).self)
    hasher.combine(fn)
    hasher.combine(ctx)
  }

  var description: String {
    "<transform argument_type=\(argumentType) result_type=\(resultType)>"
  }
}

extension CaptureList.Builder {
  mutating func addCaptures(
    of node: DSLTree.Node, optionalNesting nesting: OptionalNesting
  ) {
    switch node {
    case let .orderedChoice(children):
      for child in children {
        addCaptures(of: child, optionalNesting: nesting.addingOptional)
      }

    case let .concatenation(children):
      for child in children {
        addCaptures(of: child, optionalNesting: nesting)
      }

    case let .capture(name, _, child, transform):
      captures.append(.init(
        name: name,
        type: transform?.resultType ?? child.wholeMatchType,
        optionalDepth: nesting.depth, .fake))
      addCaptures(of: child, optionalNesting: nesting)

    case let .nonCapturingGroup(kind, child):
      assert(!kind.ast.isCapturing)
      addCaptures(of: child, optionalNesting: nesting)

    case let .conditional(cond, trueBranch, falseBranch):
      switch cond.ast {
      case .group(let g):
        addCaptures(of: .group(g), optionalNesting: nesting)
      default:
        break
      }

      addCaptures(of: trueBranch, optionalNesting: nesting.addingOptional)
      addCaptures(of: falseBranch, optionalNesting: nesting.addingOptional)

    case let .quantification(amount, _, child):
      var optNesting = nesting
      if amount.ast.bounds.atLeast == 0 {
        optNesting = optNesting.addingOptional
      }
      addCaptures(of: child, optionalNesting: optNesting)

    case let .absentFunction(abs):
      switch abs.ast.kind {
      case .expression(_, _, let child):
        addCaptures(of: child, optionalNesting: nesting)
      case .clearer, .repeater, .stopper:
        break
      }

    case let .convertedRegexLiteral(n, _):
      // We disable nesting for converted AST trees, as literals do not nest
      // captures. This includes literals nested in a DSL.
      return addCaptures(of: n, optionalNesting: nesting.disablingNesting)

    case .matcher:
      break

    case .customCharacterClass, .atom, .trivia, .empty,
        .quotedLiteral, .consumer, .characterPredicate:
      break
    }
  }

  static func build(_ dsl: DSLTree) -> CaptureList {
    var builder = Self()
    builder.captures.append(
      .init(type: dsl.root.wholeMatchType, optionalDepth: 0, .fake))
    builder.addCaptures(of: dsl.root, optionalNesting: .init(canNest: true))
    return builder.captures
  }
}

extension DSLTree.Node {
  /// Returns true if the node is output-forwarding, i.e. not defining its own
  /// output but forwarding its only child's output.
  var isOutputForwarding: Bool {
    switch self {
    case .nonCapturingGroup:
      return true
    case .orderedChoice, .concatenation, .capture,
         .conditional, .quantification, .customCharacterClass, .atom,
         .trivia, .empty, .quotedLiteral, .absentFunction,
         .convertedRegexLiteral, .consumer,
         .characterPredicate, .matcher:
      return false
    }
  }

  /// Returns the output-defining node, peering through any output-forwarding
  /// nodes.
  var outputDefiningNode: Self {
    if isOutputForwarding {
      assert(children.count == 1)
      return children[0].outputDefiningNode
    }
    return self
  }

  /// Returns the type of the whole match, i.e. `.0` element type of the output.
  var wholeMatchType: Any.Type {
    if case .matcher(let type, _) = outputDefiningNode {
      return type
    }
    return Substring.self
  }
}

// MARK: AST wrapper types
//
// These wrapper types are required because even @_spi-marked public APIs can't
// include symbols from implementation-only dependencies.

extension DSLTree {
  var captureList: CaptureList { .Builder.build(self) }

  /// Presents a wrapped version of `DSLTree.Node` that can provide an internal
  /// `_TreeNode` conformance.
  struct _Tree: _TreeNode {
    var node: DSLTree.Node
    
    init(_ node: DSLTree.Node) {
      self.node = node
    }
    
    var children: [_Tree]? {
      switch node {
        
      case let .orderedChoice(v): return v.map(_Tree.init)
      case let .concatenation(v): return v.map(_Tree.init)

      case let .convertedRegexLiteral(n, _):
        // Treat this transparently
        return _Tree(n).children

      case let .capture(_, _, n, _):        return [_Tree(n)]
      case let .nonCapturingGroup(_, n):    return [_Tree(n)]
      case let .quantification(_, _, n):    return [_Tree(n)]

      case let .conditional(_, t, f): return [_Tree(t), _Tree(f)]

      case .trivia, .empty, .quotedLiteral,
          .consumer, .matcher, .characterPredicate,
          .customCharacterClass, .atom:
        return []

      case let .absentFunction(abs):
        return abs.ast.children.map(\.dslTreeNode).map(_Tree.init)
      }
    }
  }

  @_spi(RegexBuilder)
  public enum _AST {
    @_spi(RegexBuilder)
    public struct GroupKind {
      internal var ast: AST.Group.Kind
      
      public static var atomicNonCapturing: Self {
        .init(ast: .atomicNonCapturing)
      }
      public static var lookahead: Self {
        .init(ast: .lookahead)
      }
      public static var negativeLookahead: Self {
        .init(ast: .negativeLookahead)
      }
    }

    @_spi(RegexBuilder)
    public struct ConditionKind {
      internal var ast: AST.Conditional.Condition.Kind
    }
    
    @_spi(RegexBuilder)
    public struct QuantificationKind {
      internal var ast: AST.Quantification.Kind
      
      public static var eager: Self {
        .init(ast: .eager)
      }
      public static var reluctant: Self {
        .init(ast: .reluctant)
      }
      public static var possessive: Self {
        .init(ast: .possessive)
      }
    }
    
    @_spi(RegexBuilder)
    public struct QuantificationAmount {
      internal var ast: AST.Quantification.Amount
      
      public static var zeroOrMore: Self {
        .init(ast: .zeroOrMore)
      }
      public static var oneOrMore: Self {
        .init(ast: .oneOrMore)
      }
      public static var zeroOrOne: Self {
        .init(ast: .zeroOrOne)
      }
      public static func exactly(_ n: Int) -> Self {
        .init(ast: .exactly(.init(n, at: .fake)))
      }
      public static func nOrMore(_ n: Int) -> Self {
        .init(ast: .nOrMore(.init(n, at: .fake)))
      }
      public static func upToN(_ n: Int) -> Self {
        .init(ast: .upToN(.init(n, at: .fake)))
      }
      public static func range(_ lower: Int, _ upper: Int) -> Self {
        .init(ast: .range(.init(lower, at: .fake), .init(upper, at: .fake)))
      }
    }
    
    @_spi(RegexBuilder)
    public struct ASTNode {
      internal var ast: AST.Node
    }
    
    @_spi(RegexBuilder)
    public struct AbsentFunction {
      internal var ast: AST.AbsentFunction
    }
    
    @_spi(RegexBuilder)
    public struct Reference {
      internal var ast: AST.Reference
    }
    
    @_spi(RegexBuilder)
    public struct MatchingOptionSequence {
      internal var ast: AST.MatchingOptionSequence
    }
    
    @_spi(RegexBuilder)
    public struct Atom {
      internal var ast: AST.Atom

      // FIXME: The below APIs should be removed once the DSL tree has been
      // migrated to use proper DSL atoms for them.

      public static var _anyGrapheme: Self {
        .init(ast: .init(.escaped(.graphemeCluster), .fake))
      }
      public static var _whitespace: Self {
        .init(ast: .init(.escaped(.whitespace), .fake))
      }
      public static var _digit: Self {
        .init(ast: .init(.escaped(.decimalDigit), .fake))
      }
      public static var _horizontalWhitespace: Self {
        .init(ast: .init(.escaped(.horizontalWhitespace), .fake))
      }
      public static var _newlineSequence: Self {
        .init(ast: .init(.escaped(.newlineSequence), .fake))
      }
      public static var _verticalWhitespace: Self {
        .init(ast: .init(.escaped(.verticalTab), .fake))
      }
      public static var _word: Self {
        .init(ast: .init(.escaped(.wordCharacter), .fake))
      }
    }
  }
}

extension DSLTree.Atom {
  /// Returns a Boolean indicating whether the atom represents a pattern that's
  /// matchable, e.g. a character or a scalar, not representing a change of
  /// matching options or an assertion.
  var isMatchable: Bool {
    switch self {
    case .changeMatchingOptions, .assertion:
      return false
    case .char, .scalar, .any, .anyNonNewline, .dot, .backreference,
        .symbolicReference, .unconverted:
      return true
    }
  }
}

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
    precondition(range.lowerBound >= 0, "Cannot specify a negative lower bound")
    precondition(!range.isEmpty, "Cannot specify an empty range")

    let kind: DSLTree.QuantificationKind = behavior
      .map { .explicit($0.dslTreeKind) } ?? .default

    // The upper bound needs adjusting down as
    // `.quantification` expects a closed range.
    let lower = range.lowerBound
    let upperInclusive = range.upperBound - 1

    // Unbounded cases
    if range.upperBound == Int.max {
      switch lower {
      case 0: // 0...
        return .quantification(.zeroOrMore, kind, node)
      case 1: // 1...
        return .quantification(.oneOrMore, kind, node)
      default: // n...
        return .quantification(.nOrMore(lower), kind, node)
      }
    }
    if range.count == 1 {
      // ..<1 or ...0 or any range with count == 1
      // Note: `behavior` is ignored in this case
      return .quantification(.exactly(lower), .default, node)
    }
    switch lower {
    case 0: // 0..<n or 0...n or ..<n or ...n
      return .quantification(.upToN(upperInclusive), kind, node)
    default:
      return .quantification(.range(lower, upperInclusive), kind, node)
    }
  }
}
