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

// A tree representing the type of some captures.
public enum CaptureStructure: Equatable {
  case atom(name: String? = nil, type: AnyType? = nil)
  indirect case optional(CaptureStructure)
  indirect case tuple([CaptureStructure])

  public static func tuple(_ children: CaptureStructure...) -> Self {
    tuple(children)
  }

  public static var empty: Self {
    .tuple([])
  }
}

// TODO: Below are all flattening constructors. Instead create
// a builder/visitor that can store the structuralization
// approach

extension CaptureStructure {
  public struct Constructor {
    var strategy: Strategy

    public init(_ strategy: Strategy = .flatten) {
      guard strategy == .flatten else {
        fatalError("TODO: adjust creator methods")
      }
      self.strategy = strategy
    }
  }
}

extension CaptureStructure.Constructor {
  public mutating func alternating<C: Collection>(
    _ children: C
  ) -> CaptureStructure where C.Element: _TreeNode {
    return children.map {
      $0._captureStructure(&self)
    }.reduce(.empty, +)
     .map(CaptureStructure.optional)
  }
  public mutating func concatenating<C: Collection>(
    _ children: C
  ) -> CaptureStructure where C.Element: _TreeNode {
    return children.map {
      $0._captureStructure(&self)
    }.reduce(.empty, +)
  }

  public mutating func grouping<T: _TreeNode>(
    _ child: T,
    as kind: AST.Group.Kind
  ) -> CaptureStructure {
    switch kind {
    case .capture:
      return capturing(child)
    case .namedCapture(let name):
      return capturing(name: name.value, child)
    case .balancedCapture(let b):
      return capturing(name: b.name?.value, child)
    default:
      precondition(!kind.isCapturing)
      return child._captureStructure(&self)
    }
  }

  public mutating func capturing<T: _TreeNode>(
    name: String? = nil,
    _ child: T,
    withType type: AnyType? = nil
  ) -> CaptureStructure {
    .atom(name: name, type: type)
      + child._captureStructure(&self)
  }

  // TODO: We'll likely want/need a generalization of
  // conditional's condition kind.
  public mutating func condition<T: _TreeNode>(
    _ condition: AST.Conditional.Condition.Kind,
    trueBranch: T,
    falseBranch: T
  ) -> CaptureStructure {
    // A conditional's capture structure is effectively that of an alternation
    // between the true and false branches. However the condition may also
    // have captures in the case of a group condition.
    var captures = CaptureStructure.empty
    switch condition {
    case .group(let g):
      captures = captures + AST.Node.group(g)._captureStructure(&self)
    default:
      break
    }
    let branchCaptures = trueBranch._captureStructure(&self) +
                         falseBranch._captureStructure(&self)
    return captures + branchCaptures.map(CaptureStructure.optional)
  }

  public mutating func quantifying<T: _TreeNode>(
    _ child: T, amount: AST.Quantification.Amount
  ) -> CaptureStructure {
    let result = child._captureStructure(&self)
    return amount.bounds.atLeast == 0
      ? result.map(CaptureStructure.optional) : result
  }

  // TODO: Will need to adjust for DSLTree support, and
  // "absent" isn't the best name for these.
  public mutating func absent(
    _ kind: AST.AbsentFunction.Kind
  ) -> CaptureStructure {
    // Only the child of an expression absent function is relevant, as the
    // other expressions don't actually get matched against.
    switch kind {
    case .expression(_, _, let child):
      return child._captureStructure(&self)
    case .clearer, .repeater, .stopper:
      return .empty
    }
  }

}

extension AST.Node {
  public func _captureStructure(
    _ constructor: inout CaptureStructure.Constructor
  ) -> CaptureStructure {
    guard constructor.strategy == .flatten else {
      fatalError("TODO")
    }

    // Note: This implementation could be more optimized.
    switch self {
    case let .alternation(a):
      return constructor.alternating(a.children)

    case let .concatenation(c):
      return constructor.concatenating(c.children)

    case let .group(g):
      return constructor.grouping(g.child, as: g.kind.value)

    case .conditional(let c):
      return constructor.condition(
        c.condition.kind,
        trueBranch: c.trueBranch,
        falseBranch: c.falseBranch)

    case .quantification(let q):
      return constructor.quantifying(
        q.child, amount: q.amount.value)

    case .absentFunction(let abs):
      return constructor.absent(abs.kind)

    case .quote, .trivia, .atom, .customCharacterClass, .empty:
      return .empty
    }
  }
}

// MARK: - Combination and transformation

extension CaptureStructure {
  /// Returns a capture structure by concatenating any tuples in `self` and
  /// `other`.
  func concatenating(with other: CaptureStructure) -> CaptureStructure {
    switch (self, other) {
    // (T...) + (U...) ==> (T..., U...)
    case let (.tuple(lhs), .tuple(rhs)):
      return .tuple(lhs + rhs)
    // T + () ==> T
    case (_, .tuple(let rhs)) where rhs.isEmpty:
      return self
    // () + T ==> T
    case (.tuple(let lhs), _) where lhs.isEmpty:
      return other
    // (T...) + U ==> (T..., U)
    case let (.tuple(lhs), _):
      return .tuple(lhs + [other])
    // T + (U...) ==> (T, U...)
    case let (_, .tuple(rhs)):
      return .tuple([self] + rhs)
    // T + U ==> (T, U)
    default:
      return .tuple([self, other])
    }
  }

  static func + (
    lhs: CaptureStructure, rhs: CaptureStructure
  ) -> CaptureStructure {
    lhs.concatenating(with: rhs)
  }

  /// Returns a capture structure by transforming any tuple element of `self`
  /// or transforming `self` directly if it is not a tuple.
  func map(
    _ transform: (CaptureStructure) -> CaptureStructure
  ) -> CaptureStructure {
    if case .tuple(let children) = self {
      return .tuple(children.map(transform))
    }
    return transform(self)
  }
}

// MARK: - Common properties

extension CaptureStructure {
  /// Returns a Boolean indicating whether the structure does not contain any
  /// captures.
  public var isEmpty: Bool {
    if case .tuple(let elements) = self, elements.isEmpty {
      return true
    }
    return false
  }

  public func type(withAtomType atomType: Any.Type) -> Any.Type {
    switch self {
    case .atom(_, type: nil):
      return atomType
    case .atom(_, type: let type?):
      return type.base
    case .optional(let child):
      return TypeConstruction.optionalType(of: child.type(withAtomType: atomType))
    case .tuple(let children):
      return TypeConstruction.tupleType(of: children.map {
        $0.type(withAtomType: atomType)
      })
    }
  }

  public typealias DefaultAtomType = Substring

  public var type: Any.Type {
    type(withAtomType: DefaultAtomType.self)
  }

  public var atomType: AnyType {
    switch self {
    case .atom(_, type: nil):
      return .init(Substring.self)
    case .atom(_, type: let type?):
      return type
    case .optional(let child):
      return child.atomType
    case .tuple:
      fatalError("Recursive nesting has no single atom type")
    }

  }
}

// MARK: - Serialization

extension CaptureStructure {
  /// A byte-sized serialization code.
  private enum Code: UInt8 {
    case end           = 0
    case atom          = 1
    case namedAtom     = 2
//    case formArray     = 3
    case formOptional  = 4
    case beginTuple    = 5
    case endTuple      = 6
  }

  private typealias SerializationVersion = UInt16
  private static let currentSerializationVersion: SerializationVersion = 1

  public static func serializationBufferSize(
    forInputUTF8CodeUnitCount inputUTF8CodeUnitCount: Int
  ) -> Int {
    MemoryLayout<SerializationVersion>.stride + inputUTF8CodeUnitCount + 1
  }

  /// Encodes the capture structure to the given buffer as a serialized
  /// representation.
  ///
  /// The encoding rules are as follows:
  ///
  /// ```
  /// encode(〚`T`〛) ==> <version>, 〚`T`〛, .end
  /// 〚`T` (atom)〛 ==> .atom
  /// 〚`name: T` (atom)〛 ==> .atom, `name`, '\0'
  /// 〚`T?`〛 ==> 〚`T`〛, .formOptional
  /// 〚`(T0, T1, ...)` (top level)〛 ==> 〚`T0`〛, 〚`T1`〛, ...
  /// 〚`(T0, T1, ...)`〛 ==> .beginTuple, 〚`T0`〛, 〚`T1`〛, ..., .endTuple
  /// ```
  ///
  /// - Parameter buffer: A buffer whose byte count is at least the byte count
  ///   of the regular expression string that produced this capture structure.
  public func encode(to buffer: UnsafeMutableRawBufferPointer) {
    assert(!buffer.isEmpty, "Buffer must not be empty")
    assert(
      buffer.count >=
        MemoryLayout<SerializationVersion>.stride + MemoryLayout<Code>.stride)
    // Encode version (unaligned store).
    withUnsafeBytes(of: Self.currentSerializationVersion) {
      buffer.copyMemory(from: $0)
    }
    // Encode contents.
    var offset = MemoryLayout<SerializationVersion>.stride
    /// Appends a code to the buffer, advancing the offset to the next position.
    func append(_ code: Code) {
      buffer.storeBytes(
        of: code.rawValue, toByteOffset: offset, as: UInt8.self)
      offset += MemoryLayout<Code>.stride
    }
    /// Recursively encode the node to the buffer.
    func encode(_ node: CaptureStructure, isTopLevel: Bool = false) {
      switch node {
      // 〚`T` (atom)〛 ==> .atom
      case .atom(name: nil, type: nil):
        append(.atom)
      // 〚`name: T` (atom)〛 ==> .atom, `name`, '\0'
      case .atom(name: let name?, type: nil):
        append(.namedAtom)
        let nameCString = name.utf8CString
        let nameSlot = UnsafeMutableRawBufferPointer(
          rebasing: buffer[offset ..< offset+nameCString.count])
        nameCString.withUnsafeBytes(nameSlot.copyMemory(from:))
        offset += nameCString.count
      case .atom(_, _?):
        fatalError("Cannot encode a capture structure with explicit types")
      // 〚`T?`〛 ==> 〚`T`〛, .formOptional
      case .optional(let child):
        encode(child)
        append(.formOptional)
      // 〚`(T0, T1, ...)` (top level)〛 ==> 〚`T0`〛, 〚`T1`〛, ...
      // 〚`(T0, T1, ...)`〛 ==> .beginTuple, 〚`T0`〛, 〚`T1`〛, ..., .endTuple
      case .tuple(let children):
        if !isTopLevel {
          append(.beginTuple)
        }
        for child in children {
          encode(child)
        }
        if !isTopLevel {
          append(.endTuple)
        }
      }
    }
    if !isEmpty {
      encode(self, isTopLevel: true)
    }
    append(.end)
  }

  /// Creates a capture structure by decoding a serialized representation from
  /// the given buffer.
  public init?(decoding buffer: UnsafeRawBufferPointer) {
    var scopes: [[CaptureStructure]] = [[]]
    var currentScope: [CaptureStructure] {
      get { scopes[scopes.endIndex - 1] }
      _modify { yield &scopes[scopes.endIndex - 1] }
    }
    // Decode version.
    let version = buffer.load(as: SerializationVersion.self)
    guard version == Self.currentSerializationVersion else {
      return nil
    }
    // Decode contents.
    var offset = MemoryLayout<SerializationVersion>.stride
    /// Returns the next code in the buffer, or nil if the memory does not
    /// contain a valid code.
    func nextCode() -> Code? {
      defer { offset += MemoryLayout<Code>.stride }
      let rawValue = buffer.load(fromByteOffset: offset, as: Code.RawValue.self)
      return Code(rawValue: rawValue)
    }
    repeat {
      guard let code = nextCode() else {
        return nil
      }
      switch code {
      case .end:
        offset = buffer.endIndex
      case .atom:
        currentScope.append(.atom())
      case .namedAtom:
        let stringAddress = buffer.baseAddress.unsafelyUnwrapped
          .advanced(by: offset)
          .assumingMemoryBound(to: CChar.self)
        let name = String(cString: stringAddress)
        offset += name.utf8CString.count
        currentScope.append(.atom(name: name))
      case .formOptional:
        let lastIndex = currentScope.endIndex - 1
        currentScope[lastIndex] = .optional(currentScope[lastIndex])
      case .beginTuple:
        scopes.append([])
      case .endTuple:
        let lastScope = scopes.removeLast()
        currentScope.append(.tuple(lastScope))
      }
    } while offset < buffer.endIndex
    guard scopes.count == 1 else {
      return nil // Malformed serialization.
    }
    self = currentScope.count == 1 ? currentScope[0] : .tuple(currentScope)
  }
}

extension CaptureStructure: CustomStringConvertible {
  public var description: String {
    var printer = PrettyPrinter()
    _print(&printer)
    return printer.finish()
  }

  private func _print(_ printer: inout PrettyPrinter) {
    switch self {
    case let .atom(name, type):
      let name = name ?? "<unnamed>"
      let type = type == nil ? "<untyped>"
                             : String(describing: type)
      printer.print("Atom(\(name): \(type))")

    case let .optional(c):
      printer.printBlock("Optional") { printer in
        c._print(&printer)
      }

    case let .tuple(cs):
      printer.printBlock("Tuple") { printer in
        for c in cs {
          c._print(&printer)
        }
      }

    }
  }
}

extension CaptureStructure.Constructor {
  public enum Strategy {
    case flatten
    case nest
    // case drop(after: Int)...
  }
}
