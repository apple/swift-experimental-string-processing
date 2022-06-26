# Regex DSL API Walkthrough

## Core

### Core abstractions

```swift
public protocol RegexProtocol {
  associatedtype Match
  var regex: Regex<Match> { get }
}

public struct Regex<Match>: RegexProtocol {
  public var regex: Regex<Match> { get }

  public init<Content: RegexProtocol>(
    _ content: Content
  ) where Content.Match == Match
   
  public init<Content: RegexProtocol>(
    @RegexBuilder _ content: () -> Content
  ) where Content.Match == Match
}
```

### Regex-y types

```swift
extension String: RegexProtocol {
  public typealias Match = Substring
  public var regex: Regex<Match>
}

extension String: RegexProtocol {
  public typealias Match = Substring
  public var regex: Regex<Match>
}

extension Character: RegexProtocol {
  public typealias Match = Substring
  public var regex: Regex<Match>
}

extension CharacterClass: RegexProtocol {
  public typealias Match = Substring
  public var regex: Regex<Match>
}
```

## Concatenation

### API

```swift
public init<Content: RegexProtocol>(
  _ content: Content
) where Content.Match == Match
 
public init<Content: RegexProtocol>(
  @RegexBuilder _ content: () -> Content
) where Content.Match == Match
```

... and anything that takes a `@RegexBuilder` closure.

### Builder

```swift
@resultBuilder
public enum RegexBuilder {
  public static func buildExpression<R: RegexProtocol>(_ regex: R) -> R {
    regex
  }

  public static func buildEither<R: RegexProtocol>(first component: R) -> R {
    component
  }

  public static func buildEither<R: RegexProtocol>(second component: R) -> R {
    component
  }
  
  // Base case
  
  @_disfavoredOverload
  public static func buildBlock<R0: RegexProtocol>(_ r0: R0) -> R0 {
    r0
  }

  // Starts arity^2 overloads
  
  public static func buildBlock<W0, W1, C0, R0: RegexProtocol, R1: RegexProtocol>(
    combining next: R1, into combined: R0
  ) -> Regex<(Substring, C0)>  where R0.Match == W0, R1.Match == (W1, C0) {
    .init(node: combined.regex.root.appending(next.regex.root))
  }
  
  public static func buildBlock<W0, W1, C0, C1, R0: RegexProtocol, R1: RegexProtocol>(
    combining next: R1, into combined: R0
  ) -> Regex<(Substring, C0, C1)>  where R0.Match == W0, R1.Match == (W1, C0, C1) {
    .init(node: combined.regex.root.appending(next.regex.root))
  }
  
  public static func buildBlock<W0, W1, C0, C1, C2, R0: RegexProtocol, R1: RegexProtocol>(
    combining next: R1, into combined: R0
  ) -> Regex<(Substring, C0, C1, C2)>  where R0.Match == W0, R1.Match == (W1, C0, C1, C2) {
    .init(node: combined.regex.root.appending(next.regex.root))
  }

  ...
```

## Quantification

### Overview

- `oneOrMore`, `.+`, `many`, `.*`
  - Takes `Regex<(WholeMatch, Capture...)>`
  - Returns `Regex<(WholeMatch, [(Capture...)])>`

- `optionally`, `.?`
  - Takes `Regex<(WholeMatch, Capture...)>`
  - Returns `Regex<(WholeMatch, (Capture...)?)>`

### Example

```swift
let regex = Regex {
  "a".+
  oneOrMore(.whitespace)
  optionally {
    capture(oneOrMore(.digit)) { Int($0)! }
  }
  many {
    oneOrMore(.whitespace)
    capture(oneOrMore(.word)) { Word($0)! }
  }
} // Regex<(Substring, Int?, [Word])>
```

### User API

```swift
// Nullary capture

@_disfavoredOverload
public func oneOrMore<Component: RegexProtocol>(
  _ component: Component
) -> Regex<Substring>  {
  .init(node: .quantification(.oneOrMore, .eager, component.regex.root))
}

@_disfavoredOverload
public func oneOrMore<Component: RegexProtocol>(
  @RegexBuilder _ component: () -> Component
) -> Regex<Substring>  {
  .init(node: .quantification(.oneOrMore, .eager, component().regex.root))
}

// Unary capture

public func oneOrMore<W, C0, Component: RegexProtocol>(
  _ component: Component
) -> Regex<(Substring, [C0])> where Component.Match == (W, C0) {
  .init(node: .quantification(.oneOrMore, .eager, component.regex.root))
}

public func oneOrMore<W, C0, Component: RegexProtocol>(
  @RegexBuilder _ component: () -> Component
) -> Regex<(Substring, [C0])> where Component.Match == (W, C0) {
  .init(node: .quantification(.oneOrMore, .eager, component().regex.root))
}

// Binary capture

public func oneOrMore<W, C0, C1, Component: RegexProtocol>(
  _ component: Component
) -> Regex<(Substring, [(C0, C1)])> where Component.Match == (W, C0, C1) {
  .init(node: .quantification(.oneOrMore, .eager, component.regex.root))
}


public func oneOrMore<W, C0, C1, Component: RegexProtocol>(
  @RegexBuilder _ component: () -> Component
) -> Regex<(Substring, [(C0, C1)])> where Component.Match == (W, C0, C1) {
  .init(node: .quantification(.oneOrMore, .eager, component().regex.root))
}

...
```

### Overloads for `CharacterClass` operand

```swift
// Overloads for quantifying over a character class.
public func zeroOrOne(_ cc: CharacterClass) -> Regex<Substring> {
  .init(node: .quantification(.zeroOrOne, .eager, cc.regex.root))
}

public func many(_ cc: CharacterClass) -> Regex<Substring> {
  .init(node: .quantification(.zeroOrMore, .eager, cc.regex.root))
}

public func oneOrMore(_ cc: CharacterClass) -> Regex<Substring> {
  .init(node: .quantification(.oneOrMore, .eager, cc.regex.root))
}
```

## Alternation

### Overview

- `oneOf { ... }` takes regexes with `Match == (WholeMatch, Capture...)`, and returns `Regex<(Substring, Capture?...)>` with all captures concatenated as optionals.
- `|` is the binary form of `oneOf`.

### Example

```swift
let regex = oneOf {
  capture("aaa")
  capture("bbb")
  capture("ccc")
} // => (Substring, Substring?, Substring?, Substring?)
```

### API

Very simple. Maybe better to add more generic constraints?

```swift
public func oneOf<R: RegexProtocol>(
  @AlternationBuilder builder: () -> R
) -> R {
  builder()
}
```

Binary operators (up to 10-ary captures)

```swift
public func | <R0, R1>(lhs: R0, rhs: R1) -> Regex<Substring> where R0: RegexProtocol, R1: RegexProtocol {
  .init(node: lhs.regex.root.appendingAlternationCase(rhs.regex.root))
}

public func | <R0, R1, W1, C0>(lhs: R0, rhs: R1) -> Regex<(Substring, C0?)> where R0: RegexProtocol, R1: RegexProtocol, R1.Match == (W1, C0) {
  .init(node: lhs.regex.root.appendingAlternationCase(rhs.regex.root))
}

public func | <R0, R1, W1, C0, C1>(lhs: R0, rhs: R1) -> Regex<(Substring, C0?, C1?)> where R0: RegexProtocol, R1: RegexProtocol, R1.Match == (W1, C0, C1) {
  .init(node: lhs.regex.root.appendingAlternationCase(rhs.regex.root))
}

...
```

### Builder

```swift
@resultBuilder
public struct AlternationBuilder {
  @_disfavoredOverload
  public static func buildBlock<R: RegexProtocol>(_ regex: R) -> R {
    regex
  }

  public static func buildExpression<R: RegexProtocol>(_ regex: R) -> R {
    regex
  }

  public static func buildEither<R: RegexProtocol>(first component: R) -> R {
    component
  }

  public static func buildEither<R: RegexProtocol>(second component: R) -> R {
    component
  }
  
  // Starts arity^2 overloads
  
  public static func buildBlock<R0, R1>(
    combining next: R1, into combined: R0
  ) -> Regex<Substring> where R0: RegexProtocol, R1: RegexProtocol {
    .init(node: combined.regex.root.appendingAlternationCase(next.regex.root))
  }
  
  public static func buildBlock<R0, R1, W1, C0>(
    combining next: R1, into combined: R0
  ) -> Regex<(Substring, C0?)> where R0: RegexProtocol, R1: RegexProtocol, R1.Match == (W1, C0) {
    .init(node: combined.regex.root.appendingAlternationCase(next.regex.root))
  }
  
  public static func buildBlock<R0, R1, W1, C0, C1>(
    combining next: R1, into combined: R0
  ) -> Regex<(Substring, C0?, C1?)> where R0: RegexProtocol, R1: RegexProtocol, R1.Match == (W1, C0, C1) {
    .init(node: combined.regex.root.appendingAlternationCase(next.regex.root))
  }
  
  ...
}
```

## Capture

### Overview

- `capture` and `tryCapture` inserts a new `Substring` to the `.1` position of `Match`.
- `capture(_:transform:)` accepts a closure `(Substring) -> NewCapture`.
- `tryCapture(_:transform:)` accepts a _failable_ closure `(Substring) -> NewCapture?` or `(Substring) throws -> NewCapture`. Upon failure, propagates the failure to the match.

### Example

```swift
let regex = Regex {
  "a".+
  capture {
    tryCapture("b") { Int($0) }
    many {
      tryCapture("c") { Double($0) }
    }
    "e".?
  }
}
```

### API

```swift
// nullary

public func capture<R: RegexProtocol, W>(
  @RegexBuilder _ component: () -> R
) -> Regex<(W, Substring)> where R.Match == W {
  .init(node: .group(.capture, component().regex.root))
}

public func capture<R: RegexProtocol, W, NewCapture>(
  @RegexBuilder _ component: () -> R,
  transform: @escaping (Substring) -> NewCapture
) -> Regex<(W, NewCapture)> where R.Match == W {
  .init(node: .groupTransform(
    .capture,
    component().regex.root,
    CaptureTransform(resultType: NewCapture.self) {
      transform($0) as Any
    }))
}

public func tryCapture<R: RegexProtocol, W, NewCapture>(
  @RegexBuilder _ component: () -> R,
  transform: @escaping (Substring) throws -> NewCapture
) -> Regex<(W, NewCapture)> where R.Match == W {
  .init(node: .groupTransform(
    .capture,
    component().regex.root,
    CaptureTransform(resultType: NewCapture.self) {
      try transform($0) as Any
    }))
}

public func tryCapture<R: RegexProtocol, W, NewCapture>(
  @RegexBuilder _ component: () -> R,
  transform: @escaping (Substring) -> NewCapture?
) -> Regex<(W, NewCapture)> where R.Match == W {
  .init(node: .groupTransform(
    .capture,
    component().regex.root,
    CaptureTransform(resultType: NewCapture.self) {
      transform($0) as Any?
    }))
}

// unary

public func capture<R: RegexProtocol, W, C0>(_ component: R) -> Regex<(W, Substring, C0)> where R.Match == (W, C0) {
  .init(node: .group(.capture, component.regex.root))
}

public func capture<R: RegexProtocol, W, C0, NewCapture>(
  _ component: R, transform: @escaping (Substring) -> NewCapture
) -> Regex<(W, NewCapture, C0)> where R.Match == (W, C0) {
  .init(node: .groupTransform(
    .capture,
    component.regex.root,
    CaptureTransform(resultType: NewCapture.self) {
      transform($0) as Any
    }))
}

public func tryCapture<R: RegexProtocol, W, C0, NewCapture>(
  _ component: R, transform: @escaping (Substring) throws -> NewCapture
) -> Regex<(W, NewCapture, C0)> where R.Match == (W, C0) {
  .init(node: .groupTransform(
    .capture,
    component.regex.root,
    CaptureTransform(resultType: NewCapture.self) {
      try transform($0) as Any
    }))
}

public func tryCapture<R: RegexProtocol, W, C0, NewCapture>(
  _ component: R, transform: @escaping (Substring) -> NewCapture?
) -> Regex<(W, NewCapture, C0)> where R.Match == (W, C0) {
  .init(node: .groupTransform(
    .capture,
    component.regex.root,
    CaptureTransform(resultType: NewCapture.self) {
      transform($0) as Any?
    }))
}

...
```

## Backreferences (prototype)

### Example

```swift
let regex = Regex { a, b in
    "abc".capture(as: a)
    "def".capture(as: b)
    a
    b.capture()
} // matches "abcdefabcdef"
```

or

```swift
let regex = Regex {
  let a = Reference()
  let b = Reference()
  capture("abc", into: a)
  capture("def", into: b)
  a
  capture(b)
}
```

## Group (?)

### Example

```swift
let regex = Regex {
  group {
    "a".capture()
    "b".capture()
  }
}
```

Question: When does the user want to group? If grouping for quantification, why not just use the quantifier directly, e.g.

```swift
let regex = Regex {
  oneOrMore {
    "a".capture()
    "b".capture()
  }
}
```

## Subpattern call
