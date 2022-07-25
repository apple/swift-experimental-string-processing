//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

extension Array {
  /// Coalesce adjacent elements using a given accumulator. The accumulator is
  /// transformed into elements of the array by `finish`. The `accumulate`
  /// function should return `true` if the accumulator has coalesced the
  /// element, `false` otherwise.
  func coalescing<T>(
    with initialAccumulator: T, into finish: (T) -> Self,
    accumulate: (inout T, Element) -> Bool
  ) -> Self {
    var didAccumulate = false
    var accumulator = initialAccumulator

    var result = Self()
    for elt in self {
      if accumulate(&accumulator, elt) {
        // The element has been coalesced into accumulator, there is nothing
        // else to do.
        didAccumulate = true
        continue
      }
      if didAccumulate {
        // We have a leftover accumulator, which needs to be finished before we
        // can append the next element.
        result += finish(accumulator)
        accumulator = initialAccumulator
        didAccumulate = false
      }
      result.append(elt)
    }
    // Handle a leftover accumulation.
    if didAccumulate {
      result += finish(accumulator)
    }
    return result
  }

  /// Coalesce adjacent elements using a given accumulator. The accumulator is
  /// transformed into an element of the array by `finish`. The `accumulate`
  /// function should return `true` if the accumulator has coalesced the
  /// element, `false` otherwise.
  func coalescing<T>(
    with initialAccumulator: T, into finish: (T) -> Element,
    accumulate: (inout T, Element) -> Bool
  ) -> Self {
    coalescing(
      with: initialAccumulator, into: { [finish($0) ]}, accumulate: accumulate)
  }
}
