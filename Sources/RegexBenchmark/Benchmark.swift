@_spi(RegexBenchmark) import _StringProcessing
@_implementationOnly import _RegexParser
import Foundation

protocol RegexBenchmark: Debug {
  var name: String { get }
  func run()
}

protocol SwiftRegexBenchmark: RegexBenchmark {
  var regex: Regex<AnyRegexOutput> { get set }
  var pattern: String? { get }
}

extension SwiftRegexBenchmark {
  mutating func compile() {
    let _ = regex._forceAction(.recompile)
  }
  mutating func parse() -> Bool {
    guard let s = pattern else {
      return false
    }
    
    do {
      let _ = try _RegexParser.parse(s, .traditional)
      return true
    } catch {
      return false
    }
  }
  mutating func enableTracing() {
    let _ = regex._forceAction(.addOptions(.enableTracing))
  }
  mutating func enableMetrics() {
    let _ = regex._forceAction(.addOptions([.enableMetrics]))
  }
}

struct Benchmark: SwiftRegexBenchmark {
  let name: String
  var regex: Regex<AnyRegexOutput>
  let pattern: String?
  let type: MatchType
  let target: String

  enum MatchType {
    case whole
    case first
    case allMatches
  }
  
  func run() {
    switch type {
    case .whole: blackHole(target.wholeMatch(of: regex))
    case .allMatches: blackHole(target.matches(of: regex))
    case .first: blackHole(target.firstMatch(of: regex))
    }
  }
}

struct NSBenchmark: RegexBenchmark {
  let name: String
  let regex: NSRegularExpression
  let type: NSMatchType
  let target: String
  
  var range: NSRange {
    NSRange(target.startIndex..<target.endIndex, in: target)
  }

  enum NSMatchType {
    case allMatches
    case first

    init(_ type: Benchmark.MatchType) {
      switch type {
      case .whole, .first: self = .first
      case .allMatches: self = .allMatches
      }
    }
  }
  
  func run() {
    switch type {
    case .allMatches: blackHole(regex.matches(in: target, range: range))
    case .first: blackHole(regex.firstMatch(in: target, range: range))
    }
  }
}

/// A benchmark running a regex on strings in input set
struct InputListBenchmark: SwiftRegexBenchmark {
  let name: String
  var regex: Regex<AnyRegexOutput>
  let pattern: String?
  let targets: [String]

  func run() {
    for target in targets {
      blackHole(target.wholeMatch(of: regex))
    }
  }
}

struct InputListNSBenchmark: RegexBenchmark {
  let name: String
  let regex: NSRegularExpression
  let targets: [String]
  
  init(name: String, regex: String, targets: [String]) {
    self.name = name
    self.regex = try! NSRegularExpression(pattern: "^" + regex + "$")
    self.targets = targets
  }
  
  func range(in target: String) -> NSRange {
    NSRange(target.startIndex..<target.endIndex, in: target)
  }

  func run() {
    for target in targets {
      let range = range(in: target)
      blackHole(regex.firstMatch(in: target, range: range))
    }
  }
}

/// A benchmark meant to be ran across multiple engines
struct CrossBenchmark {
  /// Suffix added onto NSRegularExpression benchmarks
  static var nsSuffix: String { "_NS" }
  
  /// The base name of the benchmark
  var baseName: String

  /// The string to compile in different engines
  var regex: String

  /// The text to search
  var input: String

  // TODO: var output, for validation

  /// Whether this is whole string matching or a searching benchmark
  ///
  /// TODO: Probably better ot have a whole-line vs search anywhere, maybe
  /// accomodate multi-line matching, etc.
  var isWhole: Bool = false
  
  /// Whether or not to do firstMatch as well or just allMatches
  var includeFirst: Bool = false

  /// Whether to also run scalar-semantic mode
  var alsoRunScalarSemantic: Bool = true

  func register(_ runner: inout BenchmarkRunner) {
    if isWhole {
      runner.registerCrossBenchmark(
        nameBase: baseName,
        input: input,
        pattern: regex,
        .whole,
        alsoRunScalarSemantic: alsoRunScalarSemantic)
    } else {
      runner.registerCrossBenchmark(
        nameBase: baseName,
        input: input,
        pattern: regex,
        .allMatches,
        alsoRunScalarSemantic: alsoRunScalarSemantic)

      if includeFirst || runner.includeFirstOverride {
        runner.registerCrossBenchmark(
          nameBase: baseName,
          input: input,
          pattern: regex,
          .first,
          alsoRunScalarSemantic: alsoRunScalarSemantic)
      }
    }
  }
}

/// A benchmark running a regex on strings in input list, run across multiple engines
struct CrossInputListBenchmark {
  /// The base name of the benchmark
  var baseName: String

  /// The string to compile in differnet engines
  var regex: String

  /// The list of strings to search
  var inputs: [String]

  /// Also run in scalar-semantic mode
  var alsoRunScalarSemantic: Bool = true
  
  func register(_ runner: inout BenchmarkRunner) {
    runner.registerCrossBenchmark(
      name: baseName,
      inputList: inputs,
      pattern: regex,
      alsoRunScalarSemantic: alsoRunScalarSemantic)
  }
}

// TODO: Capture-containing benchmarks

// nom nom nom, consume the argument
@inline(never)
func blackHole<T>(_ x: T) {
}
