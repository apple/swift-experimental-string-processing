@_implementationOnly import _RegexParser // For AssertionKind
extension Character {
  var _isHorizontalWhitespace: Bool {
    self.unicodeScalars.first?.isHorizontalWhitespace == true
  }
  var _isNewline: Bool {
    self.unicodeScalars.first?.isNewline == true
  }
}

extension Processor {
  mutating func matchBuiltinCC(
    _ cc: _CharacterClassModel.Representation,
    isInverted: Bool,
    isStrictASCII: Bool,
    isScalarSemantics: Bool
  ) -> Bool {
    guard let next = input.matchBuiltinCC(
      cc,
      at: currentPosition,
      isInverted: isInverted,
      isStrictASCII: isStrictASCII,
      isScalarSemantics: isScalarSemantics
    ) else {
      signalFailure()
      return false
    }
    currentPosition = next
    return true
  }

  func isAtStartOfLine(_ payload: AssertionPayload) -> Bool {
    // TODO: needs benchmark coverage
    if currentPosition == subjectBounds.lowerBound { return true }
    switch payload.semanticLevel {
    case .graphemeCluster:
      return input[input.index(before: currentPosition)].isNewline
    case .unicodeScalar:
      return input.unicodeScalars[input.unicodeScalars.index(before: currentPosition)].isNewline
    }
  }

  func isAtEndOfLine(_ payload: AssertionPayload) -> Bool {
    // TODO: needs benchmark coverage
    if currentPosition == subjectBounds.upperBound { return true }
    switch payload.semanticLevel {
    case .graphemeCluster:
      return input[currentPosition].isNewline
    case .unicodeScalar:
      return input.unicodeScalars[currentPosition].isNewline
    }
  }

  mutating func builtinAssert(by payload: AssertionPayload) throws -> Bool {
    // TODO: needs benchmark coverage

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

// MARK: Matching `.`
extension String {
  // TODO: Should the below have a `limitedBy` parameter?

  func matchAnyNonNewline(
    at currentPosition: String.Index,
    isScalarSemantics: Bool
  ) -> String.Index? {
    guard currentPosition < endIndex else {
      return nil
    }
    if case .definite(let result) = _quickMatchAnyNonNewline(
      at: currentPosition,
      isScalarSemantics: isScalarSemantics
    ) {
      assert(result == _thoroughMatchAnyNonNewline(
        at: currentPosition,
        isScalarSemantics: isScalarSemantics))
      return result
    }
    return _thoroughMatchAnyNonNewline(
      at: currentPosition,
      isScalarSemantics: isScalarSemantics)
  }

  @inline(__always)
  private func _quickMatchAnyNonNewline(
    at currentPosition: String.Index,
    isScalarSemantics: Bool
  ) -> QuickResult<String.Index?> {
    assert(currentPosition < endIndex)
    guard let (asciiValue, next, isCRLF) = _quickASCIICharacter(
      at: currentPosition
    ) else {
      return .unknown
    }
    switch asciiValue {
    case (._lineFeed)...(._carriageReturn):
      return .definite(nil)
    default:
      assert(!isCRLF)
      return .definite(next)
    }
  }

  @inline(never)
  private func _thoroughMatchAnyNonNewline(
    at currentPosition: String.Index,
    isScalarSemantics: Bool
  ) -> String.Index? {
    assert(currentPosition < endIndex)
    if isScalarSemantics {
      let scalar = unicodeScalars[currentPosition]
      guard !scalar.isNewline else { return nil }
      return unicodeScalars.index(after: currentPosition)
    }

    let char = self[currentPosition]
    guard !char.isNewline else { return nil }
    return index(after: currentPosition)
  }
}

// MARK: - Built-in character class matching
extension String {
  // TODO: Should the below have a `limitedBy` parameter?

  // Mentioned in ProgrammersManual.md, update docs if redesigned
  func matchBuiltinCC(
    _ cc: _CharacterClassModel.Representation,
    at currentPosition: String.Index,
    isInverted: Bool,
    isStrictASCII: Bool,
    isScalarSemantics: Bool
  ) -> String.Index? {
    guard currentPosition < endIndex else {
      return nil
    }
    if case .definite(let result) = _quickMatchBuiltinCC(
      cc,
      at: currentPosition,
      isInverted: isInverted,
      isStrictASCII: isStrictASCII,
      isScalarSemantics: isScalarSemantics
    ) {
      assert(result == _thoroughMatchBuiltinCC(
        cc,
        at: currentPosition,
        isInverted: isInverted,
        isStrictASCII: isStrictASCII,
        isScalarSemantics: isScalarSemantics))
      return result
    }
    return _thoroughMatchBuiltinCC(
      cc,
      at: currentPosition,
      isInverted: isInverted,
      isStrictASCII: isStrictASCII,
      isScalarSemantics: isScalarSemantics)
  }

  // Mentioned in ProgrammersManual.md, update docs if redesigned
  @inline(__always)
  private func _quickMatchBuiltinCC(
    _ cc: _CharacterClassModel.Representation,
    at currentPosition: String.Index,
    isInverted: Bool,
    isStrictASCII: Bool,
    isScalarSemantics: Bool
  ) -> QuickResult<String.Index?> {
    assert(currentPosition < endIndex)
    guard let (next, result) = _quickMatch(
      cc, at: currentPosition, isScalarSemantics: isScalarSemantics
    ) else {
      return .unknown
    }
    return .definite(result == isInverted ? nil : next)
  }

  // Mentioned in ProgrammersManual.md, update docs if redesigned
  @inline(never)
  private func _thoroughMatchBuiltinCC(
    _ cc: _CharacterClassModel.Representation,
    at currentPosition: String.Index,
    isInverted: Bool,
    isStrictASCII: Bool,
    isScalarSemantics: Bool
  ) -> String.Index? {
    assert(currentPosition < endIndex)
    let char = self[currentPosition]
    let scalar = unicodeScalars[currentPosition]

    let asciiCheck = !isStrictASCII
    || (scalar.isASCII && isScalarSemantics)
    || char.isASCII

    var matched: Bool
    var next: String.Index
    switch (isScalarSemantics, cc) {
    case (_, .anyGrapheme):
      next = index(after: currentPosition)
    case (true, _):
      next = unicodeScalars.index(after: currentPosition)
    case (false, _):
      next = index(after: currentPosition)
    }

    switch cc {
    case .any, .anyGrapheme:
      matched = true
    case .digit:
      if isScalarSemantics {
        matched = scalar.properties.numericType != nil && asciiCheck
      } else {
        matched = char.isNumber && asciiCheck
      }
    case .horizontalWhitespace:
      if isScalarSemantics {
        matched = scalar.isHorizontalWhitespace && asciiCheck
      } else {
        matched = char._isHorizontalWhitespace && asciiCheck
      }
    case .verticalWhitespace:
      if isScalarSemantics {
        matched = scalar.isNewline && asciiCheck
      } else {
        matched = char._isNewline && asciiCheck
      }
    case .newlineSequence:
      if isScalarSemantics {
        matched = scalar.isNewline && asciiCheck
        if matched && scalar == "\r"
            && next != endIndex && unicodeScalars[next] == "\n" {
          // Match a full CR-LF sequence even in scalar semantics
          unicodeScalars.formIndex(after: &next)
        }
      } else {
        matched = char._isNewline && asciiCheck
      }
    case .whitespace:
      if isScalarSemantics {
        matched = scalar.properties.isWhitespace && asciiCheck
      } else {
        matched = char.isWhitespace && asciiCheck
      }
    case .word:
      if isScalarSemantics {
        matched = scalar.properties.isAlphabetic && asciiCheck
      } else {
        matched = char.isWordCharacter && asciiCheck
      }
    }

    if isInverted {
      matched.toggle()
    }

    guard matched else {
      return nil
    }
    return next
  }
}
