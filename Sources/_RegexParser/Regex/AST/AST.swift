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

/// A regex abstract syntax tree.
///
/// This is a top-level type that stores the root node.
public struct AST: Hashable {
  public var root: AST.Node
  public var globalOptions: GlobalMatchingOptionSequence?

  public init(_ root: AST.Node, globalOptions: GlobalMatchingOptionSequence?) {
    self.root = root
    self.globalOptions = globalOptions
  }
}

extension AST {
  /// Whether this AST tree contains at least one capture nested inside of it.
  public var hasCapture: Bool { root.hasCapture }

  /// The capture structure of this AST tree.
  public var captureStructure: CaptureStructure {
    var constructor = CaptureStructure.Constructor(.flatten)
    return root._captureStructure(&constructor)
  }
}

extension AST {
  /// A node in the regex AST.
  @frozen
  public indirect enum Node:
    Hashable, _TreeNode //, _ASTPrintable ASTValue, ASTAction
  {
    /// ... | ... | ...
    case alternation(Alternation)

    /// ... ...
    case concatenation(Concatenation)

    /// (...)
    case group(Group)

    /// (?(cond) true-branch | false-branch)
    case conditional(Conditional)

    case quantification(Quantification)

    /// \Q...\E
    case quote(Quote)

    /// Comments, non-semantic whitespace, etc
    case trivia(Trivia)

    case atom(Atom)

    case customCharacterClass(CustomCharacterClass)

    case absentFunction(AbsentFunction)

    case empty(Empty)
  }
}

extension AST.Node {
  // :-(
  //
  // Existential-based programming is highly prone to silent
  // errors, but it does enable us to avoid having to switch
  // over `self` _everywhere_ we want to do anything.
  var _associatedValue: _ASTNode {
    switch self {
    case let .alternation(v):           return v
    case let .concatenation(v):         return v
    case let .group(v):                 return v
    case let .conditional(v):           return v
    case let .quantification(v):        return v
    case let .quote(v):                 return v
    case let .trivia(v):                return v
    case let .atom(v):                  return v
    case let .customCharacterClass(v):  return v
    case let .empty(v):                 return v
    case let .absentFunction(v):        return v
    }
  }

  public func `as`<T: _ASTNode>(_ t: T.Type = T.self) -> T? {
    _associatedValue as? T
  }

  /// The child nodes of this node.
  ///
  /// If the node isn't a parent node, this value is `nil`.
  public var children: [AST.Node]? {
    return (_associatedValue as? _ASTParent)?.children
  }

  public var location: SourceLocation {
    _associatedValue.location
  }

  /// Whether this node is trivia or non-semantic, like comments.
  public var isTrivia: Bool {
    switch self {
    case .trivia: return true
    default: return false
    }
  }

  /// Whether this node contains at least one capture nested inside of it.
  public var hasCapture: Bool {
    switch self {
    case .group(let g) where g.kind.value.isCapturing:
      return true
    default:
      break
    }
    return self.children?.any(\.hasCapture) ?? false
  }

  /// Whether this node may be used as the operand of a quantifier such as
  /// `?`, `+` or `*`.
  public var isQuantifiable: Bool {
    switch self {
    case .atom(let a):
      return a.isQuantifiable
    case .group, .conditional, .customCharacterClass, .absentFunction:
      return true
    case .alternation, .concatenation, .quantification, .quote, .trivia,
        .empty:
      return false
    }
  }
}

// MARK: - AST types

extension AST {

  public struct Alternation: Hashable, _ASTNode {
    public let children: [AST.Node]
    public let pipes: [SourceLocation]

    public init(_ mems: [AST.Node], pipes: [SourceLocation]) {
      // An alternation must have at least two branches (though the branches
      // may be empty AST nodes), and n - 1 pipes.
      precondition(mems.count >= 2)
      precondition(pipes.count == mems.count - 1)

      self.children = mems
      self.pipes = pipes
    }

    public var location: SourceLocation {
      .init(children.first!.location.start ..< children.last!.location.end)
    }
  }

  public struct Concatenation: Hashable, _ASTNode {
    public let children: [AST.Node]
    public let location: SourceLocation

    public init(_ mems: [AST.Node], _ location: SourceLocation) {
      self.children = mems
      self.location = location
    }
  }

  public struct Quote: Hashable, _ASTNode {
    public let literal: String
    public let location: SourceLocation

    public init(_ s: String, _ location: SourceLocation) {
      self.literal = s
      self.location = location
    }
  }

  public struct Trivia: Hashable, _ASTNode {
    public let contents: String
    public let location: SourceLocation

    public init(_ s: String, _ location: SourceLocation) {
      self.contents = s
      self.location = location
    }

    init(_ v: Located<String>) {
      self.contents = v.value
      self.location = v.location
    }
  }

  public struct Empty: Hashable, _ASTNode {
    public let location: SourceLocation

    public init(_ location: SourceLocation) {
      self.location = location
    }
  }

  /// An Oniguruma absent function.
  ///
  /// This is used to model a pattern which should
  /// not be matched against across varying scopes.
  public struct AbsentFunction: Hashable, _ASTNode {
    public enum Start: Hashable {
      /// `(?~|`
      case withPipe

      /// `(?~`
      case withoutPipe
    }
    public enum Kind: Hashable {
      /// An absent repeater `(?~absent)`. This is equivalent to `(?~|absent|.*)`
      /// and therefore matches as long as the pattern `absent` is not matched.
      case repeater(AST.Node)

      /// An absent expression `(?~|absent|expr)`, which defines an `absent`
      /// pattern which must not be matched against while the pattern `expr` is
      /// matched.
      case expression(absentee: AST.Node, pipe: SourceLocation, expr: AST.Node)

      /// An absent stopper `(?~|absent)`, which prevents matching against
      /// `absent` until the end of the regex, or until it is cleared.
      case stopper(AST.Node)

      /// An absent clearer `(?~|)` which cancels the effect of an absent
      /// stopper.
      case clearer
    }
    /// The location of `(?~` or `(?~|`
    public var start: SourceLocation

    public var kind: Kind

    public var location: SourceLocation

    public init(
      _ kind: Kind, start: SourceLocation, location: SourceLocation
    ) {
      self.kind = kind
      self.start = start
      self.location = location
    }
  }

  public struct Reference: Hashable {
    @frozen
    public enum Kind: Hashable {
      // \n \gn \g{n} \g<n> \g'n' (?n) (?(n)...
      // Oniguruma: \k<n>, \k'n'
      case absolute(Int)

      // \g{-n} \g<+n> \g'+n' \g<-n> \g'-n' (?+n) (?-n)
      // (?(+n)... (?(-n)...
      // Oniguruma: \k<-n> \k<+n> \k'-n' \k'+n'
      case relative(Int)

      // \k<name> \k'name' \g{name} \k{name} (?P=name)
      // \g<name> \g'name' (?&name) (?P>name)
      // (?(<name>)... (?('name')... (?(name)...
      case named(String)

      /// (?R), (?(R)..., which are equivalent to (?0), (?(0)...
      static var recurseWholePattern: Kind { .absolute(0) }
    }
    public var kind: Kind

    /// An additional specifier supported by Oniguruma that specifies what
    /// recursion level the group being referenced belongs to.
    public var recursionLevel: Located<Int>?

    /// The location of the inner numeric or textual reference, e.g the location
    /// of '-2' in '\g{-2}'. Note this includes the recursion level for e.g
    /// '\k<a+2>'.
    public var innerLoc: SourceLocation

    public init(_ kind: Kind, recursionLevel: Located<Int>? = nil,
                innerLoc: SourceLocation) {
      self.kind = kind
      self.recursionLevel = recursionLevel
      self.innerLoc = innerLoc
    }

    /// Whether this is a reference that recurses the whole pattern, rather than
    /// a group.
    public var recursesWholePattern: Bool { kind == .recurseWholePattern }
  }

  /// A set of global matching options in a regular expression literal.
  public struct GlobalMatchingOptionSequence: Hashable {
    public var options: [AST.GlobalMatchingOption]

    public init?(_ options: [AST.GlobalMatchingOption]) {
      guard !options.isEmpty else { return nil }
      self.options = options
    }

    public var location: SourceLocation {
      options.first!.location.union(with: options.last!.location)
    }
  }
}
