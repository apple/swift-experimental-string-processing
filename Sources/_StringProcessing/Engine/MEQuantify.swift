extension Processor {
  func _doQuantifyMatch(_ payload: QuantifyPayload) -> Input.Index? {
    let isScalarSemantics = payload.isScalarSemantics

    switch payload.type {
    case .asciiBitset:
      return input.matchASCIIBitset(
        registers[payload.bitset],
        at: currentPosition,
        limitedBy: end,
        isScalarSemantics: isScalarSemantics)
    case .asciiChar:
      return input.matchScalar(
        UnicodeScalar.init(_value: UInt32(payload.asciiChar)),
        at: currentPosition,
        limitedBy: end,
        boundaryCheck: !isScalarSemantics,
        isCaseInsensitive: false)
    case .builtin:
      guard currentPosition < end else { return nil }

      // We only emit .quantify if it consumes a single character
      return input.matchBuiltinCC(
        payload.builtin,
        at: currentPosition,
        limitedBy: end,
        isInverted: payload.builtinIsInverted,
        isStrictASCII: payload.builtinIsStrict,
        isScalarSemantics: isScalarSemantics)
    case .any:
      guard currentPosition < end else { return nil }

      if payload.anyMatchesNewline {
        if isScalarSemantics {
          return input.unicodeScalars.index(after: currentPosition)
        }
        return input.index(after: currentPosition)
      }

      return input.matchAnyNonNewline(
        at: currentPosition,
        limitedBy: end,
        isScalarSemantics: isScalarSemantics)
    }
  }

  /// Generic quantify instruction interpreter
  /// - Handles .eager and .posessive
  /// - Handles arbitrary minTrips and maxExtraTrips
  mutating func runQuantify(_ payload: QuantifyPayload) -> Bool {
    assert(payload.quantKind != .reluctant)

    var trips = 0
    var maxExtraTrips = payload.maxExtraTrips

    while trips < payload.minTrips {
      guard let next = _doQuantifyMatch(payload) else {
        signalFailure()
        return false
      }
      currentPosition = next
      trips += 1
    }

    if maxExtraTrips == 0 {
      // We're done
      return true
    }

    guard let next = _doQuantifyMatch(payload) else {
      return true
    }
    maxExtraTrips = maxExtraTrips.map { $0 - 1 }

    // Remember the range of valid positions in case we can create a quantified
    // save point
    let rangeStart = currentPosition
    var rangeEnd = currentPosition
    currentPosition = next

    while true {
      if maxExtraTrips == 0 { break }

      guard let next = _doQuantifyMatch(payload) else {
        break
      }
      maxExtraTrips = maxExtraTrips.map({$0 - 1})
      rangeEnd = currentPosition
      currentPosition = next
    }

    if payload.quantKind == .eager {
      savePoints.append(makeQuantifiedSavePoint(
        rangeStart..<rangeEnd, isScalarSemantics: payload.isScalarSemantics))
    } else {
      // No backtracking permitted after a successful advance
      assert(payload.quantKind == .possessive)
    }
    return true
  }

  /// Specialized quantify instruction interpreter for `*`, always succeeds
  mutating func runEagerZeroOrMoreQuantify(_ payload: QuantifyPayload) {
    assert(payload.quantKind == .eager
           && payload.minTrips == 0
           && payload.maxExtraTrips == nil)
    _doRunEagerZeroOrMoreQuantify(payload)
  }

  // NOTE: So-as to inline into one-or-more call, which makes a significant
  // performance difference
  @inline(__always)
  mutating func _doRunEagerZeroOrMoreQuantify(_ payload: QuantifyPayload) {
    guard let next = _doQuantifyMatch(payload) else {
      // Consumed no input, no point saved
      return
    }

    // Create a quantified save point for every part of the input matched up
    // to the final position.
    let rangeStart = currentPosition
    var rangeEnd = currentPosition
    currentPosition = next
    while true {
      guard let next = _doQuantifyMatch(payload) else { break }
      rangeEnd = currentPosition
      currentPosition = next
    }

    savePoints.append(makeQuantifiedSavePoint(rangeStart..<rangeEnd, isScalarSemantics: payload.isScalarSemantics))
  }

  /// Specialized quantify instruction interpreter for `+`
  mutating func runEagerOneOrMoreQuantify(_ payload: QuantifyPayload) -> Bool {
    assert(payload.quantKind == .eager
           && payload.minTrips == 1
           && payload.maxExtraTrips == nil)

    // Match at least once
    guard let next = _doQuantifyMatch(payload) else {
      signalFailure()
      return false
    }

    // Run `a+` as `aa*`
    currentPosition = next
    _doRunEagerZeroOrMoreQuantify(payload)
    return true
  }

  /// Specialized quantify instruction interpreter for ?
  mutating func runZeroOrOneQuantify(_ payload: QuantifyPayload) -> Bool {
    assert(payload.minTrips == 0
           && payload.maxExtraTrips == 1)
    let next = _doQuantifyMatch(payload)
    guard let idx = next else {
      return true // matched zero times
    }
    if payload.quantKind != .possessive {
      // Save the zero match
      savePoints.append(makeSavePoint(resumingAt: currentPC+1))
    }
    currentPosition = idx
    return true
  }
}
