import ArgumentParser

@main
struct Runner: ParsableCommand {
  @Argument(help: "Patterns for benchmarks to run")
  var specificBenchmarks: [String] = []
  
  @Flag(help: "Run only once for profiling purposes")
  var profile = false
  
  @Option(help: "How many samples to collect for each benchmark")
  var samples = 20
  
  @Flag(help: "Debug benchmark regexes")
  var debug = false
  
  @Option(help: "Output folder")
  var outputPath = "./results/"
  
  @Flag(help: "Should the results be saved")
  var save = false
  
  @Flag(help: "Compare this result with a saved result")
  var compare = false
  
  @Option(help: "The result file to compare against, if this flag is not set it will compare against the most recent result file")
  var compareFile: String?
  
  @Flag(help: "Exclude the comparisons to NSRegex")
  var excludeNs = false
  
  mutating func run() throws {
    var runner = BenchmarkRunner.makeRunner(samples, outputPath)
        
    if !self.specificBenchmarks.isEmpty {
      runner.suite = runner.suite.filter { b in
        specificBenchmarks.contains { pattern in
          try! Regex(pattern).wholeMatch(in: b.name) != nil
        }
      }
    }
    
    if excludeNs {
      runner.suite = runner.suite.filter { b in !b.name.contains("NS") }
    }
    
    switch (profile, debug) {
    case (true, true): print("Cannot run both profile and debug")
    case (true, false): runner.profile()
    case (false, true): runner.debug()
    case (false, false):
      runner.run()
      if compare {
        try runner.compare(against: compareFile)
      }
      if save {
        try runner.save()
      }
    }
  }
}
