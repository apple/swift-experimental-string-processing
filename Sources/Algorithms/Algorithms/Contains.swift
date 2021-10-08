extension Collection where Element: Equatable {
  public func contains<S: Sequence>(_ other: S) -> Bool where S.Element == Element {
    firstRange(of: other) != nil
  }
}

extension BidirectionalCollection where Element: Comparable {
  public func contains<S: Sequence>(_ other: S) -> Bool where S.Element == Element {
    firstRange(of: other) != nil
  }
}
