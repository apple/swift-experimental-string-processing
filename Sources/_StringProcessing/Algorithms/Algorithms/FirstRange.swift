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

// MARK: `CollectionSearcher` algorithms

extension Collection {
  func _firstRange<S: CollectionSearcher>(
    of searcher: S
  ) -> Range<Index>? where S.Searched == Self {
    var state = searcher.state(for: self, in: startIndex..<endIndex)
    return searcher.search(self, &state)
  }
}

// MARK: Fixed pattern algorithms
extension Substring {
  @usableFromInline
  func _firstRangeSubstring(
    of other: Substring
  ) -> Range<String.Index>? {
    var searcher = SubstringSearcher(text: self, pattern: other)
    return searcher.next()
  }
}

extension Collection where Element: Equatable {
  @usableFromInline
  func _firstRangeGeneric<C: Collection>(
    of other: C
  ) -> Range<Index>? where C.Element == Element {
    let searcher = ZSearcher<SubSequence>(pattern: Array(other), by: ==)
    return searcher.search(self[...], in: startIndex..<endIndex)
  }

  /// Finds and returns the range of the first occurrence of a given collection
  /// within this collection.
  ///
  /// - Parameter other: The collection to search for.
  /// - Returns: A range in the collection of the first occurrence of `sequence`.
  /// Returns nil if `sequence` is not found.
  @available(SwiftStdlib 5.7, *)
  @inline(__always)
  public func firstRange<C: Collection>(
    of other: C
  ) -> Range<Index>? where C.Element == Element {
    switch (self, other) {
    case (let str as String, let other as String):
      return str[...]._firstRangeSubstring(of: other[...]) as! Range<Index>?
    case (let str as Substring, let other as String):
      return str._firstRangeSubstring(of: other[...]) as! Range<Index>?
    case (let str as String, let other as Substring):
      return str[...]._firstRangeSubstring(of: other) as! Range<Index>?
    case (let str as Substring, let other as Substring):
      return str._firstRangeSubstring(of: other) as! Range<Index>?
      
    default:
      return _firstRangeGeneric(of: other)
    }
  }
}

extension BidirectionalCollection where Element: Comparable {
  /// Finds and returns the range of the first occurrence of a given collection
  /// within this collection.
  ///
  /// - Parameter other: The collection to search for.
  /// - Returns: A range in the collection of the first occurrence of `sequence`.
  /// Returns `nil` if `sequence` is not found.
  @available(SwiftStdlib 5.7, *)
  @inline(__always)
  public func firstRange<C: Collection>(
    of other: C
  ) -> Range<Index>? where C.Element == Element {
    switch (self, other) {
    case (let str as String, let other as String):
      return str[...]._firstRangeSubstring(of: other[...]) as! Range<Index>?
    case (let str as Substring, let other as String):
      return str._firstRangeSubstring(of: other[...]) as! Range<Index>?
    case (let str as String, let other as Substring):
      return str[...]._firstRangeSubstring(of: other) as! Range<Index>?
    case (let str as Substring, let other as Substring):
      return str._firstRangeSubstring(of: other) as! Range<Index>?
      
    default:
      return _firstRangeGeneric(of: other)
    }
  }
}

// MARK: Regex algorithms

extension BidirectionalCollection where SubSequence == Substring {
  /// Finds and returns the range of the first occurrence of a given regex
  /// within the collection.
  /// - Parameter regex: The regex to search for.
  /// - Returns: A range in the collection of the first occurrence of `regex`.
  /// Returns `nil` if `regex` is not found.
  @_disfavoredOverload
  @available(SwiftStdlib 5.7, *)
  public func firstRange(of regex: some RegexComponent) -> Range<Index>? {
    let s = self[...]
    return try? regex.regex.firstMatch(in: s)?.range
  }
}
