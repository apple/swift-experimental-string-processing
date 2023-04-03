extension Processor {
#if PROCESSOR_MEASUREMENTS_ENABLED
  struct ProcessorMetrics {
    var instructionCounts: [Instruction.OpCode: Int] = [:]
    var backtracks: Int = 0
    var resets: Int = 0
    var cycleCount: Int = 0

    var isTracingEnabled: Bool = false
    var shouldMeasureMetrics: Bool = false

    init(isTracingEnabled: Bool, shouldMeasureMetrics: Bool) {
      self.isTracingEnabled = isTracingEnabled
      self.shouldMeasureMetrics = shouldMeasureMetrics
    }
  }
#else
  struct ProcessorMetrics {
    var isTracingEnabled: Bool { false }
    var shouldMeasureMetrics: Bool { false }
    var cycleCount: Int { 0 }

    init(isTracingEnabled: Bool, shouldMeasureMetrics: Bool) { }
  }
#endif
}

extension Processor {

  mutating func startCycleMetrics() {
#if PROCESSOR_MEASUREMENTS_ENABLED
    if metrics.cycleCount == 0 {
      trace()
      measureMetrics()
    }
#endif
  }

  mutating func endCycleMetrics() {
#if PROCESSOR_MEASUREMENTS_ENABLED
    metrics.cycleCount += 1
    trace()
    measureMetrics()
    _checkInvariants()
#endif
  }
}

extension Processor.ProcessorMetrics {

  mutating func addReset() {
#if PROCESSOR_MEASUREMENTS_ENABLED
    self.resets += 1
#endif
  }

  mutating func addBacktrack() {
#if PROCESSOR_MEASUREMENTS_ENABLED
    self.backtracks += 1
#endif
  }
}

extension Processor {
#if PROCESSOR_MEASUREMENTS_ENABLED
  func printMetrics() {
    print("===")
    print("Total cycle count: \(metrics.cycleCount)")
    print("Backtracks: \(metrics.backtracks)")
    print("Resets: \(metrics.resets)")
    print("Instructions:")
    let sorted = metrics.instructionCounts
      .filter({$0.1 != 0})
      .sorted(by: { (a,b) in a.1 > b.1 })
    for (opcode, count) in sorted {
      print("> \(opcode): \(count)")
    }
    print("===")
  }

  mutating func measure() {
    let (opcode, _) = fetch().destructure
    if metrics.instructionCounts.keys.contains(opcode) {
      metrics.instructionCounts[opcode]! += 1
    } else {
      metrics.instructionCounts.updateValue(1, forKey: opcode)
    }
  }
  
  mutating func measureMetrics() {
    if metrics.shouldMeasureMetrics {
      measure()
    }
  }
#endif
}
