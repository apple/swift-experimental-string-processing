import Foundation
@_spi(RegexBenchmark) import _StringProcessing

/// The number of times to re-run the benchmark if results are too variang
private var rerunCount: Int { 3 }

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
  
  mutating func register(_ benchmark: some RegexBenchmark) {
    suite.append(benchmark)
  }
  
  mutating func register(_ benchmark: some SwiftRegexBenchmark) {
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
          result = measure(benchmark: b, samples: result.runtime.samples)
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
