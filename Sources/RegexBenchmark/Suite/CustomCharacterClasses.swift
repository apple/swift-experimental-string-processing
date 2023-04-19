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
    
    // TODO: Which of these can be cross-benchmarks?

    register(
      nameBase: "BasicCCC",
      input: input,
      pattern: basic,
      try! Regex(basic),
      .allMatches)
    
    register(
      nameBase: "BasicRangeCCC",
      input: input,
      pattern: basicRange,
      try! Regex(basicRange),
      .allMatches)
    
    register(
      nameBase: "CaseInsensitiveCCC",
      input: input,
      pattern: caseInsensitive,
      try! Regex(caseInsensitive),
      .allMatches)
    
    register(
      nameBase: "InvertedCCC",
      input: input,
      pattern: inverted,
      try! Regex(inverted),
      .allMatches)
    
    register(
      nameBase: "SubtractionCCC",
      input: input,
      pattern: subtraction,
      try! Regex(subtraction),
      .allMatches)
    
    register(
      nameBase: "IntersectionCCC",
      input: input,
      pattern: intersection,
      try! Regex(intersection),
      .allMatches)
    
    register(
      nameBase: "symDiffCCC",
      input: input,
      pattern: symmetricDifference,
      try! Regex(symmetricDifference),
      .allMatches)
  }
}
