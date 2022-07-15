import _StringProcessing
import Foundation

extension BenchmarkRunner {
  mutating func addNotFound() {
    let input = String(repeating: " ", count: 100_000)

    let notFound = CrossBenchmark(
      baseName: "NotFound", regex: "a", input: input)
    notFound.register(&self)

    let anchoredNotFound = CrossBenchmark(
      baseName: "AnchoredNotFound", regex: "^ +a", input: input)
    anchoredNotFound.register(&self)
  }
}
