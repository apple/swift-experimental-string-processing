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
  ///
  /// If the position in the input is not definitely a full-ASCII character (uses sub-`0x300` quick check
  /// on next byte), return `nil.`
  ///
  /// Otherwise, returns:
  ///   1. The first ASCII byte for a character (or scalar if `isScalarSemantics`)
  ///   2. Whether the ASCII Character is CR-LF
  ///   3. The index for the end of that particular ASCII character:
  ///     If the character is not CR-LF, the index of the next byte
  ///     if `isScalarSemantics` is false and the ASCII character is CR-LF, the index after the CR-LF sequence.
  ///
  func _quickASCIICharacter(
    at idx: Index,
    limitedBy end: Index,
    isScalarSemantics: Bool
  ) -> (firstASCIIByte: UInt8, isCRLF: Bool, asciiCharacterEnd: Index)? {
    // TODO: fastUTF8 version
    assert(String.Index(idx, within: unicodeScalars) != nil)
    assert(idx <= end)
    
    if idx == end {
      return nil
    }
    let base = utf8[idx]
    guard base._isASCII else {
      assert(!self[idx].isASCII)
      return nil
    }

    let byteEnd = utf8.index(after: idx)
    if isScalarSemantics || byteEnd == end {
      return (firstASCIIByte: base, isCRLF: false, asciiCharacterEnd: byteEnd)
    }

    let tail = utf8[byteEnd]
    guard tail._isSub300StartingByte else { return nil }

    // Handle CR-LF:
    if base == ._carriageReturn && tail == ._lineFeed {
      let crLFEnd = utf8.index(after: byteEnd)
      guard crLFEnd == end || utf8[crLFEnd]._isSub300StartingByte else {
        return nil
      }
      return (firstASCIIByte: base, isCRLF: true, asciiCharacterEnd: crLFEnd)
    }

    assert(self[idx].isASCII && self[idx] != "\r\n")
    return (firstASCIIByte: base, isCRLF: false, asciiCharacterEnd: byteEnd)
  }

  func _quickMatch(
    _ cc: _CharacterClassModel.Representation,
    at idx: Index,
    limitedBy end: Index,
    isScalarSemantics: Bool
  ) -> (next: Index, matchResult: Bool)? {
    // Don't use scalar semantics in this quick path for anyGrapheme cluster or
    // newline sequences, which are not scalar character classes.
    let useScalarSemantics = isScalarSemantics && cc != .anyGrapheme && cc != .newlineSequence
    /// ASCII fast-paths
    guard let (asciiValue, isCRLF: isCRLF, charEnd) = _quickASCIICharacter(
      at: idx,
      limitedBy: end,
      isScalarSemantics: useScalarSemantics
    ) else {
      return nil
    }

    // TODO: bitvectors
    switch cc {
    case .any:
      return (charEnd, true)

    case .anyGrapheme:
      // _quickASCIICharacter call handled CR-LF for us
      _ = isCRLF
      return (charEnd, true)

    case .digit:
      return (charEnd, asciiValue._asciiIsDigit)

    case .horizontalWhitespace:
      return (charEnd, asciiValue._asciiIsHorizontalWhitespace)

    case .verticalWhitespace:
      return (charEnd, asciiValue._asciiIsVerticalWhitespace)

    case .newlineSequence:
      // _quickASCIICharacter call handled CR-LF for us
      _ = isCRLF
      return (charEnd, asciiValue._asciiIsVerticalWhitespace)

    case .whitespace:
      return (charEnd, asciiValue._asciiIsWhitespace)

    case .word:
      return (charEnd, asciiValue._asciiIsWord)
    }
  }

}

