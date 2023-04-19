extension DSLTree.CustomCharacterClass {
  internal struct AsciiBitset {
    let isInverted: Bool
    var a: UInt64 = 0
    var b: UInt64 = 0

    init(isInverted: Bool) {
      self.isInverted = isInverted
    }

    init(_ val: UInt8, _ isInverted: Bool, _ isCaseInsensitive: Bool) {
      self.isInverted = isInverted
      add(val, isCaseInsensitive)
    }

    init(low: UInt8, high: UInt8, isInverted: Bool, isCaseInsensitive: Bool) {
      self.isInverted = isInverted
      for val in low...high {
        add(val, isCaseInsensitive)
      }
    }

    internal init(
      a: UInt64,
      b: UInt64,
      isInverted: Bool
    ) {
      self.isInverted = isInverted
      self.a = a
      self.b = b
    }

    internal mutating func add(_ val: UInt8, _ isCaseInsensitive: Bool) {
      setBit(val)
      if isCaseInsensitive {
        switch val {
          case 64...90: setBit(val + 32)
          case 97...122: setBit(val - 32)
          default: break
        }
      }
    }

    internal mutating func setBit(_ val: UInt8) {
      if val < 64 {
        a = a | 1 << val
      } else {
        b = b | 1 << (val - 64)
      }
    }

    private func matches(_ val: UInt8) -> Bool {
      if val < 64 {
        return (a >> val) & 1 == 1
      } else {
        return (b >> (val - 64)) & 1 == 1
      }
    }

    internal func matches(_ char: Character) -> Bool {
      let matched: Bool
      if let val = char._singleScalarAsciiValue {
        matched = matches(val)
      } else {
        matched = false
      }

      if isInverted {
        return !matched
      }
      return matched
    }

    internal func matches(_ scalar: Unicode.Scalar) -> Bool {
      let matched: Bool
      if scalar.isASCII {
        let val = UInt8(ascii: scalar)
        matched = matches(val)
      } else {
        matched = false
      }

      if isInverted {
        return !matched
      }
      return matched
    }

    /// Joins another bitset from a Member of the same CustomCharacterClass
    internal func union(_ other: AsciiBitset) -> AsciiBitset {
      precondition(self.isInverted == other.isInverted)
      return AsciiBitset(
        a: self.a | other.a,
        b: self.b | other.b,
        isInverted: self.isInverted
      )
    }
  }
}
