import _StringProcessing

extension BenchmarkRunner {
  mutating func addDna() {
    // regex-redux from the benchmarks game
    // https://benchmarksgame-team.pages.debian.net/benchmarksgame/description/regexredux.html#regexredux
    let dna = "agg[act]taaa|ttta[agt]cct"
    let ends = "aND|caN|Ha[DS]|WaS"
    
    let dnaMatching = CrossBenchmark(
      baseName: "DnaMatch",
      regex: dna,
      input: Inputs.dnaFASTA,
      includeFirst: true)
    
    let sequenceEnds = CrossBenchmark(
      baseName: "DnaEndsMatch",
      regex: ends,
      input: Inputs.dnaFASTA,
      includeFirst: true)
    
    dnaMatching.register(&self)
    sequenceEnds.register(&self)
  }
}
