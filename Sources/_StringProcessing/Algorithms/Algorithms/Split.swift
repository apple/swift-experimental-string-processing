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
  var maxSplits: Int
  var omittingEmptySubsequences: Bool

  init(
    ranges: RangesCollection<Searcher>,
    maxSplits: Int,
    omittingEmptySubsequences: Bool)
  {
    self.ranges = ranges
    self.maxSplits = maxSplits
    self.omittingEmptySubsequences = omittingEmptySubsequences
  }

  init(
    base: Base,
    searcher: Searcher,
    maxSplits: Int,
    omittingEmptySubsequences: Bool)
  {
    self.ranges = base._ranges(of: searcher)
    self.maxSplits = maxSplits
    self.omittingEmptySubsequences = omittingEmptySubsequences
  }
}

extension SplitCollection: Sequence {
  public struct Iterator: IteratorProtocol {
    let base: Base
    var index: Base.Index
    var ranges: RangesCollection<Searcher>.Iterator
    var maxSplits: Int
    var omittingEmptySubsequences: Bool

    var splitCounter = 0
    var isDone = false

    init(
      ranges: RangesCollection<Searcher>,
      maxSplits: Int,
      omittingEmptySubsequences: Bool
    ) {
      self.base = ranges.base
      self.index = base.startIndex
      self.ranges = ranges.makeIterator()
      self.maxSplits = maxSplits
      self.omittingEmptySubsequences = omittingEmptySubsequences
    }
    
    public mutating func next() -> Base.SubSequence? {
      guard !isDone else { return nil }
      
      /// Return the rest of base if it's non-empty or we're including
      /// empty subsequences.
      func finish() -> Base.SubSequence? {
        isDone = true
        return index == base.endIndex && omittingEmptySubsequences
          ? nil
          : base[index...]
      }
      
      if index == base.endIndex {
        return finish()
      }
      
      if splitCounter >= maxSplits {
        return finish()
      }
      
      while true {
        // If there are no more ranges that matched, return the rest of `base`.
        guard let range = ranges.next() else {
          return finish()
        }
        
        defer { index = range.upperBound }

        if omittingEmptySubsequences && index == range.lowerBound {
          continue
        }
        
        splitCounter += 1
        return base[index..<range.lowerBound]
      }
    }
  }
  
  public func makeIterator() -> Iterator {
    Iterator(ranges: ranges, maxSplits: maxSplits, omittingEmptySubsequences: omittingEmptySubsequences)
  }
}

// MARK: `CollectionSearcher` algorithms

extension Collection {
  func split<Searcher: CollectionSearcher>(
    by separator: Searcher,
    maxSplits: Int,
    omittingEmptySubsequences: Bool
  ) -> SplitCollection<Searcher> where Searcher.Searched == Self {
    SplitCollection(
      base: self,
      searcher: separator,
      maxSplits: maxSplits,
      omittingEmptySubsequences: omittingEmptySubsequences)
  }
}

// MARK: Fixed pattern algorithms

extension Collection where Element: Equatable {
  @_disfavoredOverload
  func split<C: Collection>(
    by separator: C,
    maxSplits: Int,
    omittingEmptySubsequences: Bool
  ) -> SplitCollection<ZSearcher<Self>> where C.Element == Element {
    split(by: ZSearcher(pattern: Array(separator), by: ==), maxSplits: maxSplits, omittingEmptySubsequences: omittingEmptySubsequences)
  }

  // FIXME: Return `some Collection<SubSequence>` for SE-0346
  /// Returns the longest possible subsequences of the collection, in order,
  /// around elements equal to the given separator.
  ///
  /// - Parameter separator: The element to be split upon.
  /// - Returns: A collection of subsequences, split from this collection's
  ///   elements.
  @_disfavoredOverload
  @available(SwiftStdlib 5.7, *)
  public func split<C: Collection>(
    separator: C,
    maxSplits: Int = .max,
    omittingEmptySubsequences: Bool = true
  ) -> [SubSequence] where C.Element == Element {
    Array(split(
      by: ZSearcher(pattern: Array(separator), by: ==),
      maxSplits: maxSplits,
      omittingEmptySubsequences: omittingEmptySubsequences))
  }
}

// String split overload breakers
//
// These are underscored and marked as SPI so that the *actual* public overloads
// are only visible in RegexBuilder, to avoid breaking source with the
// standard library's function of the same name that takes a `Character`
// as the separator. *Those* overloads are necessary as tie-breakers between
// the Collection-based and Regex-based `split`s, which in turn are both marked
// @_disfavoredOverload to avoid the wrong overload being selected when a
// collection's element type could be used interchangably with a collection of
// that element (e.g. `Array<OptionSet>.split(separator: [])`).

extension StringProtocol where SubSequence == Substring {
  @_spi(RegexBuilder)
  @available(SwiftStdlib 5.7, *)
  public func _split(
    separator: String,
    maxSplits: Int = .max,
    omittingEmptySubsequences: Bool = true
  ) -> [Substring] {
    Array(split(
      by: ZSearcher(pattern: Array(separator), by: ==),
      maxSplits: maxSplits,
      omittingEmptySubsequences: omittingEmptySubsequences))
  }
  
  @_spi(RegexBuilder)
  @available(SwiftStdlib 5.7, *)
  public func _split(
    separator: Substring,
    maxSplits: Int = .max,
    omittingEmptySubsequences: Bool = true
  ) -> [Substring] {
    Array(split(
      by: ZSearcher(pattern: Array(separator), by: ==),
      maxSplits: maxSplits,
      omittingEmptySubsequences: omittingEmptySubsequences))
  }
}

// MARK: Regex algorithms

@available(SwiftStdlib 5.7, *)
extension BidirectionalCollection where SubSequence == Substring {
  // TODO: Is this @_disfavoredOverload necessary?
  // It prevents split(separator: String) from choosing this overload instead
  // of the collection-based version when String has RegexComponent conformance

  // FIXME: Return `some Collection<Subsequence>` for SE-0346
  /// Returns the longest possible subsequences of the collection, in order,
  /// around elements equal to the given separator.
  ///
  /// - Parameter separator: A regex describing elements to be split upon.
  /// - Returns: A collection of substrings, split from this collection's
  ///   elements.
  @_disfavoredOverload
  public func split(
    separator: some RegexComponent,
    maxSplits: Int = .max,
    omittingEmptySubsequences: Bool = true
  ) -> [SubSequence] {
    var result: [SubSequence] = []
    var subSequenceStart = startIndex
    
    func appendSubsequence(end: Index) -> Bool {
      if subSequenceStart == end && omittingEmptySubsequences {
        return false
      }
      result.append(self[subSequenceStart..<end])
      return true
    }
    
    guard maxSplits > 0 && !isEmpty else {
      _ = appendSubsequence(end: endIndex)
      return result
    }

    for match in _matches(of: separator) {
      defer { subSequenceStart = match.range.upperBound }
      let didAppend = appendSubsequence(end: match.range.lowerBound)
      if didAppend && result.count == maxSplits {
        break
      }
    }
    
    if subSequenceStart != endIndex || !omittingEmptySubsequences {
      result.append(self[subSequenceStart..<endIndex])
    }
    
    return result
  }
}
