import _MatchingEngine

// MARK: - Primitives

extension String: RegexProtocol {
  public typealias Capture = EmptyCapture
  public typealias Match = Substring

  public var regex: Regex<Match> {
    let atoms = self.map { atom(.char($0)) }
    return .init(ast: concat(atoms))
  }
}

extension Character: RegexProtocol {
  public typealias Capture = EmptyCapture
  public typealias Match = Substring

  public var regex: Regex<Match> {
    .init(ast: atom(.char(self)))
  }
}

extension CharacterClass: RegexProtocol {
  public typealias Capture = EmptyCapture
  public typealias Match = Substring

  public var regex: Regex<Match> {
    guard let ast = self.makeAST() else {
      fatalError("FIXME: extended AST?")
    }
    return Regex(ast: ast)
  }
}

// MARK: - Combinators

// TODO: We want variadic generics!
// Overloads are auto-generated in Concatenation.swift.
//
// public struct Concatenate<R...: RegexContent>: RegexContent {
//   public let regex: Regex<(R...).filter { $0 != Void.self }>
//
//   public init(_ components: R...) {
//     regex = .init(ast: .concatenation([#splat(components...)]))
//   }
// }

// MARK: Repetition

/// A regular expression.
public struct OneOrMore<Component: RegexProtocol>: RegexProtocol {
  public typealias Match = Tuple2<Substring, [Component.Match.Capture]>

  public let regex: Regex<Match>

  public init(_ component: Component) {
    self.regex = .init(ast:
      oneOrMore(.eager, component.regex.ast)
    )
  }

  public init(@RegexBuilder _ content: () -> Component) {
    self.init(content())
  }
}

postfix operator .+

public postfix func .+ <R: RegexProtocol>(
  lhs: R
) -> OneOrMore<R> {
  .init(lhs)
}

public struct Repeat<
  Component: RegexProtocol
>: RegexProtocol {
  public typealias Match = Tuple2<Substring, [Component.Match.Capture]>

  public let regex: Regex<Match>

  public init(_ component: Component) {
    self.regex = .init(ast:
      zeroOrMore(.eager, component.regex.ast))
  }

  public init(@RegexBuilder _ content: () -> Component) {
    self.init(content())
  }
}

postfix operator .*

public postfix func .* <R: RegexProtocol>(
  lhs: R
) -> Repeat<R> {
  .init(lhs)
}

public struct Optionally<Component: RegexProtocol>: RegexProtocol {
  public typealias Match = Tuple2<Substring, Component.Match.Capture?>

  public let regex: Regex<Match>

  public init(_ component: Component) {
    self.regex = .init(ast:
      zeroOrOne(.eager, component.regex.ast))
  }

  public init(@RegexBuilder _ content: () -> Component) {
    self.init(content())
  }
}

postfix operator .?

public postfix func .? <R: RegexProtocol>(
  lhs: R
) -> Optionally<R> {
  .init(lhs)
}

// TODO: Support heterogeneous capture alternation.
public struct Alternation<
  Component1: RegexProtocol, Component2: RegexProtocol
>: RegexProtocol where Component1.Match.Capture == Component2.Match.Capture {
  public typealias Match = Tuple2<Substring, Component1.Match.Capture>

  public let regex: Regex<Match>

  public init(_ first: Component1, _ second: Component2) {
    regex = .init(ast: alt(
      first.regex.ast, second.regex.ast
    ))
  }

  public init(
    @RegexBuilder _ content: () -> Alternation<Component1, Component2>
  ) {
    self = content()
  }
}

public func | <Component1, Component2>(
  lhs: Component1, rhs: Component2
) -> Alternation<Component1, Component2> {
  .init(lhs, rhs)
}

// MARK: - Capture

public struct CapturingGroup<Match: MatchProtocol>: RegexProtocol {
  public let regex: Regex<Match>

  init<Component: RegexProtocol>(
    _ component: Component
  ) {
    self.regex = .init(ast:
      .groupTransform(
        .init(.init(faking: .capture), component.regex.ast, .fake),
        transform: CaptureTransform { input, bounds in
          input[bounds]
        }))
  }

  init<NewCapture, Component: RegexProtocol>(
    _ component: Component,
    transform: @escaping (Substring) -> NewCapture
  ) {
    self.regex = .init(ast:
      .groupTransform(
        .init(.init(faking: .capture), component.regex.ast, .fake),
        transform: CaptureTransform { input, bounds in
          transform(input[bounds])
        }))
  }
}
