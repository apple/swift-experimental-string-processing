# String processing algorithms

## Introduction

The Swift standard library's string processing algorithms are underpowered compared to other popular programming and scripting languages. Some of these omissions can be papered over through bridged `NSString` API available through the Foundation framework, but these are still incomplete and bring in linkage requirements to Foundation.

We propose:

1. New regex-powered algorithms over strings, bringing the standard library up to parity with scripting languages
2. Generic `Collection` equivalents of these algorithms in terms of subsequences
3. `protocol CustomRegexComponent`, allowing libraries to vend types that can be intermixed as components of regexes

This proposal is part of a larger [regex-powered string processing initiative](https://forums.swift.org/t/declarative-string-processing-overview/52459). Throughout the document, we will reference the still-in-progress [`RegexProtocol`, `Regex`](https://github.com/apple/swift-experimental-string-processing/blob/main/Documentation/Evolution/StronglyTypedCaptures.md), and [result builder DSL](https://forums.swift.org/t/pitch-regular-expression-literals/52820), but these are in flux and not formally part of this proposal. Further discussion of regex specifics is out of scope of this proposal and better discussed in another thread (see [Pitch and Proposal Status](https://github.com/apple/swift-experimental-string-processing/issues/107) for links to relevant threads).

## Motivation

Many essential string processing APIs are currently missing in the standard library, and has always been a popular ask in the community. Here, we propose to bridge the gap of Swift String API to Python and those from `NSString`. Let's take a look at what Python and `NSString` currently offers:

### Process domain-specific strings

Processing strings that requires domain specific information is a common task. 

Consider parsing the date field `"Date: Wed, 16 Feb 2022 23:53:19 GMT"` in an HTTP header as a `Date` type. A common approach is to match a substring that look like a date string (`16 Feb 2022`), and post-process the substring as a `Date` using one of the date parsers in the Foundation:

```swift
let regex = Regex {
    capture {
        oneOrMore(.digit)
        " "
        oneOrMore(.word)
        " "
        oneOrMore(.digit)
    }
}

let dateParser = Date.ParseStrategy(format: "\(day: .twoDigits) \(month: .abbreviated) \(year: .padded(4))"
if let dateMatch = header.firstMatch(of: regex)?.0 {
    let date = try? Date(dateMatch, strategy: dateParser)
}
```

While this approach happens to work for this example, it is fragile when it comes to localized strings. 

Or consider parsing a bank statement to record all the monetary values in the last column:

```swift
let statement = """
CREDIT    04/06/2020    Paypal transfer    $4.99
CREDIT    04/03/2020    Payroll            $69.73
DEBIT     04/02/2020    ACH transfer       ($38.25)
DEBIT     03/24/2020    IRX tax payment    ($52,249.98)
"""
```

Parsing a currency string such as `$3,020.85` with regex is also tricky, as it can contain localized and currency symbols. This is why Foundation provides industrial-strength parsers for localized strings like these. 

We propose a `CustomRegexComponent` protocol which allows types from outside the standard library participate in regex builders and `RegexProtocol` algorithms. This allows types, such as `Date.ParseStrategy` and `FloatingPointFormatStyle.Currency`, to be used directly within a regex.

```swift
let dateRegex = Regex {
    capture(dateParser)
}

let date = header.firstMatch(of: dateRegex).map(\.result.1) 
// A `Date` representing 2022-02-16 00:00:00 +0000

let currencyRegex = Regex {
    capture(.localizedCurrency(code: "USD").sign(strategy: .accounting))
}

let amount = statement.matches(of: currencyRegex).map(\.result.1)
// [4.99, 69.73, -38.25, -52249.98]
```


## Proposed solution and detailed design 

### String algorithm additions

The following regex-powered algorithms as well as their generic `Collection` equivalents are included in this pitch:

#### Contains

```swift
extension Collection where Element: Equatable {
    /// Returns a Boolean value indicating whether the collection contains the
    /// given sequence.
    /// - Parameter other: A sequence to search for within this collection.
    /// - Returns: `true` if the collection contains the specified sequence,
    /// otherwise `false`.
    public func contains<S: Sequence>(_ other: S) -> Bool
        where S.Element == Element
}

extension BidirectionalCollection where SubSequence == Substring {
    /// Returns a Boolean value indicating whether the collection contains the
    /// given regex.
    /// - Parameter regex: A regex to search for within this collection.
    /// - Returns: `true` if the regex was found in the collection, otherwise
    /// `false`.
    public func contains<R: RegexProtocol>(_ regex: R) -> Bool
}
```

#### Starts with

```swift
extension BidirectionalCollection where SubSequence == Substring {
    /// Returns a Boolean value indicating whether the initial elements of the
    /// sequence are the same as the elements in the specified regex.
    /// - Parameter regex: A regex to compare to this sequence.
    /// - Returns: `true` if the initial elements of the sequence matches the
    /// beginning of `regex`; otherwise, `false`.
    public func starts<R: RegexProtocol>(with regex: R) -> Bool
}
```

#### Trim prefix

```swift
extension Collection {
    /// Returns a new collection of the same type by removing initial elements
    /// that satisfy the given predicate from the start
    /// - Parameter predicate: A closure that takes an element of the sequence
    /// as its argument and returns a Boolean value indicating whether the
    /// element should be removed from the collection.
    /// - Returns: A collection containing the elements of the receiver that are
    ///  not removed by `predicate`.
    public func trimmingPrefix(while predicate: (Element) -> Bool) -> SubSequence
}

extension Collection where SubSequence == Self {
    /// Removes the initial elements that satisfy the given predicate from the
    /// start of the sequence.
    /// - Parameter predicate: A closure that takes an element of the sequence
    /// as its argument and returns a Boolean value indicating whether the
    /// element should be removed from the collection.
    public mutating func trimPrefix(while predicate: (Element) -> Bool)
}

extension RangeReplaceableCollection {
    /// Removes the initial elements that satisfy the given predicate from the
    /// start of the sequence.
    /// - Parameter predicate: A closure that takes an element of the sequence
    /// as its argument and returns a Boolean value indicating whether the
    /// element should be removed from the collection.
    public mutating func trimPrefix(while predicate: (Element) -> Bool)
}

extension Collection where Element: Equatable {
    public func trimmingPrefix<Prefix: Collection>(_ prefix: Prefix) -> SubSequence
        where Prefix.Element == Element
}

extension Collection where SubSequence == Self, Element: Equatable {
    public mutating func trimPrefix<Prefix: Collection>(_ prefix: Prefix)
        where Prefix.Element == Element
}

extension RangeReplaceableCollection where Element: Equatable {
    public mutating func trimPrefix<Prefix: Collection>(_ prefix: Prefix)
        where Prefix.Element == Element
}

extension BidirectionalCollection where SubSequence == Substring {
    public func trimmingPrefix<R: RegexProtocol>(_ regex: R) -> SubSequence
}

extension RangeReplaceableCollection
  where Self: BidirectionalCollection, SubSequence == Substring
{
    public mutating func trimPrefix<R: RegexProtocol>(_ regex: R)
}
```

#### First range

```swift
extension Collection where Element: Equatable {
    public func firstRange<S: Sequence>(of sequence: S) -> Range<Index>? 
        where S.Element == Element
}

extension BidirectionalCollection where Element: Comparable {
    public func firstRange<S: Sequence>(of other: S) -> Range<Index>?
        where S.Element == Element
}

extension BidirectionalCollection where SubSequence == Substring {
    public func firstRange<R: RegexProtocol>(of regex: R) -> Range<Index>?
}
```

#### Ranges

```swift
extension Collection where Element: Equatable {
    public func ranges<S: Sequence>(of other: S) -> some Collection<Range<Index>>
        where S.Element == Element
}

extension BidirectionalCollection where SubSequence == Substring {
    public func ranges<R: RegexProtocol>(of regex: R) -> some Collection<Range<Index>>
}
```

#### First match

```swift
extension BidirectionalCollection where SubSequence == Substring {
    public func firstMatch<R: RegexProtocol>(of regex: R) -> RegexMatch<R.Match>?
}
```

#### Matches

```swift
extension BidirectionalCollection where SubSequence == Substring {
    public func matches<R: RegexProtocol>(of regex: R) -> some Collection<RegexMatch<R.Match>>
}
```

#### Replace

```swift
extension RangeReplaceableCollection where Element: Equatable {
    public func replacing<S: Sequence, Replacement: Collection>(
        _ other: S,
        with replacement: Replacement,
        subrange: Range<Index>,
        maxReplacements: Int = .max
    ) -> Self where S.Element == Element, Replacement.Element == Element
  
    public func replacing<S: Sequence, Replacement: Collection>(
        _ other: S,
        with replacement: Replacement,
        maxReplacements: Int = .max
    ) -> Self where S.Element == Element, Replacement.Element == Element
  
    public mutating func replace<S: Sequence, Replacement: Collection>(
        _ other: S,
        with replacement: Replacement,
        maxReplacements: Int = .max
    ) where S.Element == Element, Replacement.Element == Element
}

extension RangeReplaceableCollection where SubSequence == Substring {
    public func replacing<R: RegexProtocol, Replacement: Collection>(
        _ regex: R,
        with replacement: Replacement,
        subrange: Range<Index>,
        maxReplacements: Int = .max
    ) -> Self where Replacement.Element == Element
  
    public func replacing<R: RegexProtocol, Replacement: Collection>(
        _ regex: R,
        with replacement: Replacement,
        maxReplacements: Int = .max
    ) -> Self where Replacement.Element == Element
  
    public mutating func replace<R: RegexProtocol, Replacement: Collection>(
        _ regex: R,
        with replacement: Replacement,
        maxReplacements: Int = .max
    ) where Replacement.Element == Element
  
    public func replacing<R: RegexProtocol, Replacement: Collection>(
        _ regex: R,
        with replacement: (RegexMatch<R.Match>) throws -> Replacement,
        subrange: Range<Index>,
        maxReplacements: Int = .max
    ) rethrows -> Self where Replacement.Element == Element
  
    public func replacing<R: RegexProtocol, Replacement: Collection>(
        _ regex: R,
        with replacement: (RegexMatch<R.Match>) throws -> Replacement,
        maxReplacements: Int = .max
    ) rethrows -> Self where Replacement.Element == Element
  
    public mutating func replace<R: RegexProtocol, Replacement: Collection>(
        _ regex: R,
        with replacement: (RegexMatch<R.Match>) throws -> Replacement,
        maxReplacements: Int = .max
    ) rethrows where Replacement.Element == Element
}
```

#### Split

```swift
extension Collection where Element: Equatable {
    public func split<S: Sequence>(by separator: S) -> some Collection<SubSequence>
        where S.Element == Element
}

extension BidirectionalCollection where SubSequence == Substring {
    public func split<R: RegexProtocol>(by separator: R) -> some Collection<Substring>
}
```


### `CustomRegexComponent`

`CustomRegexComponent` inherits from `RegexProtocol` and satisfies its sole requirement. 

```swift
public protocol CustomRegexComponent: RegexProtocol {
    /// Match the input string within the specified bounds, beginning at the given index, and return
    /// the end position (upper bound) of the match and the matched instance.
    /// - Parameters:
    ///   - input: The string in which the match is performed.
    ///   - index: An index of `input` at which to begin matching.
    ///   - bounds: The bounds in `input` in which the match is performed.
    /// - Returns: The upper bound where the match terminates and a matched instance, or nil if
    ///   there isn't a match.
    func match(
        _ input: String,
        startingAt index: String.Index,
        in bounds: Range<String.Index>
    ) -> (upperBound: String.Index, match: Match)?
}
```

Conformers naturally inherit from `RegexProtocol`, so they can be used with all of the string algorithms generic over `RegexProtocol`.

Here, we use Foundation `FloatingPointFormatStyle<Double>.Currency` as an example. `FloatingPointFormatStyle<Double>.Currency` would conform to `CustomRegexComponent` by implementing the `match` function, with `Match` being a `Double`. It could also add a static function `.localizedCurrency(code:)` as a member of `RegexProtocol`, so you can refer to it as `.localizedCurrency(code:)` in the `Regex` result builder. 

```swift
extension FloatingPointFormatStyle<Double>.Currency : CustomRegexComponent { 
    func match(
        _ input: String,
        startingAt index: String.Index,
        in bounds: Range<String.Index>
    ) -> (upperBound: String.Index, match: Double)?
}

extension RegexProtocol where Self == FloatingPointFormatStyle<Double>.Currency {
    public static func localizedCurrency(code: Locale.Currency) -> Self
}
```

Matching and extracting a localized currency amount, such as `"$3,020.85"`, can be done directly within a regex:

```swift
let regex = Regex {
    capture(.localizedCurreny(code: "USD"))
}
```


## Alternatives considered

### Extend `Sequence` instead of `Collection`

All of the proposed algorithms are specific to the `Collection` protocol, without support for plain `Sequence`s. Types conforming to the `Sequence` protocol are not required to support multi-pass iteration, which makes a `Sequence` conformance insufficient for most of these algorithms. In light of this, the decision was made to have the underlying shared algorithm implementations work exclusively with `Collection`s.

## Future directions

### Backward algorithms

There are some unanswered questions about algorithms that operate from the back of a collection.

There is a subtle difference between finding the last non-overlapping range of a pattern in a string, and finding the first range of this pattern when searching from the back. `"aaaaa".ranges(of: "aa")` produces two non-overlapping ranges, splitting the string in the chunks `aa|aa|a`. It would not be completely unreasonable to expect `"aaaaa".lastRange(of: "aa")` to be shorthand for `"aaaaa".ranges(of: "aa").last`, i.e. to return the range that contains the third and fourth characters of the string. Yet, the first range of `"aa"` when searching from the back of the string yields the range that contains the fourth and fifth characters.

It is not obvious whether both of these notions of what it means for a range to be the "last" range should be supported, or what names should be used in order to disambiguate them. It is also worth noting that some kinds of patterns do behave nicely and always produce the same results when searching forwards or backwards, e.g. `myInts.lastIndex(where: { $0 > 10 })` is unambiguous. These kinds of patterns might warrant special treatment when designing algorithms that process the collection in reverse.

Similar questions arise when trimming a string from both sides: `"ababa".trimming("aba")` can return either `"ba"` or `"ab"`, depending on whether the prefix or the suffix was trimmed first.

### Throwing closures

The closure parameters of `trimPrefix(while:)` and `replace(_:with:)` aren't marked `throws` and the methods themselves aren't marked `rethrows`, because the shared implementations of these groups of related algorithms do not yet support error handling.

### Open up the shared algorithm implementations for user-defined types

At this point we have not settled on a final design for the protocol hierarchy that the shared algorithm implementations rely on, so we are not ready to expose this infrastructure and stabilize the entire ABI. We aim to eventually open up the ability for users to pass their own types to these `Collection` algorithms without having to go through the `RegexProtocol` overload which creates an intermediate `Regex` instance.
