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

    /// An embedded literal.
    case regexLiteral(_AST.ASTNode)

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
    
    var containsAny: Bool {
      members.contains { member in
        switch member {
        case .atom(.any): return true
        case .custom(let ccc): return ccc.containsAny
        default:
          return false
        }
      }
    }
    
    public init(members: [DSLTree.CustomCharacterClass.Member], isInverted: Bool = false) {
      self.members = members
      self.isInverted = isInverted
    }
    
    private static func astCharacterProperty(
      _ property: AST.Atom.CharacterProperty.Kind
    ) -> Self {
      let property = AST.Atom.CharacterProperty(property, isInverted: false, isPOSIX: false)
      let astAtom = AST.Atom(.property(property), .fake)
      return .init(members: [.atom(.unconverted(.init(ast: astAtom)))])
    }
    
    public static func generalCategory(_ category: Unicode.GeneralCategory) -> Self {
      astCharacterProperty(.generalCategory(category.extendedGeneralCategory!))
    }

    public static func binaryProperty(
      _ property: KeyPath<UnicodeScalar.Properties, Bool>,
      value: Bool
    ) -> Self {
      var binaryProperty: Unicode.BinaryProperty? = nil
      switch property {
      case \.isAlphabetic: binaryProperty = .alphabetic
      case \.isASCIIHexDigit: binaryProperty = .asciiHexDigit
      case \.isBidiControl: binaryProperty = .bidiControl
      case \.isBidiMirrored: binaryProperty = .bidiMirrored
      case \.isCased: binaryProperty = .cased
      case \.isCaseIgnorable: binaryProperty = .caseIgnorable
      case \.changesWhenCaseFolded: binaryProperty = .changesWhenCasefolded
      case \.changesWhenCaseMapped: binaryProperty = .changesWhenCasemapped
      case \.changesWhenNFKCCaseFolded: binaryProperty = .changesWhenNFKCCasefolded
      case \.changesWhenLowercased: binaryProperty = .changesWhenLowercased
      case \.changesWhenTitlecased: binaryProperty = .changesWhenTitlecased
      case \.changesWhenUppercased: binaryProperty = .changesWhenUppercased
      case \.isDash: binaryProperty = .dash
      case \.isDefaultIgnorableCodePoint: binaryProperty = .defaultIgnorableCodePoint
      case \.isDeprecated: binaryProperty = .deprecated
      case \.isDiacritic: binaryProperty = .diacratic
      case \.isExtender: binaryProperty = .extender
      case \.isFullCompositionExclusion: binaryProperty = .fullCompositionExclusion
      case \.isGraphemeBase: binaryProperty = .graphemeBase
      case \.isGraphemeExtend: binaryProperty = .graphemeExtended
      case \.isHexDigit: binaryProperty = .hexDigit
      case \.isIDContinue: binaryProperty = .idContinue
      case \.isIdeographic: binaryProperty = .ideographic
      case \.isIDStart: binaryProperty = .idStart
      case \.isIDSBinaryOperator: binaryProperty = .idsBinaryOperator
      case \.isIDSTrinaryOperator: binaryProperty = .idsTrinaryOperator
      case \.isJoinControl: binaryProperty = .joinControl
      case \.isLogicalOrderException: binaryProperty = .logicalOrderException
      case \.isLowercase: binaryProperty = .lowercase
      case \.isMath: binaryProperty = .math
      case \.isNoncharacterCodePoint: binaryProperty = .noncharacterCodePoint
      case \.isPatternSyntax: binaryProperty = .patternSyntax
      case \.isPatternWhitespace: binaryProperty = .patternWhitespace
      case \.isQuotationMark: binaryProperty = .quotationMark
      case \.isRadical: binaryProperty = .radical
      case \.isSoftDotted: binaryProperty = .softDotted
      case \.isSentenceTerminal: binaryProperty = .sentenceTerminal
      case \.isTerminalPunctuation: binaryProperty = .terminalPunctuation
      case \.isUnifiedIdeograph: binaryProperty = .unifiedIdiograph
      case \.isUppercase: binaryProperty = .uppercase
      case \.isVariationSelector: binaryProperty = .variationSelector
      case \.isWhitespace: binaryProperty = .whitespace
      case \.isXIDContinue: binaryProperty = .xidContinue
      case \.isXIDStart: binaryProperty = .xidStart
      default:
        if #available(macOS 10.12.2, iOS 10.2, tvOS 10.1, watchOS 3.1.1, *) {
          // FIXME: Other platforms
          switch property {
          case \.isEmojiModifierBase: binaryProperty = .emojiModifierBase
          case \.isEmojiModifier: binaryProperty = .emojiModifier
          case \.isEmoji: binaryProperty = .emoji
          case \.isEmojiPresentation: binaryProperty = .emojiPresentation
          default:
            break
          }
        }
      }
      
      if let binaryProperty = binaryProperty {
        return astCharacterProperty(.binary(binaryProperty, value: value))
      } else {
        // FIXME: Support via a _UnicodeScalarPredicate interface?
        fatalError("Unsupported Unicode binary property")
      }
    }

    public static func age(_ version: Unicode.Version) -> Self {
      astCharacterProperty(.age(major: version.major, minor: version.minor))
    }
    
    public static func named(_ name: String) -> Self {
      astCharacterProperty(.named(name))
    }
    
    public static func numericType(_ type: Unicode.NumericType) -> Self {
      astCharacterProperty(.numericType(type))
    }
    
    public static func numericValue(_ value: Double) -> Self {
      astCharacterProperty(.numericValue(value))
    }
    
    public static func ccc(_ combiningClass: Unicode.CanonicalCombiningClass) -> Self {
      astCharacterProperty(.ccc(combiningClass))
    }
    
    public static func lowercaseMapping(_ value: String) -> Self {
      astCharacterProperty(.mapping(.lowercase, value))
    }
    
    public static func uppercaseMapping(_ value: String) -> Self {
      astCharacterProperty(.mapping(.uppercase, value))
    }
    
    public static func titlecaseMapping(_ value: String) -> Self {
      astCharacterProperty(.mapping(.titlecase, value))
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
    
    internal struct AsciiBitset {
      let isInverted: Bool
      var a: UInt64 = 0
      var b: UInt64 = 0

      init(isInverted: Bool) {
        self.isInverted = isInverted
      }

      init(_ val: UInt8, _ isInverted: Bool, _ isCaseInsensitive: Bool) {
        self.isInverted = isInverted
        add(val, isCaseInsensitive)
      }

      init(low: UInt8, high: UInt8, isInverted: Bool, isCaseInsensitive: Bool) {
        self.isInverted = isInverted
        for val in low...high {
          add(val, isCaseInsensitive)
        }
      }

      internal init(
        a: UInt64,
        b: UInt64,
        isInverted: Bool
      ) {
        self.isInverted = isInverted
        self.a = a
        self.b = b
      }

      internal mutating func add(_ val: UInt8, _ isCaseInsensitive: Bool) {
        setBit(val)
        if isCaseInsensitive {
          switch val {
            case 64...90: setBit(val + 32)
            case 97...122: setBit(val - 32)
            default: break
          }
        }
      }

      internal mutating func setBit(_ val: UInt8) {
        if val < 64 {
          a = a | 1 << val
        } else {
          b = b | 1 << (val - 64)
        }
      }

      internal func matches(char: Character) -> Bool {
        let ret: Bool
        if let val = char.asciiValue {
          if val < 64 {
            ret = (a >> val) & 1 == 1
          } else {
            ret =  (b >> (val - 64)) & 1 == 1
          }
        } else {
          ret = false
        }

        if isInverted {
          return !ret
        }

        return ret
      }

      /// Joins another bitset from a Member of the same CustomCharacterClass
      internal func union(_ other: AsciiBitset) -> AsciiBitset {
        precondition(self.isInverted == other.isInverted)
        return AsciiBitset(
          a: self.a | other.a,
          b: self.b | other.b,
          isInverted: self.isInverted
        )
      }
    }
  }

  @_spi(RegexBuilder)
  public enum Atom {
    case char(Character)
    case scalar(Unicode.Scalar)
    case any

    case assertion(_AST.AssertionKind)
    case backreference(_AST.Reference)
    case symbolicReference(ReferenceID)

    case changeMatchingOptions(_AST.MatchingOptionSequence)

    case unconverted(_AST.Atom)
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

    case .trivia, .empty, .quotedLiteral, .regexLiteral,
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
    case let .regexLiteral(literal):             return literal.ast
    case let .convertedRegexLiteral(_, literal): return literal.ast
    default: return nil
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
    case let .regexLiteral(re):
      return re.ast.hasCapture
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

// MARK: AST wrapper types
//
// These wrapper types are required because even @_spi-marked public APIs can't
// include symbols from implementation-only dependencies.

extension DSLTree.Node {
  func _addCaptures(
    to list: inout CaptureList,
    optionalNesting nesting: Int
  ) {
    let addOptional = nesting+1
    switch self {
    case let .orderedChoice(children):
      for child in children {
        child._addCaptures(to: &list, optionalNesting: addOptional)
      }

    case let .concatenation(children):
      for child in children {
        child._addCaptures(to: &list, optionalNesting: nesting)
      }

    case let .capture(name, _, child, transform):
      list.append(.init(
        name: name,
        type: transform?.resultType ?? child.wholeMatchType,
        optionalDepth: nesting, .fake))
      child._addCaptures(to: &list, optionalNesting: nesting)

    case let .nonCapturingGroup(kind, child):
      assert(!kind.ast.isCapturing)
      child._addCaptures(to: &list, optionalNesting: nesting)

    case let .conditional(cond, trueBranch, falseBranch):
      switch cond.ast {
      case .group(let g):
        AST.Node.group(g)._addCaptures(to: &list, optionalNesting: nesting)
      default:
        break
      }

      trueBranch._addCaptures(to: &list, optionalNesting: addOptional)
      falseBranch._addCaptures(to: &list, optionalNesting: addOptional)


    case let .quantification(amount, _, child):
      var optNesting = nesting
      if amount.ast.bounds.atLeast == 0 {
        optNesting += 1
      }
      child._addCaptures(to: &list, optionalNesting: optNesting)

    case let .regexLiteral(re):
      return re.ast._addCaptures(to: &list, optionalNesting: nesting)

    case let .absentFunction(abs):
      switch abs.ast.kind {
      case .expression(_, _, let child):
        child._addCaptures(to: &list, optionalNesting: nesting)
      case .clearer, .repeater, .stopper:
        break
      }

    case let .convertedRegexLiteral(n, _):
      return n._addCaptures(to: &list, optionalNesting: nesting)

    case .matcher:
      break

    case .customCharacterClass, .atom, .trivia, .empty,
        .quotedLiteral, .consumer, .characterPredicate:
      break
    }
  }

  /// Returns true if the node is output-forwarding, i.e. not defining its own
  /// output but forwarding its only child's output.
  var isOutputForwarding: Bool {
    switch self {
    case .nonCapturingGroup:
      return true
    case .orderedChoice, .concatenation, .capture,
         .conditional, .quantification, .customCharacterClass, .atom,
         .trivia, .empty, .quotedLiteral, .regexLiteral, .absentFunction,
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

extension DSLTree {
  var captureList: CaptureList {
    var list = CaptureList()
    list.append(.init(type: root.wholeMatchType, optionalDepth: 0, .fake))
    root._addCaptures(to: &list, optionalNesting: 0)
    return list
  }

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

      case .trivia, .empty, .quotedLiteral, .regexLiteral,
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
    public struct AssertionKind {
      internal var ast: AST.Atom.AssertionKind
      
      public static func startOfSubject(_ inverted: Bool = false) -> Self {
        .init(ast: .startOfSubject)
      }
      public static func endOfSubjectBeforeNewline(_ inverted: Bool = false) -> Self {
        .init(ast: .endOfSubjectBeforeNewline)
      }
      public static func endOfSubject(_ inverted: Bool = false) -> Self {
        .init(ast: .endOfSubject)
      }
      public static func firstMatchingPositionInSubject(_ inverted: Bool = false) -> Self {
        .init(ast: .firstMatchingPositionInSubject)
      }
      public static func textSegmentBoundary(_ inverted: Bool = false) -> Self {
        inverted
          ? .init(ast: .notTextSegment)
          : .init(ast: .textSegment)
      }
      public static func startOfLine(_ inverted: Bool = false) -> Self {
        .init(ast: .startOfLine)
      }
      public static func endOfLine(_ inverted: Bool = false) -> Self {
        .init(ast: .endOfLine)
      }
      public static func wordBoundary(_ inverted: Bool = false) -> Self {
        inverted
          ? .init(ast: .notWordBoundary)
          : .init(ast: .wordBoundary)
      }
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
    case .char, .scalar, .any, .backreference, .symbolicReference, .unconverted:
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
