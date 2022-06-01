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

@_implementationOnly import _RegexParser

// TODO: Where should this live? Inside TypeConstruction?
func constructExistentialOutputComponent(
  from input: Substring,
  in range: Range<String.Index>?,
  value: Any?,
  optionalCount: Int
) -> Any {
  let someCount: Int
  var underlying: Any
  if let v = value {
    underlying = v
    someCount = optionalCount
  } else if let r = range {
    underlying = input[r]
    someCount = optionalCount
  } else {
    // Ok since we Any-box every step up the ladder
    underlying = Optional<Any>(nil) as Any
    someCount = optionalCount - 1
  }
  for _ in 0..<someCount {
    func wrap<T>(_ x: T) {
      underlying = Optional(x) as Any
    }
    _openExistential(underlying, do: wrap)
  }
  return underlying
}

@available(SwiftStdlib 5.7, *)
extension AnyRegexOutput.Element {
  func existentialOutputComponent(
    from input: Substring
  ) -> Any {
    constructExistentialOutputComponent(
      from: input,
      in: range,
      value: value,
      optionalCount: representation.optionalDepth
    )
  }

  func slice(from input: String) -> Substring? {
    guard let r = range else { return nil }
    return input[r]
  }
}

@available(SwiftStdlib 5.7, *)
extension Sequence where Element == AnyRegexOutput.Element {
  // FIXME: This is a stop gap where we still slice the input
  // and traffic through existentials
  @available(SwiftStdlib 5.7, *)
  func existentialOutput(
    from input: Substring
  ) -> Any {
    var caps = Array<Any>()
    caps.append(input)
    caps.append(contentsOf: self.map {
      $0.existentialOutputComponent(from: input)
    })
    
    if caps.count == 1 {
      return input
    }
    
    return TypeConstruction.tuple(of: caps)
  }

  func slices(from input: String) -> [Substring?] {
    self.map { $0.slice(from: input) }
  }
}
