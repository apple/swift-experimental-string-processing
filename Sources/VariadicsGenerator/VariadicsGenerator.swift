//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2021-2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

// swift run VariadicsGenerator --max-arity 10 > Sources/RegexBuilder/Variadics.swift

import ArgumentParser
#if os(macOS)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif os(Windows)
import CRT
#elseif canImport(Bionic)
import Bionic
#endif

// (T), (T)
// (T), (T, T)
// …
// (T), (T, T, T, T, T, T, T)
// (T, T), (T)
// (T, T), (T, T)
// …
// (T, T), (T, T, T, T, T, T)
// …
struct Permutations: Sequence {
  let totalArity: Int

  struct Iterator: IteratorProtocol {
    let totalArity: Int
    var leftArity: Int = 0
    var rightArity: Int = 0

    mutating func next() -> (combinedArity: Int, nextArity: Int)? {
      guard leftArity < totalArity else {
        return nil
      }
      defer {
        if leftArity + rightArity >= totalArity {
          leftArity += 1
          rightArity = 0
        } else {
          rightArity += 1
        }
      }
      return (leftArity, rightArity)
    }
  }

  public func makeIterator() -> Iterator {
    Iterator(totalArity: totalArity)
  }
}

func captureTypeList(
  _ arity: Int,
  lowerBound: Int = 0,
  optional: Bool = false
) -> String {
  let opt = optional ? "?" : ""
  return (lowerBound..<arity).map {
    "C\($0+1)\(opt)"
  }.joined(separator: ", ")
}

func output(_ content: String) {
  print(content, terminator: "")
}

func outputMark(_ content: String) {
  print("// MARK: - \(content)\n")
}

func outputForEach<C: Collection>(
  _ elements: C,
  separator: String? = nil,
  lineTerminator: String? = nil,
  _ content: (C.Element) -> String
) {
  for i in elements.indices {
    output(content(elements[i]))
    let needsSep = elements.index(after: i) != elements.endIndex
    if needsSep, let sep = separator {
      output(sep)
    }
    if let lt = lineTerminator {
      let indent = needsSep ? "      " : "    "
      output("\(lt)\n\(indent)")
    }
  }
}

struct StandardErrorStream: TextOutputStream {
  func write(_ string: String) {
    fputs(string, stderr)
  }
}
var standardError = StandardErrorStream()

typealias Counter = Int64
let regexComponentProtocolName = "RegexComponent"
let outputAssociatedTypeName = "RegexOutput"
let patternProtocolRequirementName = "regex"
let regexTypeName = "Regex"
let baseMatchTypeName = "Substring"
let concatBuilderName = "RegexComponentBuilder"
let altBuilderName = "AlternationBuilder"
let defaultAvailableAttr = "@available(SwiftStdlib 5.7, *)"

@main
struct VariadicsGenerator: ParsableCommand {
  @Option(help: "The maximum arity of declarations to generate.")
  var maxArity: Int = 10
  
  @Flag(help: "Suppress status messages while generating.")
  var silent: Bool = false

  func log(_ message: String, terminator: String = "\n") {
    if !silent {
      print(message, terminator: terminator, to: &standardError)
    }
  }
  
  func run() throws {
    precondition(maxArity > 1)
    precondition(maxArity < Counter.bitWidth)

    output("""
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

      // BEGIN AUTO-GENERATED CONTENT

      @_spi(RegexBuilder) import _StringProcessing


      """)

    log("Generating concatenation overloads...")
    for (leftArity, rightArity) in Permutations(totalArity: maxArity) {
      if rightArity == 0 {
        outputMark("Partial block (left arity \(leftArity))")
        continue
      }
      log("  Left arity: \(leftArity)  Right arity: \(rightArity)")
      emitConcatenation(leftArity: leftArity, rightArity: rightArity)
    }

    outputMark("Partial block (empty)")
    for arity in 0...maxArity {
      emitConcatenationWithEmpty(leftArity: arity)
    }

    output("\n\n")

    log("Generating quantifiers...")
    for arity in 0...maxArity {
      outputMark("Quantifiers (arity \(arity))")
      log("  Arity \(arity): ", terminator: "")
      for kind in QuantifierKind.allCases {
        log("\(kind.rawValue) ", terminator: "")
        emitQuantifier(kind: kind, arity: arity)
      }
      log("repeating ", terminator: "")
      emitRepeating(arity: arity)
      log("")
    }

    log("Generating atomic groups...")
    outputMark("Atomic groups")
    for arity in 0...maxArity {
      log("  Arity \(arity): ", terminator: "")
      emitAtomicGroup(arity: arity)
      log("")
    }

    log("Generating alternation overloads...")
    for (leftArity, rightArity) in Permutations(totalArity: maxArity) {
      if rightArity == 0 {
        outputMark("Alternation builder (arity \(leftArity))")
      }
      log("  Left arity: \(leftArity)  Right arity: \(rightArity)")
      emitAlternation(leftArity: leftArity, rightArity: rightArity)
    }

    log("Generating 'AlternationBuilder.buildBlock(_:)' overloads...")
    outputMark("Alternation builder buildBlock")
    for arity in 1...maxArity {
      log("  Capture arity: \(arity)")
      emitUnaryAlternationBuildBlock(arity: arity)
    }

    log("Generating 'capture' and 'tryCapture' overloads...")
    for arity in 0...maxArity {
      log("  Capture arity: \(arity)")
      emitCapture(arity: arity)
    }

    output("\n\n")

    output("// END AUTO-GENERATED CONTENT\n")

    log("Done!")
  }

  func tupleType(arity: Int, genericParameters: () -> String) -> String {
    assert(arity >= 0)
    if arity == 0 {
      return genericParameters()
    }
    return "(\(genericParameters()))"
  }

  func emitConcatenation(leftArity: Int, rightArity: Int) {
    let genericParams: String = {
      var result = "W0, W1, "
      result += captureTypeList(leftArity+rightArity)
      return result
    }()

    // Emit concatenation type declaration.
    let leftOutputType = leftArity == 0
      ? "W0"
      : "(W0, \(captureTypeList(leftArity)))"
    let rightOutputType = rightArity == 0
      ? "W1"
      : "(W1, \(captureTypeList(leftArity+rightArity, lowerBound: leftArity)))"

    let matchType: String = {
      if leftArity+rightArity == 0 {
        return baseMatchTypeName
      } else {
        return "(\(baseMatchTypeName), "
          + captureTypeList(leftArity+rightArity)
          + ")"
      }
    }()

    // Emit concatenation builder.
    output("""
      \(defaultAvailableAttr)
      extension \(concatBuilderName) {
        @_alwaysEmitIntoClient
        public static func buildPartialBlock<\(genericParams)>(
          accumulated: some RegexComponent<\(leftOutputType)>,
          next: some RegexComponent<\(rightOutputType)>
        ) -> \(regexTypeName)<\(matchType)> {
          let factory = makeFactory()
      
      """)
    if leftArity == 0 {
      output("""
          return factory.accumulate(ignoringOutputTypeOf: accumulated, next)
      
      """)
    } else {
      output("""
          return factory.accumulate(accumulated, next)
      
      """)
    }
    output("""
        }
      }

      """)
  }

  func emitConcatenationWithEmpty(leftArity: Int) {
    // T + () = T
    output("""
      \(defaultAvailableAttr)
      extension \(concatBuilderName) {
        @_alwaysEmitIntoClient
        public static func buildPartialBlock<W0
      """)
    outputForEach(0..<leftArity) {
      ", C\($0)"
    }
    output("""
      >(
          accumulated: some \(regexComponentProtocolName)<
      """)
    if leftArity == 0 {
      output("W0")
    } else {
      output("(W0")
      outputForEach(0..<leftArity) {
        ", C\($0)"
      }
      output(")")
    }
    output("""
      >,
          next: some \(regexComponentProtocolName)
        ) -> \(regexTypeName)<
      """)
    if leftArity == 0 {
      output(baseMatchTypeName)
    } else {
      output("(\(baseMatchTypeName)")
      outputForEach(0..<leftArity) {
        ", C\($0)"
      }
      output(")")
    }
    output("""
      > {
          let factory = makeFactory()
      
      """)
    if leftArity == 0 {
      output("""
          return factory.accumulate(ignoringOutputTypeOf: accumulated, andAlso: next)
      
      """)
    } else {
      output("""
          return factory.accumulate(accumulated, ignoringOutputTypeOf: next)
      
      """)
    }
    output("""
        }
      }

      """)
  }

  enum QuantifierKind: String, CaseIterable {
    case zeroOrOne = "Optionally"
    case zeroOrMore = "ZeroOrMore"
    case oneOrMore = "OneOrMore"

    var operatorName: String {
      switch self {
      case .zeroOrOne: return ".?"
      case .zeroOrMore: return ".*"
      case .oneOrMore: return ".+"
      }
    }

    var astQuantifierAmount: String {
      switch self {
      case .zeroOrOne: return "zeroOrOne"
      case .zeroOrMore: return "zeroOrMore"
      case .oneOrMore: return "oneOrMore"
      }
    }
    
    var commentAbstract: String {
      switch self {
      case .zeroOrOne: return """
          /// Creates a regex component that matches the given component
          /// zero or one times.
        """
      case .zeroOrMore: return """
          /// Creates a regex component that matches the given component
          /// zero or more times.
        """
      case .oneOrMore: return """
          /// Creates a regex component that matches the given component
          /// one or more times.
        """
      }
    }
  }
  
  struct QuantifierParameters {
    var arity: Int
    var disfavored: String
    var genericParams: String
    var whereClauseForInit: String
    var quantifiedCaptures: String
    var matchType: String
    
    init(kind: QuantifierKind, arity: Int) {
      self.arity = arity
      self.disfavored = arity == 0 ? "  @_disfavoredOverload\n" : ""
      self.genericParams = {
        var result = ""
        if arity > 0 {
          result += "W, "
          result += captureTypeList(arity)
        }
        return result.isEmpty
          ? ""
          : "<\(result)>"
      }()

      let capturesJoined = captureTypeList(arity)
      self.quantifiedCaptures = {
        switch kind {
        case .zeroOrOne, .zeroOrMore:
          return captureTypeList(arity, optional: true)
        case .oneOrMore:
          return capturesJoined
        }
      }()
      self.matchType = arity == 0
        ? baseMatchTypeName
        : "(\(baseMatchTypeName), \(quantifiedCaptures))"
      self.whereClauseForInit = "where \(outputAssociatedTypeName) == \(matchType)"
    }
    
    var primaryAssociatedType: String {
      arity == 0 ? "" : "<(W, \(captureTypeList(arity)))>"
    }
  }

  func emitQuantifier(kind: QuantifierKind, arity: Int) {
    assert(arity >= 0)
    let params = QuantifierParameters(kind: kind, arity: arity)
    output("""
      \(defaultAvailableAttr)
      extension \(kind.rawValue) {
      \(kind.commentAbstract)
        ///
        /// - Parameters:
        ///   - component: The regex component.
        ///   - behavior: The repetition behavior to use when repeating
        ///     `component` in the match. If `behavior` is `nil`, the default
        ///     repetition behavior is used, which can be changed from
        ///     `eager` by calling `repetitionBehavior(_:)` on the resulting
        ///     `Regex`.
      \(params.disfavored)\
        @_alwaysEmitIntoClient
        public init\(params.genericParams)(
          _ component: some RegexComponent\(params.primaryAssociatedType),
          _ behavior: RegexRepetitionBehavior? = nil
        ) \(params.whereClauseForInit) {
          let factory = makeFactory()
          self.init(factory.\(kind.astQuantifierAmount)(component, behavior))
        }
      }

      \(defaultAvailableAttr)
      extension \(kind.rawValue) {
      \(kind.commentAbstract)
        ///
        /// - Parameters:
        ///   - behavior: The repetition behavior to use when repeating
        ///     `component` in the match. If `behavior` is `nil`, the default
        ///     repetition behavior is used, which can be changed from
        ///     `eager` by calling `repetitionBehavior(_:)` on the resulting
        ///     `Regex`.
        ///   - componentBuilder: A builder closure that generates a regex
        ///     component.
      \(params.disfavored)\
        @_alwaysEmitIntoClient
        public init\(params.genericParams)(
          _ behavior: RegexRepetitionBehavior? = nil,
          @\(concatBuilderName) _ componentBuilder: () -> some RegexComponent\(params.primaryAssociatedType)
        ) \(params.whereClauseForInit) {
          let factory = makeFactory()
          self.init(factory.\(kind.astQuantifierAmount)(componentBuilder(), behavior))
        }
      }

      \(kind == .zeroOrOne ?
        """
        \(defaultAvailableAttr)
        extension \(concatBuilderName) {
          @_alwaysEmitIntoClient
          public static func buildLimitedAvailability\(params.genericParams)(
            _ component: some RegexComponent\(params.primaryAssociatedType)
          ) -> \(regexTypeName)<\(params.matchType)> {
            let factory = makeFactory()
            return factory.\(kind.astQuantifierAmount)(component, nil)
          }
        }
        """ : "")

      """)
  }


  func emitAtomicGroup(arity: Int) {
    assert(arity >= 0)
    let groupName = "Local"
    func node(builder: Bool) -> String {
      """
      component\(builder ? "Builder()" : "")
      """
    }

    let disfavored = arity == 0 ? "  @_disfavoredOverload\n" : ""
    let genericParams: String = {
      var result = ""
      if arity > 0 {
        result += "<W, "
        result += captureTypeList(arity)
        result += ">"
      }
      return result
    }()
    let capturesJoined = captureTypeList(arity)
    let matchType = arity == 0
      ? baseMatchTypeName
      : "(\(baseMatchTypeName), \(capturesJoined))"
    let whereClauseForInit = "where \(outputAssociatedTypeName) == \(matchType)"

    output("""
      \(defaultAvailableAttr)
      extension \(groupName) {
        /// Creates an atomic group with the given regex component.
        ///
        /// - Parameter component: The regex component to wrap in an atomic
        ///   group.
        \(defaultAvailableAttr)
      \(disfavored)\
        @_alwaysEmitIntoClient
        public init\(genericParams)(
          _ component: some RegexComponent\(arity == 0 ? "" : "<(W, \(capturesJoined))>")
        ) \(whereClauseForInit) {
          let factory = makeFactory()
          self.init(factory.atomicNonCapturing(\(node(builder: false))))
        }
      }

      \(defaultAvailableAttr)
      extension \(groupName) {
        /// Creates an atomic group with the given regex component.
        ///
        /// - Parameter componentBuilder: A builder closure that generates a
        ///   regex component to wrap in an atomic group.
        \(defaultAvailableAttr)
      \(disfavored)\
        @_alwaysEmitIntoClient
        public init\(genericParams)(
          @\(concatBuilderName) _ componentBuilder: () -> some RegexComponent\(arity == 0 ? "" : "<(W, \(capturesJoined))>")
        ) \(whereClauseForInit) {
          let factory = makeFactory()
          self.init(factory.atomicNonCapturing(\(node(builder: true))))
        }
      }

      """)
  }

  
  func emitRepeating(arity: Int) {
    assert(arity >= 0)
    // `repeat(..<5)` has the same generic semantics as zeroOrMore
    let params = QuantifierParameters(kind: .zeroOrMore, arity: arity)
    // TODO: Could `repeat(count:)` have the same generic semantics as oneOrMore?
    // We would need to prohibit `repeat(count: 0)`; can only happen at runtime
    
    output("""
      \(defaultAvailableAttr)
      extension Repeat {
        /// Creates a regex component that matches the given component repeated
        /// the specified number of times.
        ///
        /// - Parameters:
        ///   - component: The regex component to repeat.
        ///   - count: The number of times to repeat `component`. `count` must
        ///     be greater than or equal to zero.
      \(params.disfavored)\
        @_alwaysEmitIntoClient
        public init\(params.genericParams)(
          _ component: some RegexComponent\(params.primaryAssociatedType),
          count: Int
        ) \(params.whereClauseForInit) {
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
      \(params.disfavored)\
        @_alwaysEmitIntoClient
        public init\(params.genericParams)(
          count: Int,
          @\(concatBuilderName) _ componentBuilder: () -> some RegexComponent\(params.primaryAssociatedType)
        ) \(params.whereClauseForInit) {
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
      \(params.disfavored)\
        @_alwaysEmitIntoClient
        public init\(params.genericParams)(
          _ component: some RegexComponent\(params.primaryAssociatedType),
          _ expression: some RangeExpression<Int>,
          _ behavior: RegexRepetitionBehavior? = nil
        ) \(params.whereClauseForInit) {
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
      \(params.disfavored)\
        @_alwaysEmitIntoClient
        public init\(params.genericParams)(
          _ expression: some RangeExpression<Int>,
          _ behavior: RegexRepetitionBehavior? = nil,
          @\(concatBuilderName) _ componentBuilder: () -> some RegexComponent\(params.primaryAssociatedType)
        ) \(params.whereClauseForInit) {
          let factory = makeFactory()
          self.init(factory.repeating(expression.relative(to: 0..<Int.max), behavior, componentBuilder()))
        }
      }
      
      """)
  }

  func emitAlternation(leftArity: Int, rightArity: Int) {
    let leftCaptureTypes = captureTypeList(leftArity)
    let rightCaptureTypes = captureTypeList(leftArity + rightArity, lowerBound: leftArity)
    let leftGenParams = leftArity == 0
      ? ""
      : "W0, " + leftCaptureTypes
    let rightGenParams = rightArity == 0
      ? ""
      : "W1, " + rightCaptureTypes
    let _bothParams = [leftGenParams, rightGenParams]
      .filter { !$0.isEmpty }
      .joined(separator: ", ")
    let genericParams = _bothParams.isEmpty
      ? ""
      : "<\(_bothParams)>"
    
    let resultCaptures: String = {
      var result = leftCaptureTypes
      if leftArity > 0, rightArity > 0 {
        result += ", "
      }
      result += captureTypeList(leftArity + rightArity, lowerBound: leftArity, optional: true)
      return result
    }()
    let matchType: String = {
      if leftArity == 0, rightArity == 0 {
        return baseMatchTypeName
      }
      return "(\(baseMatchTypeName), \(resultCaptures))"
    }()
    output("""
      \(defaultAvailableAttr)
      extension \(altBuilderName) {
        @_alwaysEmitIntoClient
        public static func buildPartialBlock\(genericParams)(
          accumulated: some RegexComponent\(leftGenParams.isEmpty ? "" : "<(\(leftGenParams))>"),
          next: some RegexComponent\(rightGenParams.isEmpty ? "" : "<(\(rightGenParams))>")
        ) -> ChoiceOf<\(matchType)> {
          let factory = makeFactory()
          return .init(factory.accumulateAlternation(accumulated, next))
        }
      }

      """)
  }

  func emitUnaryAlternationBuildBlock(arity: Int) {
    assert(arity > 0)
    let captures = captureTypeList(arity)
    let genericParams: String = {
      if arity == 0 {
        return "R"
      }
      return "R, W, " + captures
    }()
    let whereClause: String = """
      where R: \(regexComponentProtocolName), \
      R.\(outputAssociatedTypeName) == (W, \(captures))
      """
    let resultCaptures = captureTypeList(arity, optional: true)
    output("""
      \(defaultAvailableAttr)
      extension \(altBuilderName) {
        @_alwaysEmitIntoClient
        public static func buildPartialBlock<\(genericParams)>(first regex: R) -> ChoiceOf<(W, \(resultCaptures))> \(whereClause) {
          let factory = makeFactory()
          return .init(factory.orderedChoice(regex))
        }
      }
      
      """)
  }

  func emitCapture(arity: Int) {
    let disfavored = arity == 0 ? "  @_disfavoredOverload\n" : ""
    let genericParams = arity == 0
      ? "W"
      : "W, " + captureTypeList(arity)
    let matchType = arity == 0
      ? "W"
      : "(W, " + captureTypeList(arity) + ")"
    func newMatchType(newCaptureType: String) -> String {
      return arity == 0
        ? "(\(baseMatchTypeName), \(newCaptureType))"
        : "(\(baseMatchTypeName), \(newCaptureType), " + captureTypeList(arity) + ")"
    }
    let rawNewMatchType = newMatchType(newCaptureType: "W")
    let transformedNewMatchType = newMatchType(newCaptureType: "NewCapture")
    let whereClauseRaw = "where \(outputAssociatedTypeName) == \(rawNewMatchType)"
    let whereClauseTransformed = "where \(outputAssociatedTypeName) == \(transformedNewMatchType)"
    outputMark("Non-builder capture (arity \(arity))")
    output("""
      \(defaultAvailableAttr)
      extension Capture {
        /// Creates a capture for the given component.
        ///
        /// - Parameter component: The regex component to capture.
      \(disfavored)\
        @_alwaysEmitIntoClient
        public init<\(genericParams)>(
          _ component: some RegexComponent<\(matchType)>
        ) \(whereClauseRaw) {
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
      \(disfavored)\
        @_alwaysEmitIntoClient
        public init<\(genericParams)>(
          _ component: some RegexComponent<\(matchType)>,
          as reference: Reference<W>
        ) \(whereClauseRaw) {
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
      \(disfavored)\
        @_alwaysEmitIntoClient
        public init<\(genericParams), NewCapture>(
          _ component: some RegexComponent<\(matchType)>,
          transform: @escaping (W) throws -> NewCapture
        ) \(whereClauseTransformed) {
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
      \(disfavored)\
        @_alwaysEmitIntoClient
        public init<\(genericParams), NewCapture>(
          _ component: some RegexComponent<\(matchType)>,
          as reference: Reference<NewCapture>,
          transform: @escaping (W) throws -> NewCapture
        ) \(whereClauseTransformed) {
          let factory = makeFactory()
          self.init(factory.capture(component, reference._raw, transform))
        }
      }

      \(defaultAvailableAttr)
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
      \(disfavored)\
        @_alwaysEmitIntoClient
        public init<\(genericParams), NewCapture>(
          _ component: some RegexComponent<\(matchType)>,
          transform: @escaping (W) throws -> NewCapture?
        ) \(whereClauseTransformed) {
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
      \(disfavored)\
        @_alwaysEmitIntoClient
        public init<\(genericParams), NewCapture>(
          _ component: some RegexComponent<\(matchType)>,
          as reference: Reference<NewCapture>,
          transform: @escaping (W) throws -> NewCapture?
        ) \(whereClauseTransformed) {
          let factory = makeFactory()
          self.init(factory.captureOptional(component, reference._raw, transform))
        }
      }
      
      """)
      outputMark("Builder capture (arity \(arity))")
      output("""
      \(defaultAvailableAttr)
      extension Capture {
        /// Creates a capture for the given component.
        ///
        /// - Parameter componentBuilder: A builder closure that generates a
        ///   regex component to capture.
      \(disfavored)\
        @_alwaysEmitIntoClient
        public init<\(genericParams)>(
          @\(concatBuilderName) _ componentBuilder: () -> some RegexComponent<\(matchType)>
        ) \(whereClauseRaw) {
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
      \(disfavored)\
        @_alwaysEmitIntoClient
        public init<\(genericParams)>(
          as reference: Reference<W>,
          @\(concatBuilderName) _ componentBuilder: () -> some RegexComponent<\(matchType)>
        ) \(whereClauseRaw) {
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
      \(disfavored)\
        @_alwaysEmitIntoClient
        public init<\(genericParams), NewCapture>(
          @\(concatBuilderName) _ componentBuilder: () -> some RegexComponent<\(matchType)>,
          transform: @escaping (W) throws -> NewCapture
        ) \(whereClauseTransformed) {
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
      \(disfavored)\
        @_alwaysEmitIntoClient
        public init<\(genericParams), NewCapture>(
          as reference: Reference<NewCapture>,
          @\(concatBuilderName) _ componentBuilder: () -> some RegexComponent<\(matchType)>,
          transform: @escaping (W) throws -> NewCapture
        ) \(whereClauseTransformed) {
          let factory = makeFactory()
          self.init(factory.capture(componentBuilder(), reference._raw, transform))
        }
      }

      \(defaultAvailableAttr)
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
      \(disfavored)\
        @_alwaysEmitIntoClient
        public init<\(genericParams), NewCapture>(
          @\(concatBuilderName) _ componentBuilder: () -> some RegexComponent<\(matchType)>,
          transform: @escaping (W) throws -> NewCapture?
        ) \(whereClauseTransformed) {
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
      \(disfavored)\
        @_alwaysEmitIntoClient
        public init<\(genericParams), NewCapture>(
          as reference: Reference<NewCapture>,
          @\(concatBuilderName) _ componentBuilder: () -> some RegexComponent<\(matchType)>,
          transform: @escaping (W) throws -> NewCapture?
        ) \(whereClauseTransformed) {
          let factory = makeFactory()
          self.init(factory.captureOptional(componentBuilder(), reference._raw, transform))
        }
      }


      """)
  }
}
