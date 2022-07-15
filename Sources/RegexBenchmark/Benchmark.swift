import _StringProcessing
import Foundation

public protocol RegexBenchmark {
  var name: String { get }
  func run()
  func debug()
}

public struct Benchmark: RegexBenchmark {
  public let name: String
  let regex: Regex<AnyRegexOutput>
  let type: MatchType
  let target: String

  public enum MatchType {
    case whole
    case first
    case allMatches
  }
  
  public func run() {
    switch type {
    case .whole: blackHole(target.wholeMatch(of: regex))
    case .allMatches: blackHole(target.matches(of: regex))
    case .first: blackHole(target.firstMatch(of: regex))
    }
  }
}

public struct NSBenchmark: RegexBenchmark {
  public let name: String
  let regex: NSRegularExpression
  let type: NSMatchType
  let target: String
  
  var range: NSRange {
    NSRange(target.startIndex..<target.endIndex, in: target)
  }

  public enum NSMatchType {
    case allMatches
    case first
  }
  
  public func run() {
    switch type {
    case .allMatches: blackHole(regex.matches(in: target, range: range))
    case .first: blackHole(regex.firstMatch(in: target, range: range))
    }
  }
}

/// A benchmark meant to be ran across multiple engines
struct CrossBenchmark {
  /// The base name of the benchmark
  var baseName: String

  /// The string to compile in differnet engines
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

  func register(_ runner: inout BenchmarkRunner) {
    let swiftRegex = try! Regex(regex)
    let nsRegex: NSRegularExpression
    if isWhole {
      nsRegex = try! NSRegularExpression(pattern: "^" + regex + "$")
    } else {
      nsRegex = try! NSRegularExpression(pattern: regex)
    }

    if isWhole {
      runner.register(
        Benchmark(
          name: baseName + "Whole",
          regex: swiftRegex,
          type: .whole,
          target: input))
      runner.register(
        NSBenchmark(
          name: baseName + "Whole_NS",
          regex: nsRegex,
          type: .first,
          target: input))
    } else {
      runner.register(
        Benchmark(
          name: baseName + "All",
          regex: swiftRegex,
          type: .allMatches,
          target: input))
      runner.register(
        NSBenchmark(
          name: baseName + "All_NS",
          regex: nsRegex,
          type: .allMatches,
          target: input))
      if includeFirst {
        runner.register(
          Benchmark(
            name: baseName + "First",
            regex: swiftRegex,
            type: .first,
            target: input))
        runner.register(
          NSBenchmark(
            name: baseName + "First_NS",
            regex: nsRegex,
            type: .first,
            target: input))
      }
    }
  }
}

// TODO: Capture-containing benchmarks

// nom nom nom, consume the argument
@inline(never)
public func blackHole<T>(_ x: T) {
}
