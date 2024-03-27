//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2021-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

@_spi(RegexBuilder) import _StringProcessing

@available(SwiftStdlib 5.7, *)
extension RegexComponentBuilder {
  @_alwaysEmitIntoClient
  public static func buildPartialBlock<
    R0: RegexComponent, R1: RegexComponent, Whole0, Whole1, each Capture0, each Capture1
  >(
    accumulated: R0,
    next: R1
  ) -> Regex<(Substring, repeat each Capture0, repeat each Capture1)>
    where R0.RegexOutput == (Whole0, repeat each Capture0),
          R1.RegexOutput == (Whole1, repeat each Capture1)
  {
    let factory = makeFactory()
    return factory.accumulate(accumulated, next)
  }

  @_alwaysEmitIntoClient
  @_disfavoredOverload
  public static func buildPartialBlock<
    R0: RegexComponent, R1: RegexComponent, Whole0, Whole1, each Capture1
  >(
    accumulated: R0,
    next: R1
  ) -> Regex<(Substring, repeat each Capture1)>
    where R0.RegexOutput == Whole0,
          R1.RegexOutput == (Whole1, repeat each Capture1)
  {
    let factory = makeFactory()
    return factory.accumulate(ignoringOutputTypeOf: accumulated, next)
  }
  
  @_alwaysEmitIntoClient
  @_disfavoredOverload
  public static func buildPartialBlock<
    R0: RegexComponent, R1: RegexComponent, Whole0, Whole1, each Capture0
  >(
    accumulated: R0,
    next: R1
  ) -> Regex<(Substring, repeat each Capture0)>
    where R0.RegexOutput == (Whole0, repeat each Capture0),
          R1.RegexOutput == Whole1
  {
    let factory = makeFactory()
    return factory.accumulate(accumulated, ignoringOutputTypeOf: next)
  }
}

// MARK: - Quantifiers

@available(SwiftStdlib 5.7, *)
extension Optionally {
  /// Creates a regex component that matches the given component
  /// zero or one times.
  ///
  /// - Parameters:
  ///   - component: The regex component.
  ///   - behavior: The repetition behavior to use when repeating
  ///     `component` in the match. If `behavior` is `nil`, the default
  ///     repetition behavior is used, which can be changed from
  ///     `eager` by calling `repetitionBehavior(_:)` on the resulting
  ///     `Regex`.
  @_disfavoredOverload
  @_alwaysEmitIntoClient
  public init(
    _ component: some RegexComponent,
    _ behavior: RegexRepetitionBehavior? = nil
  ) where RegexOutput == Substring {
    let factory = makeFactory()
    self.init(factory.zeroOrOne(component, behavior))
  }

  /// Creates a regex component that matches the given component
  /// zero or one times.
  ///
  /// - Parameters:
  ///   - component: The regex component.
  ///   - behavior: The repetition behavior to use when repeating
  ///     `component` in the match. If `behavior` is `nil`, the default
  ///     repetition behavior is used, which can be changed from
  ///     `eager` by calling `repetitionBehavior(_:)` on the resulting
  ///     `Regex`.
  @_alwaysEmitIntoClient
  public init<C0, C1, each Capture>(
    _ component: some RegexComponent<(C0, C1, repeat each Capture)>,
    _ behavior: RegexRepetitionBehavior? = nil
  ) where RegexOutput == (Substring, C1, repeat (each Capture)?) {
    let factory = makeFactory()
    self.init(factory.zeroOrOne(component, behavior))
  }

  /// Creates a regex component that matches the given component
  /// zero or one times.
  ///
  /// - Parameters:
  ///   - behavior: The repetition behavior to use when repeating
  ///     `component` in the match. If `behavior` is `nil`, the default
  ///     repetition behavior is used, which can be changed from
  ///     `eager` by calling `repetitionBehavior(_:)` on the resulting
  ///     `Regex`.
  ///   - componentBuilder: A builder closure that generates a regex
  ///     component.
  @_disfavoredOverload
  @_alwaysEmitIntoClient
  public init(
    _ behavior: RegexRepetitionBehavior? = nil,
    @RegexComponentBuilder _ componentBuilder: () -> some RegexComponent
  ) where RegexOutput == Substring {
    let factory = makeFactory()
    self.init(factory.zeroOrOne(componentBuilder(), behavior))
  }
  
  /// Creates a regex component that matches the given component
  /// zero or one times.
  ///
  /// - Parameters:
  ///   - behavior: The repetition behavior to use when repeating
  ///     `component` in the match. If `behavior` is `nil`, the default
  ///     repetition behavior is used, which can be changed from
  ///     `eager` by calling `repetitionBehavior(_:)` on the resulting
  ///     `Regex`.
  ///   - componentBuilder: A builder closure that generates a regex
  ///     component.
  @_alwaysEmitIntoClient
  public init<C0, C1, each Capture>(
    _ behavior: RegexRepetitionBehavior? = nil,
    @RegexComponentBuilder _ componentBuilder: () -> some RegexComponent<(C0, C1, repeat each Capture)>
  ) where RegexOutput == (Substring, C1?, repeat (each Capture)?) {
    let factory = makeFactory()
    self.init(factory.zeroOrOne(componentBuilder(), behavior))
  }
}

@available(SwiftStdlib 5.7, *)
extension RegexComponentBuilder {
  @_disfavoredOverload
  @_alwaysEmitIntoClient
  public static func buildLimitedAvailability(
    _ component: some RegexComponent
  ) -> Regex<Substring> {
    let factory = makeFactory()
    return factory.zeroOrOne(component, nil)
  }
  
  @_alwaysEmitIntoClient
  public static func buildLimitedAvailability<C0, C1, each Capture>(
    _ component: some RegexComponent<(C0, C1, repeat each Capture)>
  ) -> Regex<(Substring, C1?, repeat (each Capture)?)> {
    let factory = makeFactory()
    return factory.zeroOrOne(component, nil)
  }
}

@available(SwiftStdlib 5.7, *)
extension ZeroOrMore {
  /// Creates a regex component that matches the given component
  /// zero or more times.
  ///
  /// - Parameters:
  ///   - component: The regex component.
  ///   - behavior: The repetition behavior to use when repeating
  ///     `component` in the match. If `behavior` is `nil`, the default
  ///     repetition behavior is used, which can be changed from
  ///     `eager` by calling `repetitionBehavior(_:)` on the resulting
  ///     `Regex`.
  @_disfavoredOverload
  @_alwaysEmitIntoClient
  public init(
    _ component: some RegexComponent,
    _ behavior: RegexRepetitionBehavior? = nil
  ) where RegexOutput == Substring {
    let factory = makeFactory()
    self.init(factory.zeroOrMore(component, behavior))
  }

  /// Creates a regex component that matches the given component
  /// zero or more times.
  ///
  /// - Parameters:
  ///   - component: The regex component.
  ///   - behavior: The repetition behavior to use when repeating
  ///     `component` in the match. If `behavior` is `nil`, the default
  ///     repetition behavior is used, which can be changed from
  ///     `eager` by calling `repetitionBehavior(_:)` on the resulting
  ///     `Regex`.
  @_alwaysEmitIntoClient
  public init<C0, C1, each Capture>(
    _ component: some RegexComponent<(C0, C1, repeat each Capture)>,
    _ behavior: RegexRepetitionBehavior? = nil
  ) where RegexOutput == (Substring, C1?, repeat (each Capture)?) {
    let factory = makeFactory()
    self.init(factory.zeroOrMore(component, behavior))
  }

  /// Creates a regex component that matches the given component
  /// zero or more times.
  ///
  /// - Parameters:
  ///   - behavior: The repetition behavior to use when repeating
  ///     `component` in the match. If `behavior` is `nil`, the default
  ///     repetition behavior is used, which can be changed from
  ///     `eager` by calling `repetitionBehavior(_:)` on the resulting
  ///     `Regex`.
  ///   - componentBuilder: A builder closure that generates a regex
  ///     component.
  @_disfavoredOverload
  @_alwaysEmitIntoClient
  public init(
    _ behavior: RegexRepetitionBehavior? = nil,
    @RegexComponentBuilder _ componentBuilder: () -> some RegexComponent
  ) where RegexOutput == Substring {
    let factory = makeFactory()
    self.init(factory.zeroOrMore(componentBuilder(), behavior))
  }

  /// Creates a regex component that matches the given component
  /// zero or more times.
  ///
  /// - Parameters:
  ///   - behavior: The repetition behavior to use when repeating
  ///     `component` in the match. If `behavior` is `nil`, the default
  ///     repetition behavior is used, which can be changed from
  ///     `eager` by calling `repetitionBehavior(_:)` on the resulting
  ///     `Regex`.
  ///   - componentBuilder: A builder closure that generates a regex
  ///     component.
  @_alwaysEmitIntoClient
  public init<C0, C1, each Capture>(
    _ behavior: RegexRepetitionBehavior? = nil,
    @RegexComponentBuilder _ componentBuilder: () -> some RegexComponent<(C0, C1, repeat each Capture)>
  ) where RegexOutput == (Substring, C1?, repeat (each Capture)?) {
    let factory = makeFactory()
    self.init(factory.zeroOrMore(componentBuilder(), behavior))
  }
}

@available(SwiftStdlib 5.7, *)
extension OneOrMore {
  /// Creates a regex component that matches the given component
  /// one or more times.
  ///
  /// - Parameters:
  ///   - component: The regex component.
  ///   - behavior: The repetition behavior to use when repeating
  ///     `component` in the match. If `behavior` is `nil`, the default
  ///     repetition behavior is used, which can be changed from
  ///     `eager` by calling `repetitionBehavior(_:)` on the resulting
  ///     `Regex`.
  @_disfavoredOverload
  @_alwaysEmitIntoClient
  public init(
    _ component: some RegexComponent,
    _ behavior: RegexRepetitionBehavior? = nil
  ) where RegexOutput == Substring {
    let factory = makeFactory()
    self.init(factory.oneOrMore(component, behavior))
  }

  /// Creates a regex component that matches the given component
  /// one or more times.
  ///
  /// - Parameters:
  ///   - component: The regex component.
  ///   - behavior: The repetition behavior to use when repeating
  ///     `component` in the match. If `behavior` is `nil`, the default
  ///     repetition behavior is used, which can be changed from
  ///     `eager` by calling `repetitionBehavior(_:)` on the resulting
  ///     `Regex`.
  @_alwaysEmitIntoClient
  public init<C0, C1, each Capture>(
    _ component: some RegexComponent<(C0, C1, repeat each Capture)>,
    _ behavior: RegexRepetitionBehavior? = nil
  ) where RegexOutput == (Substring, C1, repeat each Capture) {
    let factory = makeFactory()
    self.init(factory.oneOrMore(component, behavior))
  }

  /// Creates a regex component that matches the given component
  /// one or more times.
  ///
  /// - Parameters:
  ///   - behavior: The repetition behavior to use when repeating
  ///     `component` in the match. If `behavior` is `nil`, the default
  ///     repetition behavior is used, which can be changed from
  ///     `eager` by calling `repetitionBehavior(_:)` on the resulting
  ///     `Regex`.
  ///   - componentBuilder: A builder closure that generates a regex
  ///     component.
  @_disfavoredOverload
  @_alwaysEmitIntoClient
  public init(
    _ behavior: RegexRepetitionBehavior? = nil,
    @RegexComponentBuilder _ componentBuilder: () -> some RegexComponent
  ) where RegexOutput == Substring {
    let factory = makeFactory()
    self.init(factory.oneOrMore(componentBuilder(), behavior))
  }

  /// Creates a regex component that matches the given component
  /// one or more times.
  ///
  /// - Parameters:
  ///   - behavior: The repetition behavior to use when repeating
  ///     `component` in the match. If `behavior` is `nil`, the default
  ///     repetition behavior is used, which can be changed from
  ///     `eager` by calling `repetitionBehavior(_:)` on the resulting
  ///     `Regex`.
  ///   - componentBuilder: A builder closure that generates a regex
  ///     component.
  @_alwaysEmitIntoClient
  public init<C0, C1, each Capture>(
    _ behavior: RegexRepetitionBehavior? = nil,
    @RegexComponentBuilder _ componentBuilder: () -> some RegexComponent<(C0, C1, repeat each Capture)>
  ) where RegexOutput == (Substring, C1, repeat each Capture) {
    let factory = makeFactory()
    self.init(factory.oneOrMore(componentBuilder(), behavior))
  }
}

@available(SwiftStdlib 5.7, *)
extension Repeat {
  /// Creates a regex component that matches the given component repeated
  /// the specified number of times.
  ///
  /// - Parameters:
  ///   - component: The regex component to repeat.
  ///   - count: The number of times to repeat `component`. `count` must
  ///     be greater than or equal to zero.
  @_disfavoredOverload
  @_alwaysEmitIntoClient
  public init(
    _ component: some RegexComponent,
    count: Int
  ) where RegexOutput == Substring {
    precondition(count >= 0, "Must specify a positive count")
    let factory = makeFactory()
    self.init(factory.exactly(count, component))
  }

  /// Creates a regex component that matches the given component repeated
  /// the specified number of times.
  ///
  /// - Parameters:
  ///   - count: The number of times to repeat `component`. `count` must
  ///     be greater than or equal to zero.
  ///   - componentBuilder: A builder closure that creates the regex
  ///     component to repeat.
  @_disfavoredOverload
  @_alwaysEmitIntoClient
  public init(
    count: Int,
    @RegexComponentBuilder _ componentBuilder: () -> some RegexComponent
  ) where RegexOutput == Substring {
    precondition(count >= 0, "Must specify a positive count")
    let factory = makeFactory()
    self.init(factory.exactly(count, componentBuilder()))
  }

  /// Creates a regex component that matches the given component repeated
  /// the specified number of times.
  ///
  /// - Parameters:
  ///   - component: The regex component to repeat.
  ///   - count: The number of times to repeat `component`. `count` must
  ///     be greater than or equal to zero.
  @_alwaysEmitIntoClient
  public init<C0, C1, each Capture>(
    _ component: some RegexComponent<(C0, C1, repeat each Capture)>,
    count: Int
  ) where RegexOutput == (Substring, C1?, repeat (each Capture)?) {
    precondition(count >= 0, "Must specify a positive count")
    let factory = makeFactory()
    self.init(factory.exactly(count, component))
  }

  /// Creates a regex component that matches the given component repeated
  /// the specified number of times.
  ///
  /// - Parameters:
  ///   - count: The number of times to repeat `component`. `count` must
  ///     be greater than or equal to zero.
  ///   - componentBuilder: A builder closure that creates the regex
  ///     component to repeat.
  @_alwaysEmitIntoClient
  public init<C0, C1, each Capture>(
    count: Int,
    @RegexComponentBuilder _ componentBuilder: () -> some RegexComponent<(C0, C1, repeat each Capture)>
  ) where RegexOutput == (Substring, C1?, repeat (each Capture)?) {
    precondition(count >= 0, "Must specify a positive count")
    let factory = makeFactory()
    self.init(factory.exactly(count, componentBuilder()))
  }

  /// Creates a regex component that matches the given component repeated
  /// a number of times specified by the given range expression.
  ///
  /// - Parameters:
  ///   - component: The regex component to repeat.
  ///   - expression: A range expression specifying the number of times
  ///     that `component` can repeat.
  ///   - behavior: The repetition behavior to use when repeating
  ///     `component` in the match. If `behavior` is `nil`, the default
  ///     repetition behavior is used, which can be changed from
  ///     `eager` by calling `repetitionBehavior(_:)` on the resulting
  ///     `Regex`.
  @_disfavoredOverload
  @_alwaysEmitIntoClient
  public init(
    _ component: some RegexComponent,
    _ expression: some RangeExpression<Int>,
    _ behavior: RegexRepetitionBehavior? = nil
  ) where RegexOutput == Substring {
    let factory = makeFactory()
    self.init(factory.repeating(expression.relative(to: 0..<Int.max), behavior, component))
  }
  
  /// Creates a regex component that matches the given component repeated
  /// a number of times specified by the given range expression.
  ///
  /// - Parameters:
  ///   - component: The regex component to repeat.
  ///   - expression: A range expression specifying the number of times
  ///     that `component` can repeat.
  ///   - behavior: The repetition behavior to use when repeating
  ///     `component` in the match. If `behavior` is `nil`, the default
  ///     repetition behavior is used, which can be changed from
  ///     `eager` by calling `repetitionBehavior(_:)` on the resulting
  ///     `Regex`.
  @_alwaysEmitIntoClient
  public init<C0, C1, each Capture>(
    _ component: some RegexComponent<(C0, C1, repeat each Capture)>,
    _ expression: some RangeExpression<Int>,
    _ behavior: RegexRepetitionBehavior? = nil
  ) where RegexOutput == (Substring, C1?, repeat (each Capture)?) {
    let factory = makeFactory()
    self.init(factory.repeating(expression.relative(to: 0..<Int.max), behavior, component))
  }

  /// Creates a regex component that matches the given component repeated
  /// a number of times specified by the given range expression.
  ///
  /// - Parameters:
  ///   - expression: A range expression specifying the number of times
  ///     that `component` can repeat.
  ///   - behavior: The repetition behavior to use when repeating
  ///     `component` in the match. If `behavior` is `nil`, the default
  ///     repetition behavior is used, which can be changed from
  ///     `eager` by calling `repetitionBehavior(_:)` on the resulting
  ///     `Regex`.
  ///   - componentBuilder: A builder closure that creates the regex
  ///     component to repeat.
  @_disfavoredOverload
  @_alwaysEmitIntoClient
  public init(
    _ expression: some RangeExpression<Int>,
    _ behavior: RegexRepetitionBehavior? = nil,
    @RegexComponentBuilder _ componentBuilder: () -> some RegexComponent
  ) where RegexOutput == Substring {
    let factory = makeFactory()
    self.init(factory.repeating(expression.relative(to: 0..<Int.max), behavior, componentBuilder()))
  }

  /// Creates a regex component that matches the given component repeated
  /// a number of times specified by the given range expression.
  ///
  /// - Parameters:
  ///   - expression: A range expression specifying the number of times
  ///     that `component` can repeat.
  ///   - behavior: The repetition behavior to use when repeating
  ///     `component` in the match. If `behavior` is `nil`, the default
  ///     repetition behavior is used, which can be changed from
  ///     `eager` by calling `repetitionBehavior(_:)` on the resulting
  ///     `Regex`.
  ///   - componentBuilder: A builder closure that creates the regex
  ///     component to repeat.
  @_alwaysEmitIntoClient
  public init<C0, C1, each Capture>(
    _ expression: some RangeExpression<Int>,
    _ behavior: RegexRepetitionBehavior? = nil,
    @RegexComponentBuilder _ componentBuilder: () -> some RegexComponent<(C0, C1, repeat each Capture)>
  ) where RegexOutput == (Substring, C1?, repeat (each Capture)?) {
    let factory = makeFactory()
    self.init(factory.repeating(expression.relative(to: 0..<Int.max), behavior, componentBuilder()))
  }
}

// MARK: - Atomic groups

@available(SwiftStdlib 5.7, *)
extension Local {
  /// Creates an atomic group with the given regex component.
  ///
  /// - Parameter component: The regex component to wrap in an atomic
  ///   group.
  @available(SwiftStdlib 5.7, *)
  @_disfavoredOverload
  @_alwaysEmitIntoClient
  public init(
    _ component: some RegexComponent
  ) where RegexOutput == Substring {
    let factory = makeFactory()
    self.init(factory.atomicNonCapturing(component))
  }

  /// Creates an atomic group with the given regex component.
  ///
  /// - Parameter componentBuilder: A builder closure that generates a
  ///   regex component to wrap in an atomic group.
  @available(SwiftStdlib 5.7, *)
  @_disfavoredOverload
  @_alwaysEmitIntoClient
  public init(
    @RegexComponentBuilder _ componentBuilder: () -> some RegexComponent
  ) where RegexOutput == Substring {
    let factory = makeFactory()
    self.init(factory.atomicNonCapturing(componentBuilder()))
  }
}

@available(SwiftStdlib 5.7, *)
extension Local {
  /// Creates an atomic group with the given regex component.
  ///
  /// - Parameter component: The regex component to wrap in an atomic
  ///   group.
  @available(SwiftStdlib 5.7, *)
  @_alwaysEmitIntoClient
  public init<W, each Capture>(
    _ component: some RegexComponent<(W, repeat each Capture)>
  ) where RegexOutput == (Substring, repeat each Capture) {
    let factory = makeFactory()
    self.init(factory.atomicNonCapturing(component))
  }

  /// Creates an atomic group with the given regex component.
  ///
  /// - Parameter componentBuilder: A builder closure that generates a
  ///   regex component to wrap in an atomic group.
  @available(SwiftStdlib 5.7, *)
  @_alwaysEmitIntoClient
  public init<W, each Capture>(
    @RegexComponentBuilder _ componentBuilder: () -> some RegexComponent<(W, repeat each Capture)>
  ) where RegexOutput == (Substring, repeat each Capture) {
    let factory = makeFactory()
    self.init(factory.atomicNonCapturing(componentBuilder()))
  }
}

// MARK: - Alternation builder

@available(SwiftStdlib 5.7, *)
extension AlternationBuilder {
  @_alwaysEmitIntoClient
  public static func buildPartialBlock<W0, W1, C0, C1>(
    accumulated: some RegexComponent<(W0, C0)>,
    next: some RegexComponent<(W1, C1)>
  ) -> ChoiceOf<(Substring, C0?, C1?)> {
    let factory = makeFactory()
    return .init(factory.accumulateAlternation(accumulated, next))
  }
  
  @_alwaysEmitIntoClient
  public static func buildPartialBlock<W0, W1, each Capture0, each Capture1>(
    accumulated: some RegexComponent<(W0, repeat each Capture0)>,
    next: some RegexComponent<(W1, repeat each Capture1)>
  ) -> ChoiceOf<(Substring, repeat each Capture0, repeat (each Capture1)?)> {
    let factory = makeFactory()
    return .init(factory.accumulateAlternation(accumulated, next))
  }
  
  @_disfavoredOverload
  @_alwaysEmitIntoClient
  public static func buildPartialBlock(
    accumulated: some RegexComponent,
    next: some RegexComponent
  ) -> ChoiceOf<Substring> {
    let factory = makeFactory()
    return .init(factory.accumulateAlternation(accumulated, next))
  }
}

// MARK: - Non-builder captures

@available(SwiftStdlib 5.7, *)
extension Capture {
  /// Creates a capture for the given component.
  ///
  /// - Parameter component: The regex component to capture.
  @_alwaysEmitIntoClient
  public init<W, each Capture>(
    _ component: some RegexComponent<(W, repeat each Capture)>
  ) where RegexOutput == (Substring, W, repeat each Capture) {
    let factory = makeFactory()
    self.init(factory.capture(component))
  }

  /// Creates a capture for the given component using the specified
  /// reference.
  ///
  /// - Parameters:
  ///   - component: The regex component to capture.
  ///   - reference: The reference to use for anything captured by
  ///     `component`.
  @_alwaysEmitIntoClient
  public init<W, each Capture>(
    _ component: some RegexComponent<(W, repeat each Capture)>,
    as reference: Reference<W>
  ) where RegexOutput == (Substring, W, repeat each Capture) {
    let factory = makeFactory()
    self.init(factory.capture(component, reference._raw))
  }

  /// Creates a capture for the given component, transforming with the
  /// given closure.
  ///
  /// - Parameters:
  ///   - component: The regex component to capture.
  ///   - transform: A closure that takes the substring matched by
  ///     `component` and returns a new value to capture. If `transform`
  ///     throws an error, matching is abandoned and the error is returned
  ///     to the caller.
  @_alwaysEmitIntoClient
  public init<W, each Capture, NewCapture>(
    _ component: some RegexComponent<(W, repeat each Capture)>,
    transform: @escaping (W) throws -> NewCapture
  ) where RegexOutput == (Substring, NewCapture, repeat each Capture) {
    let factory = makeFactory()
    self.init(factory.capture(component, nil, transform))
  }

  /// Creates a capture for the given component using the specified
  /// reference, transforming with the given closure.
  ///
  /// - Parameters:
  ///   - component: The regex component to capture.
  ///   - reference: The reference to use for anything captured by
  ///     `component`.
  ///   - transform: A closure that takes the substring matched by
  ///     `component` and returns a new value to capture. If `transform`
  ///     throws an error, matching is abandoned and the error is returned
  ///     to the caller.
  @_alwaysEmitIntoClient
  public init<W, each Capture, NewCapture>(
    _ component: some RegexComponent<(W, repeat each Capture)>,
    as reference: Reference<NewCapture>,
    transform: @escaping (W) throws -> NewCapture
  ) where RegexOutput == (Substring, NewCapture, repeat each Capture) {
    let factory = makeFactory()
    self.init(factory.capture(component, reference._raw, transform))
  }
}

@available(SwiftStdlib 5.7, *)
extension TryCapture {
  /// Creates a capture for the given component, attempting to transform
  /// with the given closure.
  ///
  /// - Parameters:
  ///   - component: The regex component to capture.
  ///   - transform: A closure that takes the substring matched by
  ///     `component` and returns a new value to capture, or `nil` if
  ///     matching should proceed, backtracking if allowed. If `transform`
  ///     throws an error, matching is abandoned and the error is returned
  ///     to the caller.
  @_alwaysEmitIntoClient
  public init<W, each Capture, NewCapture>(
    _ component: some RegexComponent<(W, repeat each Capture)>,
    transform: @escaping (W) throws -> NewCapture?
  ) where RegexOutput == (Substring, NewCapture, repeat each Capture) {
    let factory = makeFactory()
    self.init(factory.captureOptional(component, nil, transform))
  }

  /// Creates a capture for the given component using the specified
  /// reference, attempting to transform with the given closure.
  ///
  /// - Parameters:
  ///   - component: The regex component to capture.
  ///   - reference: The reference to use for anything captured by
  ///     `component`.
  ///   - transform: A closure that takes the substring matched by
  ///     `component` and returns a new value to capture, or `nil` if
  ///     matching should proceed, backtracking if allowed. If `transform`
  ///     throws an error, matching is abandoned and the error is returned
  ///     to the caller.
  @_alwaysEmitIntoClient
  public init<W, each Capture, NewCapture>(
    _ component: some RegexComponent<(W, repeat each Capture)>,
    as reference: Reference<NewCapture>,
    transform: @escaping (W) throws -> NewCapture?
  ) where RegexOutput == (Substring, NewCapture, repeat each Capture) {
    let factory = makeFactory()
    self.init(factory.captureOptional(component, reference._raw, transform))
  }
}

// MARK: - Builder captures

@available(SwiftStdlib 5.7, *)
extension Capture {
  /// Creates a capture for the given component.
  ///
  /// - Parameter componentBuilder: A builder closure that generates a
  ///   regex component to capture.
  @_alwaysEmitIntoClient
  public init<W, each Capture>(
    @RegexComponentBuilder _ componentBuilder: () -> some RegexComponent<(W, repeat each Capture)>
  ) where RegexOutput == (Substring, W, repeat each Capture) {
    let factory = makeFactory()
    self.init(factory.capture(componentBuilder()))
  }

  /// Creates a capture for the given component using the specified
  /// reference.
  ///
  /// - Parameters:
  ///   - reference: The reference to use for anything captured by
  ///     `component`.
  ///   - componentBuilder: A builder closure that generates a regex
  ///     component to capture.
  @_alwaysEmitIntoClient
  public init<W, each Capture>(
    as reference: Reference<W>,
    @RegexComponentBuilder _ componentBuilder: () -> some RegexComponent<(W, repeat each Capture)>
  ) where RegexOutput == (Substring, W, repeat each Capture) {
    let factory = makeFactory()
    self.init(factory.capture(componentBuilder(), reference._raw))
  }

  /// Creates a capture for the given component, transforming with the
  /// given closure.
  ///
  /// - Parameters:
  ///   - componentBuilder: A builder closure that generates a regex
  ///     component to capture.
  ///   - transform: A closure that takes the substring matched by
  ///     `component` and returns a new value to capture. If `transform`
  ///     throws an error, matching is abandoned and the error is returned
  ///     to the caller.
  @_alwaysEmitIntoClient
  public init<W, each Capture, NewCapture>(
    @RegexComponentBuilder _ componentBuilder: () -> some RegexComponent<(W, repeat each Capture)>,
    transform: @escaping (W) throws -> NewCapture
  ) where RegexOutput == (Substring, NewCapture, repeat each Capture) {
    let factory = makeFactory()
    self.init(factory.capture(componentBuilder(), nil, transform))
  }

  /// Creates a capture for the given component using the specified
  /// reference, transforming with the given closure.
  ///
  /// - Parameters:
  ///   - reference: The reference to use for anything captured by
  ///     `component`.
  ///   - componentBuilder: A builder closure that generates a regex
  ///     component to capture.
  ///   - transform: A closure that takes the substring matched by
  ///     `component` and returns a new value to capture. If `transform`
  ///     throws an error, matching is abandoned and the error is returned
  ///     to the caller.
  @_alwaysEmitIntoClient
  public init<W, each Capture, NewCapture>(
    as reference: Reference<NewCapture>,
    @RegexComponentBuilder _ componentBuilder: () -> some RegexComponent<(W, repeat each Capture)>,
    transform: @escaping (W) throws -> NewCapture
  ) where RegexOutput == (Substring, NewCapture, repeat each Capture) {
    let factory = makeFactory()
    self.init(factory.capture(componentBuilder(), reference._raw, transform))
  }
}

@available(SwiftStdlib 5.7, *)
extension TryCapture {
  /// Creates a capture for the given component, attempting to transform
  /// with the given closure.
  ///
  /// - Parameters:
  ///   - componentBuilder: A builder closure that generates a regex
  ///     component to capture.
  ///   - transform: A closure that takes the substring matched by
  ///     `component` and returns a new value to capture, or `nil` if
  ///     matching should proceed, backtracking if allowed. If `transform`
  ///     throws an error, matching is abandoned and the error is returned
  ///     to the caller.
  @_alwaysEmitIntoClient
  public init<W, each Capture, NewCapture>(
    @RegexComponentBuilder _ componentBuilder: () -> some RegexComponent<(W, repeat each Capture)>,
    transform: @escaping (W) throws -> NewCapture?
  ) where RegexOutput == (Substring, NewCapture, repeat each Capture) {
    let factory = makeFactory()
    self.init(factory.captureOptional(componentBuilder(), nil, transform))
  }

  /// Creates a capture for the given component using the specified
  /// reference, attempting to transform with the given closure.
  ///
  /// - Parameters:
  ///   - reference: The reference to use for anything captured by
  ///     `component`.
  ///   - componentBuilder: A builder closure that generates a regex
  ///     component to capture.
  ///   - transform: A closure that takes the substring matched by
  ///     `component` and returns a new value to capture, or `nil` if
  ///     matching should proceed, backtracking if allowed. If `transform`
  ///     throws an error, matching is abandoned and the error is returned
  ///     to the caller.
  @_alwaysEmitIntoClient
  public init<W, each Capture, NewCapture>(
    as reference: Reference<NewCapture>,
    @RegexComponentBuilder _ componentBuilder: () -> some RegexComponent<(W, repeat each Capture)>,
    transform: @escaping (W) throws -> NewCapture?
  ) where RegexOutput == (Substring, NewCapture, repeat each Capture) {
    let factory = makeFactory()
    self.init(factory.captureOptional(componentBuilder(), reference._raw, transform))
  }
}
