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
  mutating func matchBuiltin(
    _ cc: _CharacterClassModel.Representation,
    _ isInverted: Bool,
    _ isStrictASCII: Bool,
    _ isScalarSemantics: Bool
  ) -> Bool {
    guard let next = _doMatchBuiltin(
      cc,
      isInverted,
      isStrictASCII,
      isScalarSemantics
    ) else {
      signalFailure()
      return false
    }
    currentPosition = next
    return true
  }
  
  func _doMatchBuiltin(
    _ cc: _CharacterClassModel.Representation,
    _ isInverted: Bool,
    _ isStrictASCII: Bool,
    _ isScalarSemantics: Bool
  ) -> Input.Index? {

    // ASCII fast-path
    if let (next, result) = input._quickMatch(
      cc, at: currentPosition, isScalarSemantics: isScalarSemantics
    ) {
      return result == isInverted ? nil : next
    }

    guard let char = load(), let scalar = loadScalar() else {
      return nil
    }

    let asciiCheck = !isStrictASCII
      || (scalar.isASCII && isScalarSemantics)
      || char.isASCII

    var matched: Bool
    var next: Input.Index
    switch (isScalarSemantics, cc) {
    case (_, .anyGrapheme):
      next = input.index(after: currentPosition)
    case (_, .anyScalar):
      next = input.unicodeScalars.index(after: currentPosition)
    case (true, _):
      next = input.unicodeScalars.index(after: currentPosition)
    case (false, _):
      next = input.index(after: currentPosition)
    }

    switch cc {
    case .any, .anyGrapheme:
      matched = true
    case .anyScalar:
      if isScalarSemantics {
        matched = true
      } else {
        matched = input.isOnGraphemeClusterBoundary(next)
      }
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
            && next != input.endIndex && input.unicodeScalars[next] == "\n" {
          // Match a full CR-LF sequence even in scalar semantics
          input.unicodeScalars.formIndex(after: &next)
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
