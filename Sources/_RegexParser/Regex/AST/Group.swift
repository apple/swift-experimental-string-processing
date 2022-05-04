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

extension AST {
  public struct Group: Hashable {
    public let kind: Located<Kind>
    public let child: AST.Node

    public let location: SourceLocation

    public init(
      _ kind: Located<Kind>, _ child: AST.Node, _ r: SourceLocation
    ) {
      self.kind = kind
      self.child = child
      self.location = r
    }

    public enum Kind: Hashable {
      // (...)
      case capture

      // (?<name>...) (?'name'...) (?P<name>...)
      case namedCapture(Located<String>)

      // (?<name-priorName>) (?'name-priorName')
      case balancedCapture(BalancedCapture)

      // (?:...)
      case nonCapture

      // (?|...)
      case nonCaptureReset

      // (?>...)
      case atomicNonCapturing

      // (?=...)
      case lookahead

      // (?!...)
      case negativeLookahead

      // (?*...)
      case nonAtomicLookahead

      // (?<=...)
      case lookbehind

      // (?<!...)
      case negativeLookbehind

      // (?<*...)
      case nonAtomicLookbehind

      // (*sr:...)
      case scriptRun

      // (*asr:...)
      case atomicScriptRun

      // (?iJmnsUxxxDPSWy{..}-iJmnsUxxxDPSW:)
      case changeMatchingOptions(MatchingOptionSequence)

      // NOTE: Comments appear to be groups, but are not parsed
      // the same. They parse more like quotes, so are not
      // listed here.
    }
  }
}

extension AST.Group.Kind {
  /// Whether the group is a capturing group.
  public var isCapturing: Bool {
    switch self {
    case .capture, .namedCapture, .balancedCapture: return true
    default: return false
    }
  }

  /// The name of the group.
  ///
  /// If the group doesn't have a name, this value is `nil`.
  public var name: String? {
    switch self {
    case .namedCapture(let name): return name.value
    case .balancedCapture(let b): return b.name?.value
    default: return nil
    }
  }
}

extension AST.Group.Kind {
  /// The direction of a lookaround assertion
  /// and an indication of whether the assertion is positive or negative.
  ///
  /// If the group isn't a lookaheand or lookbehind assertion,
  /// this value is `nil`.
  public var lookaroundKind: (forwards: Bool, positive: Bool)? {
    switch self {
    case .lookahead:         return (true, true)
    case .negativeLookahead: return (true, false)
    case .lookbehind:         return (false, true)
    case .negativeLookbehind: return (false, false)
    default: return nil
    }
  }
}

extension AST.Group {
  public struct BalancedCapture: Hashable {
    /// The name of the group, or nil if the group has no name.
    public var name: AST.Located<String>?

    /// The location of the `-` in the group.
    public var dash: SourceLocation

    /// The name of the prior group that the balancing group references.
    public var priorName: AST.Located<String>

    public init(
      name: AST.Located<String>?, dash: SourceLocation,
      priorName: AST.Located<String>
    ) {
      self.name = name
      self.dash = dash
      self.priorName = priorName
    }
  }
}
