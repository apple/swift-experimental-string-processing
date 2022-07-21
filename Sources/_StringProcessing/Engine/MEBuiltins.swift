@_implementationOnly import _RegexParser // For AssertionKind

extension Processor {
  func _doMatchBuiltin(
    _ cc: _CharacterClassModel.Representation,
    _ isInverted: Bool,
    _ isStrictAscii: Bool
  ) -> Input.Index? {
    guard let c = load() else {
      return nil
    }

    var matched: Bool
    var next = input.index(after: currentPosition)
    switch cc {
    case .any, .anyGrapheme: matched = true
    case .anyScalar:
      matched = true
      next = input.unicodeScalars.index(after: currentPosition)
    case .digit:
      matched = c.isNumber && (c.isASCII || !isStrictAscii)
    case .horizontalWhitespace:
      matched = c.unicodeScalars.first?.isHorizontalWhitespace == true
      && (c.isASCII || !isStrictAscii)
    case .newlineSequence, .verticalWhitespace:
      matched = c.unicodeScalars.first?.isNewline == true
      && (c.isASCII || !isStrictAscii)
    case .whitespace:
      matched = c.isWhitespace && (c.isASCII || !isStrictAscii)
    case .word:
      matched = c.isWordCharacter && (c.isASCII || !isStrictAscii)
    }
    if isInverted {
      matched.toggle()
    }
    return matched ? next : nil
  }

  mutating func matchBuiltin(
    _ cc: _CharacterClassModel.Representation,
    _ isInverted: Bool,
    _ isStrictAscii: Bool
  ) -> Bool {
    guard let next = _doMatchBuiltin(cc, isInverted, isStrictAscii) else {
      signalFailure()
      return false
    }
    currentPosition = next
    return true
  }
  
  mutating func matchBuiltinScalar(
    _ cc: _CharacterClassModel.Representation,
    _ isInverted: Bool,
    _ isStrictAscii: Bool
  ) -> Bool {
    guard let c = loadScalar() else {
      signalFailure()
      return false
    }

    var matched: Bool
    var next = input.unicodeScalars.index(after: currentPosition)
    switch cc {
    case .any: matched = true
    case .anyScalar: matched = true
    case .anyGrapheme:
      matched = true
      next = input.index(after: currentPosition)
    case .digit:
      matched = c.properties.numericType != nil && (c.isASCII || !isStrictAscii)
    case .horizontalWhitespace:
      matched = c.isHorizontalWhitespace && (c.isASCII || !isStrictAscii)
    case .verticalWhitespace:
      matched = c.isNewline && (c.isASCII || !isStrictAscii)
    case .newlineSequence:
      matched = c.isNewline && (c.isASCII || !isStrictAscii)
      if c == "\r" && next != input.endIndex && input.unicodeScalars[next] == "\n" {
        input.unicodeScalars.formIndex(after: &next)
      }
    case .whitespace:
      matched = c.properties.isWhitespace && (c.isASCII || !isStrictAscii)
    case .word:
      matched = (c.properties.isAlphabetic || c == "_") && (c.isASCII || !isStrictAscii)
    }
    if isInverted {
      matched.toggle()
    }
    if matched {
      currentPosition = next
      return true
    } else {
      signalFailure()
      return false
    }
  }
  
  func isAtStartOfLine(_ payload: AssertionPayload) -> Bool {
    if currentPosition == subjectBounds.lowerBound { return true }
    switch payload.semanticLevel {
    case .graphemeCluster:
      return input[input.index(before: currentPosition)].isNewline
    case .unicodeScalar:
      return input.unicodeScalars[input.unicodeScalars.index(before: currentPosition)].isNewline
    }
  }
  
  func isAtEndOfLine(_ payload: AssertionPayload) -> Bool {
    if currentPosition == subjectBounds.upperBound { return true }
    switch payload.semanticLevel {
    case .graphemeCluster:
      return input[currentPosition].isNewline
    case .unicodeScalar:
      return input.unicodeScalars[currentPosition].isNewline
    }
  }

  mutating func builtinAssert(by payload: AssertionPayload) throws -> Bool {
    // Future work: Optimize layout and dispatch
    switch payload.kind {
    case .startOfSubject: return currentPosition == subjectBounds.lowerBound

    case .endOfSubjectBeforeNewline:
      if currentPosition == subjectBounds.upperBound { return true }
      switch payload.semanticLevel {
      case .graphemeCluster:
        return input.index(after: currentPosition) == subjectBounds.upperBound
         && input[currentPosition].isNewline
      case .unicodeScalar:
        return input.unicodeScalars.index(after: currentPosition) == subjectBounds.upperBound
         && input.unicodeScalars[currentPosition].isNewline
      }

    case .endOfSubject: return currentPosition == subjectBounds.upperBound

    case .resetStartOfMatch:
      fatalError("Unreachable, we should have thrown an error during compilation")

    case .firstMatchingPositionInSubject:
      return currentPosition == searchBounds.lowerBound

    case .textSegment: return input.isOnGraphemeClusterBoundary(currentPosition)

    case .notTextSegment: return !input.isOnGraphemeClusterBoundary(currentPosition)

    case .startOfLine:
      return isAtStartOfLine(payload)
    case .endOfLine:
      return isAtEndOfLine(payload)
      
    case .caretAnchor:
      if payload.anchorsMatchNewlines {
        return isAtStartOfLine(payload)
      } else {
        return currentPosition == subjectBounds.lowerBound
      }

    case .dollarAnchor:
      if payload.anchorsMatchNewlines {
        return isAtEndOfLine(payload)
      } else {
        return currentPosition == subjectBounds.upperBound
      }

    case .wordBoundary:
      if payload.usesSimpleUnicodeBoundaries {
        // TODO: How should we handle bounds?
        return atSimpleBoundary(payload.usesASCIIWord, payload.semanticLevel)
      } else {
        return input.isOnWordBoundary(at: currentPosition, using: &wordIndexCache, &wordIndexMaxIndex)
      }

    case .notWordBoundary:
      if payload.usesSimpleUnicodeBoundaries {
        // TODO: How should we handle bounds?
        return !atSimpleBoundary(payload.usesASCIIWord, payload.semanticLevel)
      } else {
        return !input.isOnWordBoundary(at: currentPosition, using: &wordIndexCache, &wordIndexMaxIndex)
      }
      }
  }
}

struct AssertionPayload: RawRepresentable {
  var _assertionKindMask: UInt64 { ~0xFFF0_0000_0000_0000 }
  var _opcodeMask: UInt64 { 0xFF00_0000_0000_0000 }
  
  let rawValue: UInt64

  init(rawValue: UInt64) {
    self.rawValue = rawValue
    assert(rawValue & _opcodeMask == 0)
  }
  
  init(_ assertion: DSLTree.Atom.Assertion,
       _ anchorsMatchNewlines: Bool,
       _ usesSimpleUnicodeBoundaries: Bool,
       _ usesASCIIWord: Bool,
       _ semanticLevel: MatchingOptions.SemanticLevel
  ) {
    // 4 bits of options
    let anchorBit: UInt64 = anchorsMatchNewlines ? (1 << 55) : 0
    let boundaryBit: UInt64 = usesSimpleUnicodeBoundaries ? (1 << 54) : 0
    let strictBit: UInt64 = usesASCIIWord ? (1 << 53) : 0
    let semanticLevelBit: UInt64 = semanticLevel == .unicodeScalar ? (1 << 52) : 0
    let optionsBits: UInt64 = anchorBit + boundaryBit + strictBit + semanticLevelBit

    // 4 bits for the assertion kind
    // Future work: Optimize this layout
    let kind = assertion.rawValue
    self.init(rawValue: kind + optionsBits)
  }
  
  var kind: DSLTree.Atom.Assertion {
    return .init(rawValue: self.rawValue & _assertionKindMask)!
  }
  var anchorsMatchNewlines: Bool { (self.rawValue >> 55) & 1 == 1 }
  var usesSimpleUnicodeBoundaries: Bool  { (self.rawValue >> 54) & 1 == 1 }
  var usesASCIIWord: Bool  { (self.rawValue >> 53) & 1 == 1 }
  var semanticLevel: MatchingOptions.SemanticLevel {
    if (self.rawValue >> 52) & 1 == 1 {
      return .unicodeScalar
    } else {
      return .graphemeCluster
    }
  }
}
