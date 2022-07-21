import Foundation

struct BenchmarkRunner {
  let suiteName: String
  var suite: [any RegexBenchmark] = []
  
  let samples: Int
  var results: SuiteResult = SuiteResult()
  let quiet: Bool

  init(_ suiteName: String, _ n: Int, _ quiet: Bool) {
    self.suiteName = suiteName
    self.samples = n
    self.quiet = quiet
  }
  
  mutating func register(_ new: some RegexBenchmark) {
    suite.append(new)
  }
  
  mutating func measure(benchmark: some RegexBenchmark, samples: Int) -> BenchmarkResult {
    var times: [Time] = []
    
    // initial run to make sure the regex has been compiled
    // todo: measure compile times, or at least how much this first run
    //       differs from the later ones
    benchmark.run()
    
    // fixme: use suspendingclock?
    for _ in 0..<samples {
      let start = Tick.now
      benchmark.run()
      let end = Tick.now
      let time = end.elapsedTime(since: start)
      times.append(time)
    }

    times.sort()
    let median = times[samples/2]
    let mean = times.reduce(0.0, {acc, next in acc + next.seconds}) / Double(times.count)
    let stdev = (times.reduce(0.0, {acc, next in acc + pow(next.seconds - mean, 2)}) / Double(times.count)).squareRoot()
    return BenchmarkResult(median, stdev, samples)
  }
  
  mutating func run() {
    print("Running")
    for b in suite {
      var result = measure(benchmark: b, samples: samples)
      if !quiet {
        print("- \(b.name) \(result.median) (stdev: \(Time(result.stdev)))")
      }
      
      if result.stdev > Stats.maxAllowedStdev {
        print("Warning: Standard deviation > \(Time(Stats.maxAllowedStdev)) for \(b.name)")
        print("N = \(samples), median: \(result.median), stdev: \(Time(result.stdev))")
        print("Rerunning \(b.name)")
        result = measure(benchmark: b, samples: result.samples*2)
        print("N = \(result.samples), median: \(result.median), stdev: \(Time(result.stdev))")
        if result.stdev > Stats.maxAllowedStdev {
          fatalError("Benchmark \(b.name) is too variant")
        }
      }
      
      self.results.add(name: b.name, result: result)
    }
  }
    
  mutating func debug() {
    print("Debugging")
    print("========================")
    for b in suite {
      let result = measure(benchmark: b, samples: samples)
      print("- \(b.name) \(result.median) (stdev: \(Time(result.stdev)))")
      b.debug()
      print("========================")
    }
  }
}

extension BenchmarkRunner {
  
  func save(to savePath: String) throws {
    let url = URL(fileURLWithPath: savePath, isDirectory: false)
    let parent = url.deletingLastPathComponent()
    if !FileManager.default.fileExists(atPath: parent.path) {
      try! FileManager.default.createDirectory(atPath: parent.path, withIntermediateDirectories: true)
    }
    print("Saving result to \(url.path)")
    try results.save(to: url)
  }
  
  func compare(against compareFilePath: String, showChart: Bool) throws {
    let compareFileURL = URL(fileURLWithPath: compareFilePath)
    let compareResult = try SuiteResult.load(from: compareFileURL)
    let compareFile = compareFileURL.lastPathComponent

    let diff = results
      .compare(with: compareResult)
      .filter({(name, _) in !name.contains("_NS")})
    let regressions = diff.filter({(_, change) in change.seconds > 0})
      .sorted(by: {(a,b) in a.1 > b.1})
    let improvements = diff.filter({(_, change) in change.seconds < 0})
      .sorted(by: {(a,b) in a.1 < b.1})
    
    print("Comparing against benchmark result file \(compareFile)")
    print("=== Regressions ======================================================================")
    func printComparison(name: String, diff: Time) {
      let oldVal = compareResult.results[name]!.median
      let newVal = results.results[name]!.median
      let percentage = (1000 * diff.seconds / oldVal.seconds).rounded()/10
      let len = max(40 - name.count, 1)
      let nameSpacing = String(repeating: " ", count: len)
      print("- \(name)\(nameSpacing)\(newVal)\t\(oldVal)\t\(diff)\t\t\(percentage)%")
    }
    
    for item in regressions {
      printComparison(name: item.key, diff: item.value)
    }
    
    print("=== Improvements =====================================================================")
    for item in improvements {
      printComparison(name: item.key, diff: item.value)
    }

    #if os(macOS)
    if showChart {
      print("""
        === Comparison chart =================================================================
        Press Control-C to close...
        """)
      BenchmarkResultApp.comparisons = {
        var comparisons: [BenchmarkChart.Comparison] = []
        for (name, baseline) in compareResult.results {
          if let latest = results.results[name] {
            comparisons.append(
              .init(name: name, baseline: baseline, latest: latest))
          }
        }
        return comparisons.sorted {
          let delta0 = Float($0.latest.median.seconds - $0.baseline.median.seconds)
            / Float($0.baseline.median.seconds)
          let delta1 = Float($1.latest.median.seconds - $1.baseline.median.seconds)
            / Float($1.baseline.median.seconds)
          return delta0 > delta1
        }
      }()
      BenchmarkResultApp.main()
    }
    #endif
  }
}

struct BenchmarkResult: Codable {
  let median: Time
  let stdev: Double
  let samples: Int

  init(_ median: Time, _ stdev: Double, _ samples: Int) {
    self.median = median
    self.stdev = stdev
    self.samples = samples
  }
}

struct SuiteResult {
  var results: [String: BenchmarkResult] = [:]
  
  mutating func add(name: String, result: BenchmarkResult) {
    results.updateValue(result, forKey: name)
  }
  
  func compare(with other: SuiteResult) -> [String: Time] {
    var output: [String: Time] = [:]
    for item in results {
      if let otherVal = other.results[item.key] {
        let diff = item.value.median - otherVal.median
        if Stats.tTest(item.value, otherVal) {
          output.updateValue(diff, forKey: item.key)
        }
      }
    }
    return output
  }
}

extension SuiteResult: Codable {
  func save(to url: URL) throws {
    let encoder = JSONEncoder()
    let data = try encoder.encode(self)
    try data.write(to: url, options: .atomic)
  }
  
  static func load(from url: URL) throws -> SuiteResult {
    let decoder = JSONDecoder()
    let data = try Data(contentsOf: url)
    return try decoder.decode(SuiteResult.self, from: data)
  }
}
