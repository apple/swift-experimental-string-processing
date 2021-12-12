/*

These functions are temporary AST construction helpers. As
the AST gets more and more source-location tracking, we'll
want easier migration paths for our parser tests (which
construct and compare location-less AST nodes) as well as the
result builder DSL (which has a different notion of location).

Without real namespaces and `using`, attempts at
pseudo-namespaces tie the use site to being nested inside a
type. So for now, these are global, but they will likely be
namespaced in the future if/when clients are weaned off the
AST.

*/

import _MatchingEngine

func alt(_ asts: [AST]) -> AST {
  .alternation(.init(asts, .fake))
}
func alt(_ asts: AST...) -> AST {
  alt(asts)
}

func concat(_ asts: [AST]) -> AST {
  .concatenation(.init(asts, .fake))
}
func concat(_ asts: AST...) -> AST {
  concat(asts)
}

func group(
  _ kind: AST.Group.Kind, _ child: AST
) -> AST {
  .group(.init(.init(faking: kind), child, .fake))
}
func capture(
  _ child: AST
) -> AST {
  group(.capture, child)
}
func nonCapture(
  _ child: AST
) -> AST {
  group(.nonCapture, child)
}
func namedCapture(
  _ name: String,
  _ child: AST
) -> AST {
  group(.namedCapture(.init(faking: name)), child)
}
func nonCaptureReset(
  _ child: AST
) -> AST {
  group(.nonCaptureReset, child)
}
func atomicNonCapturing(
  _ child: AST
) -> AST {
  group(.atomicNonCapturing, child)
}
func lookahead(_ child: AST) -> AST {
  group(.lookahead, child)
}
func lookbehind(_ child: AST) -> AST {
  group(.lookbehind, child)
}
func negativeLookahead(_ child: AST) -> AST {
  group(.negativeLookahead, child)
}
func negativeLookbehind(_ child: AST) -> AST {
  group(.negativeLookbehind, child)
}


var any: AST { .atom(.any) }

func quant(
  _ amount: AST.Quantification.Amount,
  _ kind: AST.Quantification.Kind = .greedy,
  _ child: AST
) -> AST {
  .quantification(.init(
    .init(faking: amount), .init(faking: kind), child, .fake))
}
func zeroOrMore(
  _ kind: AST.Quantification.Kind = .greedy,
  _ child: AST
) -> AST {
  quant(.zeroOrMore, kind, child)
}
func zeroOrOne(
  _ kind: AST.Quantification.Kind = .greedy,
  _ child: AST
) -> AST {
  quant(.zeroOrOne, kind, child)
}
func oneOrMore(
  _ kind: AST.Quantification.Kind = .greedy,
  _ child: AST
) -> AST {
  quant(.oneOrMore, kind, child)
}
func exactly(
  _ kind: AST.Quantification.Kind = .greedy,
  _ i: Int,
  _ child: AST
) -> AST {
  quant(.exactly(.init(faking: i)), kind, child)
}
func nOrMore(
  _ kind: AST.Quantification.Kind = .greedy,
  _ i: Int,
  _ child: AST
) -> AST {
  quant(.nOrMore(.init(faking: i)), kind, child)
}
func upToN(
  _ kind: AST.Quantification.Kind = .greedy,
  _ i: Int,
  _ child: AST
) -> AST {
  quant(.upToN(.init(faking: i)), kind, child)
}
func quantRange(
  _ kind: AST.Quantification.Kind = .greedy,
  _ r: ClosedRange<Int>,
  _ child: AST
) -> AST {
  let range = AST.Loc(faking: r.lowerBound) ... AST.Loc(faking: r.upperBound)
  return quant(.range(range), kind, child)
}

func charClass(
  _ members: AST.CustomCharacterClass.Member...,
  inverted: Bool = false
) -> AST {
  let cc = AST.CustomCharacterClass(
    .init(faking: inverted ? .inverted : .normal),
    members,
    .fake)
  return .customCharacterClass(cc)
}
func charClass(
  _ members: AST.CustomCharacterClass.Member...,
  inverted: Bool = false
) -> AST.CustomCharacterClass.Member {
  let cc = AST.CustomCharacterClass(
    .init(faking: inverted ? .inverted : .normal),
    members,
    .fake)
  return .custom(cc)
}
func posixSet(
  _ set: Unicode.POSIXCharacterSet, inverted: Bool = false
) -> Atom {
  .namedSet(.init(inverted: inverted, set))
}

func quote(_ s: String) -> AST {
  .quote(.init(s, .fake))
}

func prop(
  _ kind: Atom.CharacterProperty.Kind, inverted: Bool = false
) -> Atom {
  return .property(.init(kind, isInverted: inverted))
}
