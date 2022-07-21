extension Processor {
  func _doQuantifyMatch(_ payload: QuantifyPayload) -> Input.Index? {
    var next: Input.Index?
    switch payload.type {
    case .bitset:
      next = _doMatchBitset(registers[payload.bitset])
    case .asciiChar:
      next = _doMatchScalar(
        UnicodeScalar.init(_value: UInt32(payload.asciiChar)), true)
    case .builtin:
      // We only emit .quantify if it consumes a single character
      next = _doMatchBuiltin(payload.builtin,
                             payload.builtinIsInverted, payload.builtinIsStrict)
    case .any:
      let matched = currentPosition != input.endIndex
        && (!input[currentPosition].isNewline || payload.anyMatchesNewline)
      next = matched ? input.index(after: currentPosition) : nil
    }
    return next
  }
  
  /// Generic quantify instruction interpreter
  /// - Handles .eager and .posessive
  /// - Handles arbitrary minTrips and extraTrips
  mutating func runQuantify(_ payload: QuantifyPayload) -> Bool {
    var trips = 0
    var extraTrips = payload.extraTrips
    var savePoint = startQuantifierSavePoint()
    
    while true {
      if trips >= payload.minTrips {
        if extraTrips == 0 { break }
        extraTrips = extraTrips.map({$0 - 1})
        if payload.quantKind == .eager {
          savePoint.updateRange(newEnd: currentPosition)
        }
      }
      let next = _doQuantifyMatch(payload)
      guard let idx = next else { break }
      currentPosition = idx
      trips += 1
    }
    
    if trips < payload.minTrips {
      signalFailure()
      return false
    }
    
    if payload.quantKind == .eager && !savePoint.rangeIsEmpty {
      // The last save point has saved the current position, so it's unneeded
      savePoint.shrinkRange(input)
      if !savePoint.rangeIsEmpty {
        savePoints.append(savePoint)
      }
    }
    return true
  }
  
  /// Specialized quantify instruction interpreter for *
  mutating func runEagerZeroOrMoreQuantify(_ payload: QuantifyPayload) -> Bool {
    assert(payload.quantKind == .eager
           && payload.minTrips == 0
           && payload.extraTrips == nil)
    var savePoint = startQuantifierSavePoint()
    
    while true {
      savePoint.updateRange(newEnd: currentPosition)
      let next = _doQuantifyMatch(payload)
      guard let idx = next else { break }
      currentPosition = idx
    }
    
    // The last save point has saved the current position, so it's unneeded
    savePoint.shrinkRange(input)
    if !savePoint.rangeIsEmpty {
      savePoints.append(savePoint)
    }
    return true
  }
  
  /// Specialized quantify instruction interpreter for +
  mutating func runEagerOneOrMoreQuantify(_ payload: QuantifyPayload) -> Bool {
    assert(payload.quantKind == .eager
           && payload.minTrips == 1
           && payload.extraTrips == nil)
    var savePoint = startQuantifierSavePoint()
    while true {
      let next = _doQuantifyMatch(payload)
      guard let idx = next else { break }
      currentPosition = idx
      savePoint.updateRange(newEnd: currentPosition)
    }
    
    if savePoint.rangeIsEmpty {
      signalFailure()
      return false
    }
    // The last save point has saved the current position, so it's unneeded
    savePoint.shrinkRange(input)
    if !savePoint.rangeIsEmpty {
      savePoints.append(savePoint)
    }
    return true
  }
  
  /// Specialized quantify instruction interpreter for ?
  mutating func runZeroOrOneQuantify(_ payload: QuantifyPayload) -> Bool {
    assert(payload.minTrips == 0
           && payload.extraTrips == 1)
    let next = _doQuantifyMatch(payload)
    guard let idx = next else {
      return true // matched zero times
    }
    if payload.quantKind != .possessive {
      // Save the zero match
      let savePoint = makeSavePoint(currentPC + 1)
      savePoints.append(savePoint)
    }
    currentPosition = idx
    return true
  }
}
