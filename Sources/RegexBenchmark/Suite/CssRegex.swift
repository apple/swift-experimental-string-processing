import Foundation
import _StringProcessing

extension BenchmarkRunner {
  mutating func addCSS() {
    let r = #"--([a-zA-Z0-9_-]+)\s*:\s*(.*?);"#

    let css = CrossBenchmark(
      baseName: "Css", regex: r, input: Inputs.swiftOrgCSS)
    css.register(&self)
  }
}
