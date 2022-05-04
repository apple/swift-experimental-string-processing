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

// MARK: `SplitCollection`

struct SplitCollection<Searcher: CollectionSearcher> {
  public typealias Base = Searcher.Searched
  
  let ranges: RangesCollection<Searcher>
  
  init(ranges: RangesCollection<Searcher>) {
    self.ranges = ranges
  }

  init(base: Base, searcher: Searcher) {
    self.ranges = base.ranges(of: searcher)
  }
}

extension SplitCollection: Sequence {
  public struct Iterator: IteratorProtocol {
    let base: Base
    var index: Base.Index
    var ranges: RangesCollection<Searcher>.Iterator
    var isDone: Bool
    
    init(ranges: RangesCollection<Searcher>) {
      self.base = ranges.base
      self.index = base.startIndex
      self.ranges = ranges.makeIterator()
      self.isDone = false
    }
    
    public mutating func next() -> Base.SubSequence? {
      guard !isDone else { return nil }
      
      guard let range = ranges.next() else {
        isDone = true
        return base[index...]
      }
      
      defer { index = range.upperBound }
      return base[index..<range.lowerBound]
    }
  }
  
  public func makeIterator() -> Iterator {
    Iterator(ranges: ranges)
  }
}

extension SplitCollection: Collection {
  public struct Index {
    var start: Base.Index
    var base: RangesCollection<Searcher>.Index
    var isEndIndex: Bool
  }

  public var startIndex: Index {
    let base = ranges.startIndex
    return Index(start: ranges.base.startIndex, base: base, isEndIndex: false)
  }

  public var endIndex: Index {
    Index(start: ranges.base.endIndex, base: ranges.endIndex, isEndIndex: true)
  }

  public func formIndex(after index: inout Index) {
    guard !index.isEndIndex else { fatalError("Cannot advance past endIndex") }

    if let range = index.base.range {
      let newStart = range.upperBound
      ranges.formIndex(after: &index.base)
      index.start = newStart
    } else {
      index.isEndIndex = true
    }
  }

  public func index(after index: Index) -> Index {
    var index = index
    formIndex(after: &index)
    return index
  }

  public subscript(index: Index) -> Base.SubSequence {
    guard !index.isEndIndex else {
      fatalError("Cannot subscript using endIndex")
    }
    let end = index.base.range?.lowerBound ?? ranges.base.endIndex
    return ranges.base[index.start..<end]
  }
}

extension SplitCollection.Index: Comparable {
   static func == (lhs: Self, rhs: Self) -> Bool {
    switch (lhs.isEndIndex, rhs.isEndIndex) {
    case (false, false):
      return lhs.start == rhs.start
    case (let lhs, let rhs):
      return lhs == rhs
    }
  }

  static func < (lhs: Self, rhs: Self) -> Bool {
    switch (lhs.isEndIndex, rhs.isEndIndex) {
    case (true, _):
      return false
    case (_, true):
      return true
    case (false, false):
      return lhs.start < rhs.start
    }
  }
}

// MARK: `ReversedSplitCollection`

struct ReversedSplitCollection<Searcher: BackwardCollectionSearcher> {
  public typealias Base = Searcher.BackwardSearched
  
  let ranges: ReversedRangesCollection<Searcher>
  
  init(ranges: ReversedRangesCollection<Searcher>) {
    self.ranges = ranges
  }

  init(base: Base, searcher: Searcher) {
    self.ranges = base.rangesFromBack(of: searcher)
  }
}

extension ReversedSplitCollection: Sequence {
  public struct Iterator: IteratorProtocol {
    let base: Base
    var index: Base.Index
    var ranges: ReversedRangesCollection<Searcher>.Iterator
    var isDone: Bool
    
    init(ranges: ReversedRangesCollection<Searcher>) {
      self.base = ranges.base
      self.index = base.endIndex
      self.ranges = ranges.makeIterator()
      self.isDone = false
    }
    
    public mutating func next() -> Base.SubSequence? {
      guard !isDone else { return nil }
      
      guard let range = ranges.next() else {
        isDone = true
        return base[..<index]
      }
      
      defer { index = range.lowerBound }
      return base[range.upperBound..<index]
    }
  }
  
  public func makeIterator() -> Iterator {
    Iterator(ranges: ranges)
  }
}

// TODO: `Collection` conformance

// MARK: `CollectionSearcher` algorithms

extension Collection {
  func split<Searcher: CollectionSearcher>(
    by separator: Searcher
  ) -> SplitCollection<Searcher> where Searcher.Searched == Self {
    // TODO: `maxSplits`, `omittingEmptySubsequences`?
    SplitCollection(base: self, searcher: separator)
  }
}

extension BidirectionalCollection {
  func splitFromBack<Searcher: BackwardCollectionSearcher>(
    by separator: Searcher
  ) -> ReversedSplitCollection<Searcher>
    where Searcher.BackwardSearched == Self
  {
    ReversedSplitCollection(base: self, searcher: separator)
  }
}

// MARK: Predicate algorithms

extension Collection {
  // TODO: Non-escaping and throwing
  func split(
    whereSeparator predicate: @escaping (Element) -> Bool
  ) -> SplitCollection<PredicateConsumer<Self>> {
    split(by: PredicateConsumer(predicate: predicate))
  }
}

extension BidirectionalCollection where Element: Equatable {
  func splitFromBack(
    whereSeparator predicate: @escaping (Element) -> Bool
  ) -> ReversedSplitCollection<PredicateConsumer<Self>> {
    splitFromBack(by: PredicateConsumer(predicate: predicate))
  }
}

// MARK: Single element algorithms

extension Collection where Element: Equatable {
  func split(
    by separator: Element
  ) -> SplitCollection<PredicateConsumer<Self>> {
    split(whereSeparator: { $0 == separator })
  }
}

extension BidirectionalCollection where Element: Equatable {
  func splitFromBack(
    by separator: Element
  ) -> ReversedSplitCollection<PredicateConsumer<Self>> {
    splitFromBack(whereSeparator: { $0 == separator })
  }
}

// MARK: Fixed pattern algorithms

extension Collection where Element: Equatable {
  @_disfavoredOverload
  func split<S: Sequence>(
    by separator: S
  ) -> SplitCollection<ZSearcher<Self>> where S.Element == Element {
    split(by: ZSearcher(pattern: Array(separator), by: ==))
  }

  // FIXME: Return `some Collection<SubSequence>` for SE-0346
  /// Returns the longest possible subsequences of the collection, in order,
  /// around elements equal to the given separator.
  ///
  /// - Parameter separator: The element to be split upon.
  /// - Returns: A collection of subsequences, split from this collection's
  ///   elements.
  @available(SwiftStdlib 5.7, *)
  public func split<S: Sequence>(
    by separator: S
  ) -> [SubSequence] where S.Element == Element {
    Array(split(by: ZSearcher(pattern: Array(separator), by: ==)))
  }
}

extension BidirectionalCollection where Element: Equatable {
  // FIXME
//  public func splitFromBack<S: Sequence>(
//    separator: S
//  ) -> ReversedSplitCollection<ZSearcher<SubSequence>>
//    where S.Element == Element
//  {
//    splitFromBack(separator: ZSearcher(pattern: Array(separator), by: ==))
//  }
}

extension BidirectionalCollection where Element: Comparable {
  func split<S: Sequence>(
    by separator: S
  ) -> SplitCollection<PatternOrEmpty<TwoWaySearcher<Self>>>
    where S.Element == Element
  {
    split(
      by: PatternOrEmpty(searcher: TwoWaySearcher(pattern: Array(separator))))
  }
  
  // FIXME
//  public func splitFromBack<S: Sequence>(
//    separator: S
//  ) -> ReversedSplitCollection<PatternOrEmpty<TwoWaySearcher<SubSequence>>>
//    where S.Element == Element
//  {
//    splitFromBack(separator: PatternOrEmpty(
//      searcher: TwoWaySearcher(pattern: Array(separator))))
//  }
}

// MARK: Regex algorithms

@available(SwiftStdlib 5.7, *)
extension BidirectionalCollection where SubSequence == Substring {
  @_disfavoredOverload
  func split<R: RegexComponent>(
    by separator: R
  ) -> SplitCollection<RegexConsumer<R, Self>> {
    split(by: RegexConsumer(separator))
  }
  
  func splitFromBack<R: RegexComponent>(
    by separator: R
  ) -> ReversedSplitCollection<RegexConsumer<R, Self>> {
    splitFromBack(by: RegexConsumer(separator))
  }

  // FIXME: Return `some Collection<Substring>` for SE-0346 
  /// Returns the longest possible subsequences of the collection, in order,
  /// around elements equal to the given separator.
  ///
  /// - Parameter separator: A regex describing elements to be split upon.
  /// - Returns: A collection of substrings, split from this collection's
  ///   elements.
  public func split<R: RegexComponent>(
    by separator: R
  ) -> [SubSequence] {
    Array(split(by: RegexConsumer(separator)))
  }
}
