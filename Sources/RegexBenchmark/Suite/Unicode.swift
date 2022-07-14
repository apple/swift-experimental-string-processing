import _StringProcessing

extension BenchmarkRunner {
  mutating func addUnicode() {
    // tagged unicode: unicode characters surrounded by html tags
    // use the same html regex, uses backreference + reluctant quantification
    let tags = #"<(\w*)\b[^>]*>(.*?)<\/\1>"#
    let taggedEmojis = CrossBenchmark(
      baseName: "TaggedEmojis",
      regex: tags,
      input: Inputs.taggedEmojis)

    // Now actually matching emojis
    let emoji = #"(😃|😀|😳|😲|😦|😊|🙊|😘|😏|😳|😒){2,5}"#
    
    let emojiRegex = CrossBenchmark(
      baseName: "EmojiRegex",
      regex: emoji,
      input: Inputs.taggedEmojis)

    // taggedEmojis.register(&self) // disabled due to \b being unusably slow
    emojiRegex.register(&self)
  }
}
