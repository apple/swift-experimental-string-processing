//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2021-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

extension UInt8 {
  static var _lineFeed: UInt8 { 0x0A }
  static var _carriageReturn: UInt8 { 0x0D }
  static var _lineTab: UInt8 { 0x0B }
  static var _formFeed: UInt8 { 0x0C }
  static var _space: UInt8 { 0x20 }
  static var _tab: UInt8 { 0x09 }

  static var _underscore: UInt8 { 0x5F }
}

private var _0: UInt8 { 0x30 }
private var _9: UInt8 { 0x39 }

private var _a: UInt8 { 0x61 }
private var _z: UInt8 { 0x7A }
private var _A: UInt8 { 0x41 }
private var _Z: UInt8 { 0x5A }

extension UInt8 {
  var _isASCII: Bool { self < 0x80 }

  // TODO: Bitvectors for the below

  /// Assuming we're ASCII, whether we match `\d`
  var _asciiIsDigit: Bool {
    assert(_isASCII)
    return(_0..._9).contains(self)
  }

  /// Assuming we're ASCII, whether we match `\h`
  var _asciiIsHorizontalWhitespace: Bool {
    assert(_isASCII)
    return self == ._space || self == ._tab
  }

  /// Assuming we're ASCII, whether we match `\v`
  var _asciiIsVerticalWhitespace: Bool {
    assert(_isASCII)
    switch self {
    case ._lineFeed, ._carriageReturn, ._lineTab, ._formFeed:
      return true
    default:
      return false
    }
  }

  /// Assuming we're ASCII, whether we match `\s`
  var _asciiIsWhitespace: Bool {
    assert(_isASCII)
    switch self {
    case ._space, ._tab, ._lineFeed, ._lineTab, ._formFeed, ._carriageReturn:
      return true
    default:
      return false
    }
  }

  /// Assuming we're ASCII, whether we match `[a-zA-Z]`
  var _asciiIsLetter: Bool {
    assert(_isASCII)
    return (_a..._z).contains(self) || (_A..._Z).contains(self)
  }

  /// Assuming we're ASCII, whether we match `\w`
  var _asciiIsWord: Bool {
    assert(_isASCII)
    return _asciiIsDigit || _asciiIsLetter || self == ._underscore
  }
}

extension String {
  /// TODO: better to take isScalarSemantics parameter, we can return more results
  /// and we can give the right `next` index, not requiring the caller to re-adjust it
  /// TODO: detailed description of nuanced semantics
  func _quickASCIICharacter(
    at idx: Index
  ) -> (first: UInt8, next: Index, crLF: Bool)? {
    // TODO: fastUTF8 version

    if idx == endIndex {
      return nil
    }
    let base = utf8[idx]
    guard base._isASCII else {
      assert(!self[idx].isASCII)
      return nil
    }

    var next = utf8.index(after: idx)
    if next == utf8.endIndex {
      assert(self[idx].isASCII)
      return (first: base, next: next, crLF: false)
    }

    let tail = utf8[next]
    guard tail._isSub300StartingByte else { return nil }

    // Handle CR-LF:
    if base == ._carriageReturn && tail == ._lineFeed {
      utf8.formIndex(after: &next)
      guard next == endIndex || utf8[next]._isSub300StartingByte else {
        return nil
      }
      assert(self[idx] == "\r\n")
      return (first: base, next: next, crLF: true)
    }

    assert(self[idx].isASCII && self[idx] != "\r\n")
    return (first: base, next: next, crLF: false)
  }

  func _quickMatch(
    _ cc: _CharacterClassModel.Representation,
    at idx: Index,
    isScalarSemantics: Bool
  ) -> (next: Index, matchResult: Bool)? {
    /// ASCII fast-paths
    guard let (asciiValue, next, isCRLF) = _quickASCIICharacter(
      at: idx
    ) else {
      return nil
    }

    // TODO: bitvectors
    switch cc {
    case .any, .anyGrapheme:
      return (next, true)

    case .digit:
      return (next, asciiValue._asciiIsDigit)

    case .horizontalWhitespace:
      return (next, asciiValue._asciiIsHorizontalWhitespace)

    case .verticalWhitespace, .newlineSequence:
      if asciiValue._asciiIsVerticalWhitespace {
        if isScalarSemantics && isCRLF && cc == .verticalWhitespace {
          return (utf8.index(before: next), true)
        }
        return (next, true)
      }
      return (next, false)

    case .whitespace:
      if asciiValue._asciiIsWhitespace {
        if isScalarSemantics && isCRLF {
          return (utf8.index(before: next), true)
        }
        return (next, true)
      }
      return (next, false)

    case .word:
      return (next, asciiValue._asciiIsWord)
    }
  }

}

