
/// TODO: better description
/// Whether this is the starting byte of a sub-300 (i.e. pre-combining scalar) scalars
private func _isSub300StartingByte(_ x: UInt8) -> Bool {
  x < 0xCC
}
private func _isASCII(_ x: UInt8) -> Bool {
  x < 0x80
}

private var _lineFeed: UInt8 { 0x0A }
private var _carriageReturn: UInt8 { 0x0D }
private var _lineTab: UInt8 { 0x0B }
private var _formFeed: UInt8 { 0x0C }
private var _space: UInt8 { 0x20 }
private var _tab: UInt8 { 0x09 }



private var _0: UInt8 { 0x30 }
private var _9: UInt8 { 0x39 }
private func _isASCIINumber(_ x: UInt8) -> Bool {
  return (_0..._9).contains(x)
}

private var _a: UInt8 { 0x61 }
private var _z: UInt8 { 0x7A }
private var _A: UInt8 { 0x41 }
private var _Z: UInt8 { 0x5A }
private func _isASCIILetter(_ x: UInt8) -> Bool {
  return (_a..._z).contains(x) || (_A..._Z).contains(x)
}

private var _underscore: UInt8 { 0x5F }



extension String {
  /// TODO: detailed description of nuanced semantics
  func _asciiCharacter(
    at idx: Index
  ) -> (first: UInt8, next: Index, crLF: Bool)? {
    // TODO: fastUTF8 version

    if idx == endIndex {
      return nil
    }
    let base = utf8[idx]
    guard _isASCII(base) else { return nil }

    var next = utf8.index(after: idx)
    if next == utf8.endIndex {
      return (first: base, next: next, crLF: false)
    }

    let tail = utf8[next]
    guard _isSub300StartingByte(tail) else { return nil }

    // Handle CR-LF:
    if base == _carriageReturn && tail == _lineFeed {
      utf8.formIndex(after: &next)
      guard next == endIndex || _isSub300StartingByte(utf8[next]) else {
        return nil
      }
      return (first: base, next: next, crLF: true)
    }

    return (first: base, next: next, crLF: false)
  }

  func _quickMatch(
    _ cc: _CharacterClassModel.Representation,
    at idx: Index,
    isScalarSemantics: Bool
  ) -> (next: Index, matchResult: Bool)? {
    /// ASCII fast-paths
    guard let (asciiValue, next, isCRLF) = _asciiCharacter(
      at: idx
    ) else {
      return nil
    }

    // TODO: bitvectors
    switch cc {
    case .any, .anyGrapheme, .anyScalar:
      // TODO: should any scalar not consume CR-LF in scalar semantic mode?
      return (next, true)

    case .digit:
      if _isASCIINumber(asciiValue) {
        return (next, true)
      }
      return (next, false)

    case .horizontalWhitespace:
      switch asciiValue {
        case _space, _tab: return (next, true)
        default: return (next, false)
      }

    case .verticalWhitespace, .newlineSequence:
      switch asciiValue {
        case _lineFeed, _carriageReturn, _lineTab, _formFeed:
        // Scalar semantics: For `\v`, only advance past the CR instead of CR-LF
        if isScalarSemantics && isCRLF && cc == .verticalWhitespace {
          return (utf8.index(before: next), true)
        }
        return (next, true)

        default:
          return (next, false)
      }

    case .whitespace:
      switch asciiValue {
        case _space, _tab, _lineFeed, _lineTab, _formFeed, _carriageReturn:
          return (next, true)
        default:
          return (next, false)
      }

    case .word:
      let matches = _isASCIINumber(asciiValue) || _isASCIILetter(asciiValue) || asciiValue == _underscore
      return (next, matches)
    }
  }

}

/// MARK: TODO: Better as SPI or new low-level interfaces...

extension String {
  var _object: _StringObject {
    unsafeBitCast(self, to: _StringObject.self)
  }

  var _unsafeFastUTF8: UnsafeRawBufferPointer? {
    // TODO: platform support, or a stdlib alternative
#if arch(i386) || arch(arm) || arch(arm64_32) || arch(wasm32)
    return nil
#endif
    // TODO: Add in shared string support
    return _object.nativeUTF8IfAvailable
  }

}

internal struct _StringObject {
  // Abstract the count and performance-flags containing word
  struct CountAndFlags {
    var _storage: UInt64

    @inline(__always)
    internal init(zero: ()) { self._storage = 0 }
  }

  internal var _countAndFlagsBits: UInt64

  // NOTE: We store the raw bits instead of BridgeObject, because we don't
  // have access to bridge object
  internal var discriminatedObjectRawBits: UInt64

  @inline(__always)
  internal var _countAndFlags: CountAndFlags {
    _internalInvariant(!isSmall)
    return CountAndFlags(rawUnchecked: _countAndFlagsBits)
  }

  // Whether this string is native, i.e. tail-allocated and nul-terminated,
  // presupposing it is both large and fast
  @inline(__always)
  internal var largeFastIsTailAllocated: Bool {
    _internalInvariant(isLarge && providesFastUTF8)
    return _countAndFlags.isTailAllocated
  }

  @inline(__always)
  internal var isSmall: Bool {
#if os(Android) && arch(arm64)
    return (discriminatedObjectRawBits & 0x0020_0000_0000_0000) != 0
#else
    return (discriminatedObjectRawBits & 0x2000_0000_0000_0000) != 0
#endif
  }

  @inline(__always)
  internal var isLarge: Bool { return !isSmall }

  // Whether this string can provide access to contiguous UTF-8 code units:
  //   - Small strings can by spilling to the stack
  //   - Large native strings can through an offset
  //   - Shared strings can:
  //     - Cocoa strings which respond to e.g. CFStringGetCStringPtr()
  //     - Non-Cocoa shared strings
  @inline(__always)
  internal var providesFastUTF8: Bool {
#if os(Android) && arch(arm64)
    return (discriminatedObjectRawBits & 0x0010_0000_0000_0000) == 0
#else
    return (discriminatedObjectRawBits & 0x1000_0000_0000_0000) == 0
#endif
  }

  /// A modification of fastUTF8 from StringObject.swift, as we don't have
  /// access to shared string internals.
  @inline(__always)
  var nativeUTF8IfAvailable: UnsafeRawBufferPointer? {
    guard self.isLarge && self.providesFastUTF8 && self.largeFastIsTailAllocated else {
      return nil
    }
    return UnsafeRawBufferPointer(
      start: self.nativeUTF8Start, count: self.largeCount)
  }

  @inline(__always)
  internal var largeCount: Int {
    _internalInvariant(isLarge)
    return _countAndFlags.count
  }

  @inline(__always)
  internal var nativeUTF8Start: UnsafePointer<UInt8> {
    _internalInvariant(largeFastIsTailAllocated)
    return UnsafePointer(
      bitPattern: largeAddressBits &+ _StringObject.nativeBias
    )._unsafelyUnwrappedUnchecked
  }


  @inline(__always)
  internal var largeAddressBits: UInt {
    _internalInvariant(isLarge)
    return UInt(truncatingIfNeeded:
      discriminatedObjectRawBits & Nibbles.largeAddressMask)
  }

  enum Nibbles {}

  @inline(__always)
  internal static var nativeBias: UInt {
#if arch(i386) || arch(arm) || arch(arm64_32) || arch(wasm32)
    return 20
#else
    return 32
#endif
  }
}

extension _StringObject.Nibbles {
  // Mask for address bits, i.e. non-discriminator and non-extra high bits
  @inline(__always)
  static internal var largeAddressMask: UInt64 {
#if os(Android) && arch(arm64)
    return 0xFF0F_FFFF_FFFF_FFFF
#else
    return 0x0FFF_FFFF_FFFF_FFFF
#endif
  }

}

extension _StringObject.CountAndFlags {
  internal typealias RawBitPattern = UInt64

  @inline(__always)
  internal init(rawUnchecked bits: RawBitPattern) {
    self._storage = bits
  }

  @inline(__always)
  internal static var isTailAllocatedMask: UInt64 {
    0x1000_0000_0000_0000
  }

  @inline(__always)
  internal static var countMask: UInt64 { 0x0000_FFFF_FFFF_FFFF }

  @inline(__always)
  internal var count: Int {
    return Int(
      truncatingIfNeeded: _storage & _StringObject.CountAndFlags.countMask)
  }

  @inline(__always)
  internal var isTailAllocated: Bool {
    return 0 != _storage & _StringObject.CountAndFlags.isTailAllocatedMask
  }
}

extension UnsafeRawPointer {
  func loadByte(_ offset: String.Index) -> UInt8 {
    self.load(fromByteOffset: offset.encodedOffset, as: UInt8.self)
  }
}
