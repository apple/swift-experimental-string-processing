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

extension Source {
  /// The location in the input of a parsed entity, presented as a region over the input
  public struct Location: Hashable {
    public var range: Range<Source.Position>

    public var start: Source.Position { range.lowerBound }

    /// The open end
    public var end: Source.Position { range.upperBound }

    public init(_ r: Range<Source.Position>) {
      self.range = r
    }
    public init<R: RangeExpression>(
      _ r: R, in input: Source
    ) where R.Bound == Source.Position {
      self.init(r.relative(to: input.input))
    }
    public init(from sub: Input.SubSequence) {
      self.init(sub.startIndex ..< sub.endIndex)
    }

    /// NOTE: This is a temporary measure to unblock DSL efforts and
    /// incremental source location tracking. This shouldn't be called from
    /// within the parser's module...
    public static var fake: Self {
      .init("".startIndex ..< "".startIndex)
    }
    public var isFake: Bool { self == Self.fake }
    public var isReal: Bool { !isFake }

    /// Whether this location covers an empty range. This includes `isFake`.
    public var isEmpty: Bool { start == end }

    /// Returns the smallest location that contains both this location and
    /// another.
    public func union(with other: Location) -> SourceLocation {
      .init(min(start, other.start) ..< max(end, other.end))
    }
  }
}
public typealias SourceLocation = Source.Location

extension Source {
  var currentPosition: Position { bounds.lowerBound }
}

public protocol LocatedErrorProtocol: Error {
  var location: SourceLocation { get }
  var _typeErasedError: Error { get }
}

extension Source {
  /// An error that includes information about the location in source code.
  public struct LocatedError<E: Error>: Error, LocatedErrorProtocol {
    public let error: E
    public let location: SourceLocation

    init(_ e: E, _ r: SourceLocation) {
      self.error = e
      self.location = r
    }
    public init(_ v: E, _ r: Range<Source.Position>) {
      self.error = v
      self.location = Location(r)
    }
  }

  /// A value wrapped with a source range.
  ///
  /// Note: Source location is part of value identity so that, for example, the
  /// same `Character` value appearing twice can be stored in a data structure
  /// distinctly. To ignore source locations, use `.value` directly.
  public struct Located<T> {
    public var value: T
    public var location: SourceLocation

    public init(_ v: T, _ r: SourceLocation) {
      self.value = v
      self.location = r
    }
    public init(_ v: T, _ r: Range<Source.Position>) {
      self.value = v
      self.location = Location(r)
    }

    /// NOTE: This is a temporary measure to unblock DSL efforts and
    /// incremental source location tracking. This shouldn't be called from
    /// within the parser's module...
    public init(faking v: T) {
      // TODO: any way to assert or guarantee this is called
      // externally?
      self.init(v, .fake)
    }

    public func map<U>(_ fn: (T) throws -> U) rethrows -> Located<U> {
      Located<U>(try fn(value), location)
    }
  }
}
extension AST {
  public typealias Located = Source.Located
}
extension AST.Located: Equatable where T: Equatable {}
extension AST.Located: Hashable where T: Hashable {}

extension Source.LocatedError: CustomStringConvertible {
  public var description: String {
    // Just return the underlying error's description, which is currently how
    // we present the message to the compiler.
    "\(error)"
  }

  public var _typeErasedError: Error {
    return error
  }
}
