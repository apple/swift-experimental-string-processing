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
    public let child: AST

    public let location: SourceLocation

    public init(
      _ kind: Located<Kind>, _ child: AST, _ r: SourceLocation
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
      // Isolated options are written as e.g (?i), and implicitly form a group
      // containing all the following elements of the current group.
      case changeMatchingOptions(MatchingOptionSequence, isIsolated: Bool)

      // NOTE: Comments appear to be groups, but are not parsed
      // the same. They parse more like quotes, so are not
      // listed here.
    }
  }
}

extension AST.Group.Kind {
  public var isCapturing: Bool {
    switch self {
    case .capture, .namedCapture: return true
    default: return false
    }
  }

  /// Whether this is a group with an implicit scope, e.g isolated matching
  /// options implicitly become parent groups for the rest of the elements in
  /// the current group:
  ///
  ///      (a(?i)bc)de -> (a(?i:bc))de
  ///
  public var hasImplicitScope: Bool {
    switch self {
    case .changeMatchingOptions(_, let isIsolated):
      return isIsolated
    default:
      return false
    }
  }

  /// If this is a named group, its name, `nil` otherwise.
  public var name: String? {
    switch self {
    case .namedCapture(let name): return name.value
    default: return nil
    }
  }
}

extension AST.Group {
  /// If this group is a lookaround assertion, return its direction
  /// and whether it is positive or negative. Otherwise returns
  /// `nil`.
  public var lookaroundKind: (forwards: Bool, positive: Bool)? {
    switch self.kind.value {
    case .lookahead:         return (true, true)
    case .negativeLookahead: return (true, false)
    case .lookbehind:         return (false, true)
    case .negativeLookbehind: return (false, false)
    default: return nil
    }
  }

}
