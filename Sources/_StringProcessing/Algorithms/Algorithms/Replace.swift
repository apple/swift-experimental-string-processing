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

extension Substring {
  func _replacingSubstring(
    _ other: Substring,
    with replacement: Substring,
    maxReplacements: Int = .max
  ) -> String {
    precondition(maxReplacements >= 0)
    
    var result = String()
    var index = startIndex
    
    // `maxRanges` is a workaround for https://github.com/apple/swift/issues/59522
    var rangeIterator = SubstringSearcher(text: self, pattern: other)
    var replacementCount = 0
    while let range = rangeIterator.next() {
      result.append(contentsOf: self[index..<range.lowerBound])
      result.append(contentsOf: replacement)
      index = range.upperBound
      
      replacementCount += 1
      if replacementCount == maxReplacements { break }
    }
    
    result.append(contentsOf: self[index...])
    return result
  }
}

extension RangeReplaceableCollection {
  func _replacing<Ranges: Collection, Replacement: Collection>(
    _ ranges: Ranges,
    with replacement: Replacement,
    maxReplacements: Int = .max
  ) -> Self where Ranges.Element == Range<Index>,
                  Replacement.Element == Element
  {
    precondition(maxReplacements >= 0)
    
    var result = Self()
    var index = startIndex
    
    // `maxRanges` is a workaround for https://github.com/apple/swift/issues/59522
    let maxRanges = ranges.prefix(maxReplacements)
    for range in maxRanges {
      result.append(contentsOf: self[index..<range.lowerBound])
      result.append(contentsOf: replacement)
      index = range.upperBound
    }
    
    result.append(contentsOf: self[index...])
    return result
  }
}

// MARK: Fixed pattern algorithms

extension RangeReplaceableCollection where Element: Equatable {
  /// Returns a new collection in which all occurrences of a target sequence
  /// are replaced by another collection.
  /// - Parameters:
  ///   - other: The sequence to replace.
  ///   - replacement: The new elements to add to the collection.
  ///   - subrange: The range in the collection in which to search for `other`.
  ///   - maxReplacements: A number specifying how many occurrences of `other`
  ///   to replace. Default is `Int.max`.
  /// - Returns: A new collection in which all occurrences of `other` in
  /// `subrange` of the collection are replaced by `replacement`.
  @available(SwiftStdlib 5.7, *)
  public func replacing<C: Collection, Replacement: Collection>(
    _ other: C,
    with replacement: Replacement,
    subrange: Range<Index>,
    maxReplacements: Int = .max
  ) -> Self where C.Element == Element, Replacement.Element == Element {
    switch (self, other, replacement) {
    case (let str as String, let other as String, let repl as String):
      return str[...]._replacingSubstring(other[...], with: repl[...],
                                maxReplacements: maxReplacements) as! Self
    case (let str as Substring, let other as Substring, let repl as Substring):
      return str._replacingSubstring(other, with: repl,
                                maxReplacements: maxReplacements) as! Self

    case (let str as Substring, let other as String, let repl as String):
      return str[...]._replacingSubstring(other[...], with: repl[...],
                                maxReplacements: maxReplacements) as! Self
    case (let str as String, let other as Substring, let repl as String):
      return str[...]._replacingSubstring(other[...], with: repl[...],
                                maxReplacements: maxReplacements) as! Self
    case (let str as String, let other as String, let repl as Substring):
      return str[...]._replacingSubstring(other[...], with: repl[...],
                                maxReplacements: maxReplacements) as! Self

    case (let str as String, let other as Substring, let repl as Substring):
      return str[...]._replacingSubstring(other[...], with: repl[...],
                                maxReplacements: maxReplacements) as! Self
    case (let str as Substring, let other as String, let repl as Substring):
      return str[...]._replacingSubstring(other[...], with: repl[...],
                                maxReplacements: maxReplacements) as! Self
    case (let str as Substring, let other as Substring, let repl as String):
      return str[...]._replacingSubstring(other[...], with: repl[...],
                                maxReplacements: maxReplacements) as! Self

    default:
      return _replacing(
        self[subrange]._ranges(of: other),
        with: replacement,
        maxReplacements: maxReplacements)
    }
  }

  /// Returns a new collection in which all occurrences of a target sequence
  /// are replaced by another collection.
  /// - Parameters:
  ///   - other: The sequence to replace.
  ///   - replacement: The new elements to add to the collection.
  ///   - maxReplacements: A number specifying how many occurrences of `other`
  ///   to replace. Default is `Int.max`.
  /// - Returns: A new collection in which all occurrences of `other` in
  /// `subrange` of the collection are replaced by `replacement`.
  @available(SwiftStdlib 5.7, *)
  public func replacing<C: Collection, Replacement: Collection>(
    _ other: C,
    with replacement: Replacement,
    maxReplacements: Int = .max
  ) -> Self where C.Element == Element, Replacement.Element == Element {
    replacing(
      other,
      with: replacement,
      subrange: startIndex..<endIndex,
      maxReplacements: maxReplacements)
  }

  /// Replaces all occurrences of a target sequence with a given collection
  /// - Parameters:
  ///   - other: The sequence to replace.
  ///   - replacement: The new elements to add to the collection.
  ///   - maxReplacements: A number specifying how many occurrences of `other`
  ///   to replace. Default is `Int.max`.
  @available(SwiftStdlib 5.7, *)
  public mutating func replace<C: Collection, Replacement: Collection>(
    _ other: C,
    with replacement: Replacement,
    maxReplacements: Int = .max
  ) where C.Element == Element, Replacement.Element == Element {
    self = replacing(
      other,
      with: replacement,
      subrange: startIndex..<endIndex,
      maxReplacements: maxReplacements)
  }
}

extension RangeReplaceableCollection
  where Self: BidirectionalCollection, Element: Comparable
{
  func _replacing<C: Collection, Replacement: Collection>(
    _ other: C,
    with replacement: Replacement,
    subrange: Range<Index>,
    maxReplacements: Int = .max
  ) -> Self where C.Element == Element, Replacement.Element == Element {
    _replacing(
      self[subrange]._ranges(of: other),
      with: replacement,
      maxReplacements: maxReplacements)
  }
      
  func _replacing<C: Collection, Replacement: Collection>(
    _ other: C,
    with replacement: Replacement,
    maxReplacements: Int = .max
  ) -> Self where C.Element == Element, Replacement.Element == Element {
    _replacing(
      other,
      with: replacement,
      subrange: startIndex..<endIndex,
      maxReplacements: maxReplacements)
  }
  
  mutating func _replace<C: Collection, Replacement: Collection>(
    _ other: C,
    with replacement: Replacement,
    maxReplacements: Int = .max
  ) where C.Element == Element, Replacement.Element == Element {
    self = _replacing(
      other,
      with: replacement,
      subrange: startIndex..<endIndex,
      maxReplacements: maxReplacements)
  }
}

// MARK: Regex algorithms

extension RangeReplaceableCollection where SubSequence == Substring {
  /// Returns a new collection in which all occurrences of a sequence matching
  /// the given regex are replaced by another collection.
  /// - Parameters:
  ///   - regex: A regex describing the sequence to replace.
  ///   - replacement: The new elements to add to the collection.
  ///   - subrange: The range in the collection in which to search for `regex`.
  ///   - maxReplacements: A number specifying how many occurrences of the
  ///   sequence matching `regex` to replace. Default is `Int.max`.
  /// - Returns: A new collection in which all occurrences of subsequence
  /// matching `regex` in `subrange` are replaced by `replacement`.
  @available(SwiftStdlib 5.7, *)
  public func replacing<Replacement: Collection>(
    _ regex: some RegexComponent,
    with replacement: Replacement,
    subrange: Range<Index>,
    maxReplacements: Int = .max
  ) -> Self where Replacement.Element == Element {
    _replacing(
      self._ranges(
        of: regex,
        subjectBounds: startIndex..<endIndex,
        searchBounds: subrange),
      with: replacement,
      maxReplacements: maxReplacements)
  }

  /// Returns a new collection in which all occurrences of a sequence matching
  /// the given regex are replaced by another collection.
  /// - Parameters:
  ///   - regex: A regex describing the sequence to replace.
  ///   - replacement: The new elements to add to the collection.
  ///   - maxReplacements: A number specifying how many occurrences of the
  ///   sequence matching `regex` to replace. Default is `Int.max`.
  /// - Returns: A new collection in which all occurrences of subsequence
  /// matching `regex` are replaced by `replacement`.
  @_disfavoredOverload
  @available(SwiftStdlib 5.7, *)
  public func replacing<Replacement: Collection>(
    _ regex: some RegexComponent,
    with replacement: Replacement,
    maxReplacements: Int = .max
  ) -> Self where Replacement.Element == Element {
    replacing(
      regex,
      with: replacement,
      subrange: startIndex..<endIndex,
      maxReplacements: maxReplacements)
  }

  /// Replaces all occurrences of the sequence matching the given regex with
  /// a given collection.
  /// - Parameters:
  ///   - regex: A regex describing the sequence to replace.
  ///   - replacement: The new elements to add to the collection.
  ///   - maxReplacements: A number specifying how many occurrences of the
  ///   sequence matching `regex` to replace. Default is `Int.max`.
  @available(SwiftStdlib 5.7, *)
  public mutating func replace<Replacement: Collection>(
    _ regex: some RegexComponent,
    with replacement: Replacement,
    maxReplacements: Int = .max
  ) where Replacement.Element == Element {
    self = replacing(
      regex,
      with: replacement,
      maxReplacements: maxReplacements)
  }
}
