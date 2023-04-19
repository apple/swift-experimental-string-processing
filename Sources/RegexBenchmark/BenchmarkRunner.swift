import Foundation
@_spi(RegexBenchmark) import _StringProcessing

/// The number of times to re-run the benchmark if results are too varying
private var rerunCount: Int { 3 }

extension Benchmark.MatchType {
  fileprivate var nameSuffix: String {
    switch self {
    case .whole: return "_Whole"
    case .first: return "_First"
    case .allMatches: return "_All"
    }
  }
}

struct BenchmarkRunner {
  let suiteName: String
  var suite: [any RegexBenchmark] = []
  
  let samples: Int
  var results: SuiteResult = SuiteResult()
  let quiet: Bool
  let enableTracing: Bool
  let enableMetrics: Bool
  
  // Forcibly include firstMatch benchmarks for all CrossBenchmarks
  let includeFirstOverride: Bool

  // Register a cross-benchmark
  mutating func registerCrossBenchmark(
    nameBase: String,
    input: String,
    pattern: String,
    _ type: Benchmark.MatchType,
    alsoRunScalarSemantic: Bool = true
  ) {
    let swiftRegex = try! Regex(pattern)
    let nsRegex: NSRegularExpression
    if type == .whole {
      nsRegex = try! NSRegularExpression(pattern: "^" + pattern + "$")
    } else {
      nsRegex = try! NSRegularExpression(pattern: pattern)
    }
    let nameSuffix = type.nameSuffix

    register(
      Benchmark(
        name: nameBase + nameSuffix,
        regex: swiftRegex,
        pattern: pattern,
        type: type,
        target: input))
    register(
      NSBenchmark(
        name: nameBase + nameSuffix + CrossBenchmark.nsSuffix,
        regex: nsRegex,
        type: .init(type),
        target: input))

    if alsoRunScalarSemantic {
      register(
        Benchmark(
          name: nameBase + nameSuffix + "_Scalar",
          regex: swiftRegex.matchingSemantics(.unicodeScalar),
          pattern: pattern,
          type: type,
          target: input))
      register(
        NSBenchmark(
          name: nameBase + nameSuffix + "_Scalar" + CrossBenchmark.nsSuffix,
          regex: nsRegex,
          type: .init(type),
          target: input))
    }
  }

  // Register a cross-benchmark list
  mutating func registerCrossBenchmark(
    name: String,
    inputList: [String],
    pattern: String,
    alsoRunScalarSemantic: Bool = true
  ) {
    let swiftRegex = try! Regex(pattern)
    register(InputListBenchmark(
      name: name,
      regex: swiftRegex,
      pattern: pattern,
      targets: inputList
    ))
    register(InputListNSBenchmark(
      name: name + CrossBenchmark.nsSuffix,
      regex: pattern,
      targets: inputList
    ))

    if alsoRunScalarSemantic {
      register(InputListBenchmark(
        name: name + "_Scalar",
        regex: swiftRegex.matchingSemantics(.unicodeScalar),
        pattern: pattern,
        targets: inputList
      ))
      register(InputListNSBenchmark(
        name: name + "_Scalar" + CrossBenchmark.nsSuffix,
        regex: pattern,
        targets: inputList
      ))
    }

  }

  // Register a swift-only benchmark
  mutating func register(
    nameBase: String,
    input: String,
    pattern: String,
    _ swiftRegex: Regex<AnyRegexOutput>,
    _ type: Benchmark.MatchType,
    alsoRunScalarSemantic: Bool = true
  ) {
    let nameSuffix = type.nameSuffix

    register(
      Benchmark(
        name: nameBase + nameSuffix,
        regex: swiftRegex,
        pattern: pattern,
        type: type,
        target: input))

    if alsoRunScalarSemantic {
      register(
        Benchmark(
          name: nameBase + nameSuffix + "_Scalar",
          regex: swiftRegex,
          pattern: pattern,
          type: type,
          target: input))
    }
  }
  
  private mutating func register(_ benchmark: NSBenchmark) {
    suite.append(benchmark)
  }
  
  private mutating func register(_ benchmark: Benchmark) {
    var benchmark = benchmark
    if enableTracing {
      benchmark.enableTracing()
    }
    if enableMetrics {
      benchmark.enableMetrics()
    }
    suite.append(benchmark)
  }

  private mutating func register(_ benchmark: InputListNSBenchmark) {
    suite.append(benchmark)
  }

  private mutating func register(_ benchmark: InputListBenchmark) {
    var benchmark = benchmark
    if enableTracing {
      benchmark.enableTracing()
    }
    if enableMetrics {
      benchmark.enableMetrics()
    }
    suite.append(benchmark)
  }
  
  func medianMeasure(
    samples: Int,
    closure: () -> Void
  ) -> Measurement {
    // FIXME: use suspendingclock?
    var times: [Time] = []
    for _ in 0..<samples {
      let start = Tick.now
      closure()
      let end = Tick.now
      let time = end.elapsedTime(since: start)
      times.append(time)
    }
    return Measurement(results: times)
  }
  
  func measure(
    benchmark: some RegexBenchmark,
    samples: Int
  ) -> BenchmarkResult {
    // Initial run to make sure the regex has been compiled
    benchmark.run()

    // Measure compilataion time for Swift regex
    let compileTime: Measurement?
    let parseTime: Measurement?
    if benchmark is SwiftRegexBenchmark {
      var benchmark = benchmark as! SwiftRegexBenchmark
      compileTime = medianMeasure(samples: samples) { benchmark.compile() }
      // Can't parse if we don't have an input string (ie a builder regex)
      if benchmark.pattern != nil {
        parseTime = medianMeasure(samples: samples) { let _ = benchmark.parse() }
      } else {
        parseTime = nil
      }
      
    } else {
      compileTime = nil
      parseTime = nil
    }
    
    let runtime = medianMeasure(samples: samples) { benchmark.run() }
    return BenchmarkResult(
      runtime: runtime,
      compileTime: compileTime,
      parseTime: parseTime)
  }
  
  mutating func run() {
    print("Running")
    for b in suite {
      var result = measure(benchmark: b, samples: samples)
      if result.runtimeIsTooVariant {
        for _ in 0..<rerunCount {
          print("Warning: Standard deviation > \(Stats.maxAllowedStdev*100)% for \(b.name)")
          print(result.runtime)
          print("Rerunning \(b.name)")
          result = measure(benchmark: b, samples: result.runtime.samples*2)
          print(result.runtime)
          if !result.runtimeIsTooVariant {
            break
          }
        }
        if result.runtimeIsTooVariant {
          fatalError("Benchmark \(b.name) is too variant")
        }
      }
      if result.compileTime?.median ?? .zero > Time.millisecond {
        print("Warning: Abnormally high compilation time, what happened?")
      }
      
      if result.parseTime?.median ?? .zero > Time.millisecond {
        print("Warning: Abnormally high parse time, what happened?")
      }
      if !quiet {
        print("- \(b.name)\n\(result)")
      }
      self.results.add(name: b.name, result: result)
    }
  }
    
  mutating func debug() {
    print("Debugging")
    print("========================")
    for b in suite {
      b.debug()
      print("========================")
    }
  }
}
