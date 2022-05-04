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

// MARK: `CollectionConsumer` algorithms

extension Collection {
  func starts<C: CollectionConsumer>(with consumer: C) -> Bool
    where C.Consumed == SubSequence
  {
    consumer.consuming(self[...]) != nil
  }
}

extension BidirectionalCollection {
  func ends<C: BidirectionalCollectionConsumer>(with consumer: C) -> Bool
    where C.Consumed == SubSequence
  {
    consumer.consumingBack(self[...]) != nil
  }
}

// MARK: Fixed pattern algorithms

extension Collection where Element: Equatable {
  func starts<C: Collection>(with prefix: C) -> Bool
    where C.Element == Element
  {
    starts(with: FixedPatternConsumer(pattern: prefix))
  }
}

extension BidirectionalCollection where Element: Equatable {
  func ends<C: BidirectionalCollection>(with suffix: C) -> Bool
    where C.Element == Element
  {
    ends(with: FixedPatternConsumer(pattern: suffix))
  }
}

// MARK: Regex algorithms

@available(SwiftStdlib 5.7, *)
extension BidirectionalCollection where SubSequence == Substring {
  /// Returns a Boolean value indicating whether the initial elements of the
  /// sequence are the same as the elements in the specified regex.
  ///
  /// - Parameter regex: A regex to compare to this sequence.
  /// - Returns: `true` if the initial elements of the sequence matches the
  ///   beginning of `regex`; otherwise, `false`.
  public func starts<R: RegexComponent>(with regex: R) -> Bool {
    starts(with: RegexConsumer(regex))
  }
  
  func ends<R: RegexComponent>(with regex: R) -> Bool {
    ends(with: RegexConsumer(regex))
  }
}
