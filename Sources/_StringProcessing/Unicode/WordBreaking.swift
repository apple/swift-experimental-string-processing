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

@_spi(_Unicode)
import Swift

// TODO: Sink onto String
extension Processor {
  func atSimpleBoundary(
    _ usesAsciiWord: Bool,
    _ semanticLevel: MatchingOptions.SemanticLevel
  ) -> Bool {
    func matchesWord(at i: Input.Index) -> Bool {
      switch semanticLevel {
      case .graphemeCluster:
        // TODO: needs benchmark coverage
        let c = input[i]
        return c.isWordCharacter && (c.isASCII || !usesAsciiWord)
      case .unicodeScalar:
        // TODO: needs benchmark coverage
        let c = input.unicodeScalars[i]
        return (c.properties.isAlphabetic || c == "_") && (c.isASCII || !usesAsciiWord)
      }
    }
    
    // FIXME: How should we handle bounds?
    // We probably need two concepts
    if subjectBounds.isEmpty { return false }
    if currentPosition == subjectBounds.lowerBound {
      return matchesWord(at: currentPosition)
    }
    let priorIdx = input.index(before: currentPosition)
    if currentPosition == subjectBounds.upperBound {
      return matchesWord(at: priorIdx)
    }
    
    let prior = matchesWord(at: priorIdx)
    let current = matchesWord(at: currentPosition)
    return prior != current
  }
}

extension String {
  func isOnWordBoundary(
    at i: String.Index,
    using cache: inout Set<String.Index>?,
    _ maxIndex: inout String.Index?
  ) -> Bool {
    // TODO: needs benchmark coverage
    guard i != startIndex, i != endIndex else {
      return true
    }
    
    // If our index is already in our cache, then this is obviously on a
    // boundary.
    if let cache = cache, cache.contains(i) {
      return true
    }
    
    // If its not in the cache AND our max index is larger than our index, it
    // means this index is never on a word boundary in our string. If our index
    // is larger than max index, we may need to still do work to determine if
    // i is on a boundary. If it's equal to max index, then it should've been
    // taken the cache path.
    if let maxIndex = maxIndex, i < maxIndex {
      return false
    }
    
    if #available(SwiftStdlib 5.7, *) {
      var indices: Set<String.Index> = []
      var j = maxIndex ?? startIndex
      
      while j < endIndex, j <= i {
        indices.insert(j)
        j = _wordIndex(after: j)
      }
      
      cache = indices
      maxIndex = j
      
      return indices.contains(i)
    } else {
      return false
    }
  }
}
