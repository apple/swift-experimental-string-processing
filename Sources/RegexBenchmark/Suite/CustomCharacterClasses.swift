import _StringProcessing

extension BenchmarkRunner {
  mutating func addCustomCharacterClasses() {
    let basic = #"[abCDeiou'~]{4,6}"#
    let basicRange = #"[a-z]{4,6}"#
    let caseInsensitive = #"(?i)[abCDeiou'~]{4,6}"#
    let inverted = #"[^jskldfjoi]{4,6}"#
    let subtraction = #"[a-z--[ae]]{4,6}"#
    let intersection = #"[a-z&&[abcdeiou]]{4,6}"#
    let symmetricDifference = #"[a-z~~[jskldfjoi]]{4,6}"#
    
    let input = Inputs.graphemeBreakData
    
    register(Benchmark(
      name: "BasicCCC",
      regex: try! Regex(basic),
      type: .allMatches,
      target: input))
    
    register(Benchmark(
      name: "BasicRangeCCC",
      regex: try! Regex(basicRange),
      type: .allMatches,
      target: input))
    
    register(Benchmark(
      name: "CaseInsensitiveCCC",
      regex: try! Regex(caseInsensitive),
      type: .allMatches,
      target: input))
    
    register(Benchmark(
      name: "InvertedCCC",
      regex: try! Regex(inverted),
      type: .allMatches,
      target: input))
    
    register(Benchmark(
      name: "SubtractionCCC",
      regex: try! Regex(subtraction),
      type: .allMatches,
      target: input))
    
    register(Benchmark(
      name: "IntersectionCCC",
      regex: try! Regex(intersection),
      type: .allMatches,
      target: input))
    
    register(Benchmark(
      name: "symDiffCCC",
      regex: try! Regex(symmetricDifference),
      type: .allMatches,
      target: input))
  }
}
