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

extension UnicodeScalar {
  var isHorizontalWhitespace: Bool {
    value == 0x09 || properties.generalCategory == .spaceSeparator
  }
  
  var isNewline: Bool {
    switch value {
      case 0x000A...0x000D /* LF ... CR */: return true
      case 0x0085 /* NEXT LINE (NEL) */: return true
      case 0x2028 /* LINE SEPARATOR */: return true
      case 0x2029 /* PARAGRAPH SEPARATOR */: return true
      default: return false
    }
  }
}
