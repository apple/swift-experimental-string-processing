public struct SplitCollection<Searcher: CollectionSearcher> {
  public typealias Base = Searcher.Searched
  
  let ranges: RangesCollection<Searcher>
  
  init(ranges: RangesCollection<Searcher>) {
    self.ranges = ranges
  }

  init(base: Base, searcher: Searcher) {
    self.ranges = base.ranges(of: searcher)
  }
}

extension SplitCollection where Searcher: BidirectionalCollectionSearcher {
  public func reversed() -> ReversedSplitCollection<Searcher> {
    ReversedSplitCollection(ranges: ranges.reversed())
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
    guard !index.isEndIndex else { fatalError("Cannot subscript using endIndex") }
    let end = index.base.range?.lowerBound ?? ranges.base.endIndex
    return ranges.base[index.start..<end]
  }
}

extension SplitCollection.Index: Comparable {
  public static func == (lhs: Self, rhs: Self) -> Bool {
    switch (lhs.isEndIndex, rhs.isEndIndex) {
    case (false, false):
      return lhs.start == rhs.start
    case (let lhs, let rhs):
      return lhs == rhs
    }
  }

  public static func < (lhs: Self, rhs: Self) -> Bool {
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

public struct ReversedSplitCollection<Searcher: BackwardCollectionSearcher> {
  public typealias Base = Searcher.Searched
  
  let ranges: ReversedRangesCollection<Searcher>
  
  init(ranges: ReversedRangesCollection<Searcher>) {
    self.ranges = ranges
  }

  init(base: Base, searcher: Searcher) {
    self.ranges = base.rangesFromBack(of: searcher)
  }
}

extension ReversedSplitCollection where Searcher: BidirectionalCollectionSearcher {
  public func reversed() -> SplitCollection<Searcher> {
    SplitCollection(ranges: ranges.reversed())
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

extension Collection {
  public func split<Searcher: CollectionSearcher>(
    separator: Searcher
  ) -> SplitCollection<Searcher> where Searcher.Searched == SubSequence {
    // TODO: `maxSplits`, `omittingEmptySubsequences`?
    SplitCollection(base: self[...], searcher: separator)
  }
}

extension BidirectionalCollection {
  public func splitFromBack<Searcher: BackwardCollectionSearcher>(
    separator: Searcher
  ) -> ReversedSplitCollection<Searcher> where Searcher.Searched == SubSequence {
    ReversedSplitCollection(base: self[...], searcher: separator)
  }
}

extension Collection where Element: Equatable {
  public func split<S: Sequence>(
    separator: S
  ) -> SplitCollection<PatternOrEmpty<ZSearcher<SubSequence>>> where S.Element == Element {
    let pattern = Array(separator)
    let searcher = pattern.isEmpty ? nil : ZSearcher<SubSequence>(pattern: pattern, by: ==)
    return split(separator: PatternOrEmpty(searcher: searcher))
  }
}

extension BidirectionalCollection where Element: Comparable {
  public func split<S: Sequence>(
    separator: S
  ) -> SplitCollection<PatternOrEmpty<TwoWaySearcher<SubSequence>>> where S.Element == Element {
    split(separator: PatternOrEmpty(searcher: TwoWaySearcher(pattern: Array(separator))))
  }
}

// MARK: Regex

extension Collection where SubSequence == Substring {
  public func split(separator: Regex) -> SplitCollection<RegexConsumer> {
    split(separator: RegexConsumer(separator))
  }
}
