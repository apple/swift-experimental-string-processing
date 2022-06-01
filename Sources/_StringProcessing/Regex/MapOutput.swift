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

@available(SwiftStdlib 5.7, *)
extension Regex {
  @available(SwiftStdlib 5.7, *)
  public func mapOutput<NewOutput>(
    _ body: @escaping (Output) -> NewOutput
  ) -> Regex<NewOutput> {
    let transform: (Any) -> NewOutput = {
      if let previousTransform = outputTransform {
        return body(previousTransform($0))
      } else {
        return body($0 as! Output)
      }
    }
    
    var regex = Regex<NewOutput>(node: root)
    regex.outputTransform = transform
    return regex
  }
}
