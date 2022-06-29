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

@_spi(_Unicode) import Swift
@_implementationOnly import _RegexParser

extension DSLTree.Node {
  /// Attempt to generate a consumer from this AST node
  ///
  /// A consumer is a Swift closure that matches against
  /// the front of an input range
  func generateConsumer(
    _ opts: MatchingOptions
  ) throws -> MEProgram.ConsumeFunction? {
    switch self {
    case .atom(let a):
      return try a.generateConsumer(opts)
    case .customCharacterClass(let ccc):
      return try ccc.generateConsumer(opts)

    case .quotedLiteral:
      // TODO: Should we handle this here?
      return nil

    case .regexLiteral:
      fatalError(
        "unreachable: We should only ask atoms")

    case let .convertedRegexLiteral(n, _):
      return try n.generateConsumer(opts)

    case .orderedChoice, .conditional, .concatenation,
        .capture, .nonCapturingGroup,
        .quantification, .trivia, .empty,
        .absentFunction: return nil

    case .consumer:
      fatalError("FIXME: Is this where we handle them?")
    case .matcher:
      fatalError("FIXME: Is this where we handle them?")
    case .characterPredicate:
      fatalError("FIXME: Is this where we handle them?")
    }
  }
}

extension DSLTree._AST.Atom {
  var singleScalarASCIIValue: UInt8? {
    return ast.singleScalarASCIIValue
  }
}

extension DSLTree.Atom {
  var singleScalarASCIIValue: UInt8? {
    switch self {
    case let .char(c) where c != "\r\n":
      return c.asciiValue
    case let .scalar(s) where s.isASCII:
      return UInt8(ascii: s)
    case let .unconverted(atom):
      return atom.singleScalarASCIIValue
    default:
      return nil
    }
  }
  
  // TODO: If ByteCodeGen switches first, then this is unnecessary for
  // top-level nodes, but it's also invoked for `.atom` members of a custom CC
  func generateConsumer(
    _ opts: MatchingOptions
  ) throws -> MEProgram.ConsumeFunction? {
    let isCaseInsensitive = opts.isCaseInsensitive
    
    switch self {
    case let .char(c):
      if opts.semanticLevel == .graphemeCluster {
        return { input, bounds in
          let low = bounds.lowerBound
          if isCaseInsensitive && c.isCased {
            return input[low].lowercased() == c.lowercased()
              ? input.index(after: low)
              : nil
          } else {
            return input[low] == c
              ? input.index(after: low)
              : nil
          }
        }
      } else {
        let consumers = c.unicodeScalars.map { s in consumeScalar {
          isCaseInsensitive
            ? $0.properties.lowercaseMapping == s.properties.lowercaseMapping
            : $0 == s
        }}
        return { input, bounds in
          for fn in consumers {
            if let idx = fn(input, bounds) {
              return idx
            }
          }
          return nil
        }
      }
    case let .scalar(s):
      return consumeScalar {
        isCaseInsensitive
          ? $0.properties.lowercaseMapping == s.properties.lowercaseMapping
          : $0 == s
      }

    case .any:
      // FIXME: Should this be a total ordering?
      fatalError(
        "unreachable: emitAny() should be called isntead")

    case .assertion:
      // TODO: We could handle, should this be total?
      return nil

    case .backreference:
      // TODO: Should we handle?
      return nil

    case .symbolicReference:
      // TODO: Should we handle?
      return nil

    case .changeMatchingOptions:
      // TODO: Should we handle?
      return nil

    case let .unconverted(a):
      return try a.ast.generateConsumer(opts)
    }

  }
}

extension String {
  /// Compares this string to `other` using the loose matching rule UAX44-LM2,
  /// which ignores case, whitespace, underscores, and nearly all medial
  /// hyphens.
  ///
  /// FIXME: Only ignore medial hyphens
  /// FIXME: Special case for U+1180 HANGUL JUNGSEONG O-E
  /// See https://www.unicode.org/reports/tr44/#Matching_Rules
  fileprivate func isEqualByUAX44LM2(to other: String) -> Bool {
    var index = startIndex
    var otherIndex = other.startIndex
    
    while index < endIndex && otherIndex < other.endIndex {
      if self[index].isWhitespace || self[index] == "-" || self[index] == "_" {
        formIndex(after: &index)
        continue
      }
      if other[otherIndex].isWhitespace || other[otherIndex] == "-" || other[otherIndex] == "_" {
        other.formIndex(after: &otherIndex)
        continue
      }
      
      if self[index] != other[otherIndex] && self[index].lowercased() != other[otherIndex].lowercased() {
        return false
      }

      formIndex(after: &index)
      other.formIndex(after: &otherIndex)
    }
    return index == endIndex && otherIndex == other.endIndex
  }
}

func consumeName(_ name: String, opts: MatchingOptions) -> MEProgram.ConsumeFunction {
  let consume = consumeFunction(for: opts)
  return consume(propertyScalarPredicate {
    // FIXME: name aliases not covered by $0.nameAlias are missed
    // e.g. U+FEFF has both 'BYTE ORDER MARK' and 'BOM' as aliases
    $0.name?.isEqualByUAX44LM2(to: name) == true
      || $0.nameAlias?.isEqualByUAX44LM2(to: name) == true
  })
}

// TODO: This is basically an AST interpreter, which would
// be good or interesting to build regardless, and serves
// as a compiler fall-back path

extension AST.Atom {
  // TODO: clarify difference between this and
  // literal character value...
  //
  // For now this just extracts `.char` case
  //
  // TODO: Shouldn't this be parameterized over matching
  // level?
  var singleCharacter: Character? {
    switch kind {
    case .char(let c): return c
    default: return nil
    }
  }

  var singleScalar: UnicodeScalar? {
    switch kind {
    case .scalar(let s): return s.value
    default: return nil
    }
  }
  
  var singleScalarASCIIValue: UInt8? {
    switch kind {
    case let .char(c) where c != "\r\n":
      return c.asciiValue
    case let .scalar(s) where s.value.isASCII:
      return UInt8(ascii: s.value)
    default:
      return nil
    }
  }
  
  func generateConsumer(
    _ opts: MatchingOptions
  ) throws -> MEProgram.ConsumeFunction? {
    // TODO: Wean ourselves off of this type...
    if let cc = self.characterClass?.withMatchLevel(
      opts.matchLevel
    ) {
      return { input, bounds in
        // FIXME: should we worry about out of bounds?
        cc.matches(in: input, at: bounds.lowerBound, with: opts)
      }
    }

    switch kind {
    case let .scalar(s):
      assertionFailure(
        "Should have been handled by tree conversion")
      return consumeScalar { $0 == s.value }

    case let .char(c):
      assertionFailure(
        "Should have been handled by tree conversion")

      // TODO: Match level?
      return { input, bounds in
        let low = bounds.lowerBound
        guard input[low] == c else {
          return nil
        }
        return input.index(after: low)
      }

    case let .property(p):
      return try p.generateConsumer(opts)

    case let .namedCharacter(name):
      return consumeName(name, opts: opts)
      
    case .any:
      assertionFailure(
        "Should have been handled by tree conversion")
      fatalError(".atom(.any) is handled in emitAny")

    case .startOfLine, .endOfLine:
      // handled in emitAssertion
      return nil

    case .scalarSequence, .escaped, .keyboardControl, .keyboardMeta,
        .keyboardMetaControl, .backreference, .subpattern, .callout,
        .backtrackingDirective, .changeMatchingOptions:
      // FIXME: implement
      return nil
    }
  }
}

extension DSLTree.CustomCharacterClass.Member {
  func asAsciiBitset(
    _ opts: MatchingOptions,
    _ isInverted: Bool
  ) -> DSLTree.CustomCharacterClass.AsciiBitset? {
    switch self {
    case let .atom(a):
      if let val = a.singleScalarASCIIValue {
        return DSLTree.CustomCharacterClass.AsciiBitset(
          val,
          isInverted,
          opts.isCaseInsensitive
        )
      }
    case let .range(low, high):
      if let lowVal = low.singleScalarASCIIValue, let highVal = high.singleScalarASCIIValue {
        return DSLTree.CustomCharacterClass.AsciiBitset(
          low: lowVal,
          high: highVal,
          isInverted: isInverted,
          isCaseInsensitive: opts.isCaseInsensitive
        )
      }
    default:
      return nil
    }
    return nil
  }
  
  func generateConsumer(
    _ opts: MatchingOptions
  ) throws -> MEProgram.ConsumeFunction {
    switch self {
    case let .atom(a):
      guard let c = try a.generateConsumer(opts) else {
        throw Unsupported("Consumer for \(a)")
      }
      return c
    case let .range(low, high):
      // TODO:
      guard let lhs = low.literalCharacterValue else {
        throw Unsupported("\(low) in range")
      }
      guard let rhs = high.literalCharacterValue else {
        throw Unsupported("\(high) in range")
      }

      if opts.isCaseInsensitive {
        let lhsLower = lhs.lowercased()
        let rhsLower = rhs.lowercased()
        guard lhsLower <= rhsLower else { throw Unsupported("Invalid range \(lhs)-\(rhs)") }
        return { input, bounds in
          // TODO: check for out of bounds?
          let curIdx = bounds.lowerBound
          if (lhsLower...rhsLower).contains(input[curIdx].lowercased()) {
            // TODO: semantic level
            return input.index(after: curIdx)
          }
          return nil
        }
      } else {
        guard lhs <= rhs else { throw Unsupported("Invalid range \(lhs)-\(rhs)") }
        return { input, bounds in
          // TODO: check for out of bounds?
          let curIdx = bounds.lowerBound
          if (lhs...rhs).contains(input[curIdx]) {
            // TODO: semantic level
            return input.index(after: curIdx)
          }
          return nil
        }
      }

    case let .custom(ccc):
      return try ccc.generateConsumer(opts)

    case let .intersection(lhs, rhs):
      let lhs = try lhs.generateConsumer(opts)
      let rhs = try rhs.generateConsumer(opts)
      return { input, bounds in
        if let lhsIdx = lhs(input, bounds),
           let rhsIdx = rhs(input, bounds)
        {
          guard lhsIdx == rhsIdx else {
            fatalError("TODO: What should we do here?")
          }
          return lhsIdx
        }
        return nil
      }

    case let .subtraction(lhs, rhs):
      let lhs = try lhs.generateConsumer(opts)
      let rhs = try rhs.generateConsumer(opts)
      return { input, bounds in
        if let lhsIdx = lhs(input, bounds),
           rhs(input, bounds) == nil
        {
          return lhsIdx
        }
        return nil
      }

    case let .symmetricDifference(lhs, rhs):
      let lhs = try lhs.generateConsumer(opts)
      let rhs = try rhs.generateConsumer(opts)
      return { input, bounds in
        if let lhsIdx = lhs(input, bounds) {
          return rhs(input, bounds) == nil ? lhsIdx : nil
        }
        return rhs(input, bounds)
      }
    case .quotedLiteral(let s):
      if opts.isCaseInsensitive {
        return { input, bounds in
          guard s.lowercased()._contains(input[bounds.lowerBound].lowercased()) else {
            return nil
          }
          return input.index(after: bounds.lowerBound)
        }
      } else {
        return { input, bounds in
          guard s.contains(input[bounds.lowerBound]) else {
            return nil
          }
          return input.index(after: bounds.lowerBound)
        }
      }
    case .trivia:
      // TODO: Should probably strip this earlier...
      return { _, _ in nil }
    }
  }
}

extension DSLTree.CustomCharacterClass {
  func asAsciiBitset(_ opts: MatchingOptions) -> AsciiBitset? {
    return members.reduce(
      .init(isInverted: isInverted),
      {result, member in
        if let next = member.asAsciiBitset(opts, isInverted) {
          return result?.union(next)
        } else {
          return nil
        }
      }
    )
  }
  
  func generateConsumer(
    _ opts: MatchingOptions
  ) throws -> MEProgram.ConsumeFunction {
    // NOTE: Easy way to implement, obviously not performant
    let consumers = try members.map {
      try $0.generateConsumer(opts)
    }
    return { input, bounds in
      for consumer in consumers {
        if let idx = consumer(input, bounds) {
          return isInverted ? nil : idx
        }
      }
      if isInverted {
        return opts.semanticLevel == .graphemeCluster
          ? input.index(after: bounds.lowerBound)
          : input.unicodeScalars.index(after: bounds.lowerBound)
      }
      return nil
    }
  }
}

// NOTE: Conveniences, though not most performant
typealias ScalarPredicate = (UnicodeScalar) -> Bool

private func scriptScalarPredicate(_ s: Unicode.Script) -> ScalarPredicate {
  {
    if #available(SwiftStdlib 5.7, *) {
      return unsafeBitCast($0.properties._script, to: Unicode.Script.self) == s
    } else {
      return false
    }
  }
}
private func scriptExtensionScalarPredicate(_ s: Unicode.Script) -> ScalarPredicate {
  {
    if #available(SwiftStdlib 5.7, *) {
      let extensions = $0.properties._scriptExtensions
      return extensions.contains(unsafeBitCast(s, to: UInt8.self))
    } else {
      return false
    }
  }
}
private func categoryScalarPredicate(_ gc: Unicode.GeneralCategory) -> ScalarPredicate {
  { gc == $0.properties.generalCategory }
}
private func categoriesScalarPredicate(_ gcs: [Unicode.GeneralCategory]) -> ScalarPredicate {
  { gcs.contains($0.properties.generalCategory) }
}
private func propertyScalarPredicate(_ p: @escaping (Unicode.Scalar.Properties) -> Bool) -> ScalarPredicate {
  { p($0.properties) }
}

func consumeScalar(
  _ p: @escaping ScalarPredicate
) -> MEProgram.ConsumeFunction {
  { input, bounds in
    // TODO: bounds check?
    let curIdx = bounds.lowerBound
    if p(input.unicodeScalars[curIdx]) {
      // TODO: semantic level?
      return input.unicodeScalars.index(after: curIdx)
    }
    return nil
  }
}
func consumeCharacterWithLeadingScalar(
  _ p: @escaping ScalarPredicate
) -> MEProgram.ConsumeFunction {
  { input, bounds in
    let curIdx = bounds.lowerBound
    if p(input[curIdx].unicodeScalars.first!) {
      return input.index(after: curIdx)
    }
    return nil
  }
}
func consumeCharacterWithSingleScalar(
  _ p: @escaping ScalarPredicate
) -> MEProgram.ConsumeFunction {
  { input, bounds in
    let curIdx = bounds.lowerBound
    
    if input[curIdx].hasExactlyOneScalar && p(input[curIdx].unicodeScalars.first!) {
      return input.index(after: curIdx)
    }
    return nil
  }
}

func consumeFunction(
  for opts: MatchingOptions
) -> (@escaping ScalarPredicate) -> MEProgram.ConsumeFunction {
  opts.semanticLevel == .graphemeCluster
    ? consumeCharacterWithLeadingScalar
    : consumeScalar
}

extension AST.Atom.CharacterProperty {
  func generateConsumer(
    _ opts: MatchingOptions
  ) throws -> MEProgram.ConsumeFunction {
    // Handle inversion for us, albeit not efficiently
    func invert(
      _ p: @escaping MEProgram.ConsumeFunction
    ) -> MEProgram.ConsumeFunction {
      return { input, bounds in
        if p(input, bounds) != nil { return nil }

        // TODO: bounds check
        return opts.semanticLevel == .graphemeCluster
          ? input.index(after: bounds.lowerBound)
          : input.unicodeScalars.index(after: bounds.lowerBound)
      }
    }

    let consume = consumeFunction(for: opts)
    let preInversion: MEProgram.ConsumeFunction =
    try {
      switch kind {
        // TODO: is this modeled differently?
      case .any:
        return { input, bounds in
          // TODO: bounds check?
          return input.index(after: bounds.lowerBound)
        }
      case .assigned:
        return consume {
          $0.properties.generalCategory != .unassigned
        }
      case .ascii:
        // Note: ASCII must look at the whole character, not just the first
        // scalar. That is, "e\u{301}" is not an ASCII character, even though
        // the first scalar is.
        return opts.semanticLevel == .graphemeCluster
          ? consumeCharacterWithSingleScalar(\.isASCII)
          : consumeScalar(\.isASCII)

      case .generalCategory(let p):
        return try p.generateConsumer(opts)
//        fatalError("TODO: Map categories: \(p)")

      case .binary(let prop, value: let value):
        let cons = try prop.generateConsumer(opts)
        return value ? cons : invert(cons)

      case .script(let s):
        return consume(scriptScalarPredicate(s))

      case .scriptExtension(let s):
        return consume(scriptExtensionScalarPredicate(s))
        
      case .named(let n):
        return consumeName(n, opts: opts)

      case .age(let major, let minor):
        return consume {
          guard let age = $0.properties.age else { return false }
          return age <= (major, minor)
        }
        
      case .numericValue(let value):
        return consume { $0.properties.numericValue == value }
        
      case .numericType(let type):
        return consume { $0.properties.numericType == type }
        
      case .ccc(let ccc):
        return consume { $0.properties.canonicalCombiningClass == ccc }
        
      case .mapping(.lowercase, let value):
        return consume { $0.properties.lowercaseMapping == value }

      case .mapping(.uppercase, let value):
        return consume { $0.properties.uppercaseMapping == value }

      case .mapping(.titlecase, let value):
        return consume { $0.properties.titlecaseMapping == value }

      case .block(let b):
        throw Unsupported("TODO: map block: \(b)")

      case .posix(let p):
        return p.generateConsumer(opts)

      case .pcreSpecial(let s):
        throw Unsupported("TODO: map PCRE special: \(s)")

      case .javaSpecial(let s):
        throw Unsupported("TODO: map Java special: \(s)")
      }
    }()

    if !isInverted { return preInversion }
    return invert(preInversion)
  }
}

extension Unicode.BinaryProperty {
  // FIXME: Semantic level, vet for precise defs
  func generateConsumer(
    _ opts: MatchingOptions
  ) throws -> MEProgram.ConsumeFunction {
    let consume = consumeFunction(for: opts)

    // Note if you implement support for any of the below, you need to adjust
    // the switch in Sema.swift to not have it be diagnosed as unsupported
    // (potentially guarded on deployment version).
    switch self {
    case .asciiHexDigit:
      return consume(propertyScalarPredicate {
        $0.isHexDigit && $0.isASCIIHexDigit
      })
    case .alphabetic:
      return consume(propertyScalarPredicate(\.isAlphabetic))
    case .bidiControl:
      return consume(propertyScalarPredicate(\.isBidiControl))
    case .bidiMirrored:
      return consume(propertyScalarPredicate(\.isBidiMirrored))
    case .cased:
      return consume(propertyScalarPredicate(\.isCased))
    case .compositionExclusion:
      break
    case .caseIgnorable:
      return consume(propertyScalarPredicate(\.isCaseIgnorable))
    case .changesWhenCasefolded:
      return consume(propertyScalarPredicate(\.changesWhenCaseFolded))
    case .changesWhenCasemapped:
      return consume(propertyScalarPredicate(\.changesWhenCaseMapped))
    case .changesWhenNFKCCasefolded:
      return consume(propertyScalarPredicate(\.changesWhenNFKCCaseFolded))
    case .changesWhenLowercased:
      return consume(propertyScalarPredicate(\.changesWhenLowercased))
    case .changesWhenTitlecased:
      return consume(propertyScalarPredicate(\.changesWhenTitlecased))
    case .changesWhenUppercased:
      return consume(propertyScalarPredicate(\.changesWhenUppercased))
    case .dash:
      return consume(propertyScalarPredicate(\.isDash))
    case .deprecated:
      return consume(propertyScalarPredicate(\.isDeprecated))
    case .defaultIgnorableCodePoint:
      return consume(propertyScalarPredicate(\.isDefaultIgnorableCodePoint))
    case .diacratic: // spelling?
      return consume(propertyScalarPredicate(\.isDiacritic))
    case .emojiModifierBase:
      if #available(macOS 10.12.2, iOS 10.2, tvOS 10.1, watchOS 3.1.1, *) {
        return consume(propertyScalarPredicate(\.isEmojiModifierBase))
      } else {
        throw Unsupported(
          "isEmojiModifierBase on old OSes")
      }
    case .emojiComponent:
      break
    case .emojiModifier:
      if #available(macOS 10.12.2, iOS 10.2, tvOS 10.1, watchOS 3.1.1, *) {
        return consume(propertyScalarPredicate(\.isEmojiModifier))
      } else {
        throw Unsupported("isEmojiModifier on old OSes")
      }
    case .emoji:
      if #available(macOS 10.12.2, iOS 10.2, tvOS 10.1, watchOS 3.1.1, *) {
        return consume(propertyScalarPredicate(\.isEmoji))
      } else {
        throw Unsupported("isEmoji on old OSes")
      }
    case .emojiPresentation:
      if #available(macOS 10.12.2, iOS 10.2, tvOS 10.1, watchOS 3.1.1, *) {
        return consume(propertyScalarPredicate(\.isEmojiPresentation))
      } else {
        throw Unsupported(
          "isEmojiPresentation on old OSes")
      }
    case .extender:
      return consume(propertyScalarPredicate(\.isExtender))
    case .extendedPictographic:
      break // NOTE: Stdlib has this data internally
    case .fullCompositionExclusion:
      return consume(propertyScalarPredicate(\.isFullCompositionExclusion))
    case .graphemeBase:
      return consume(propertyScalarPredicate(\.isGraphemeBase))
    case .graphemeExtended:
      return consume(propertyScalarPredicate(\.isGraphemeExtend))
    case .graphemeLink:
      break
    case .hexDigit:
      return consume(propertyScalarPredicate(\.isHexDigit))
    case .hyphen:
      break
    case .idContinue:
      return consume(propertyScalarPredicate(\.isIDContinue))
    case .ideographic:
      return consume(propertyScalarPredicate(\.isIdeographic))
    case .idStart:
      return consume(propertyScalarPredicate(\.isIDStart))
    case .idsBinaryOperator:
      return consume(propertyScalarPredicate(\.isIDSBinaryOperator))
    case .idsTrinaryOperator:
      return consume(propertyScalarPredicate(\.isIDSTrinaryOperator))
    case .joinControl:
      return consume(propertyScalarPredicate(\.isJoinControl))
    case .logicalOrderException:
      return consume(propertyScalarPredicate(\.isLogicalOrderException))
    case .lowercase:
      return consume(propertyScalarPredicate(\.isLowercase))
    case .math:
      return consume(propertyScalarPredicate(\.isMath))
    case .noncharacterCodePoint:
      return consume(propertyScalarPredicate(\.isNoncharacterCodePoint))
    case .otherAlphabetic:
      break
    case .otherDefaultIgnorableCodePoint:
      break
    case .otherGraphemeExtended:
      break
    case .otherIDContinue:
      break
    case .otherIDStart:
      break
    case .otherLowercase:
      break
    case .otherMath:
      break
    case .otherUppercase:
      break
    case .patternSyntax:
      return consume(propertyScalarPredicate(\.isPatternSyntax))
    case .patternWhitespace:
      return consume(propertyScalarPredicate(\.isPatternWhitespace))
    case .prependedConcatenationMark:
      break
    case .quotationMark:
      return consume(propertyScalarPredicate(\.isQuotationMark))
    case .radical:
      return consume(propertyScalarPredicate(\.isRadical))
    case .regionalIndicator:
      return consume { s in
        (0x1F1E6...0x1F1FF).contains(s.value)
      }
    case .softDotted:
      return consume(propertyScalarPredicate(\.isSoftDotted))
    case .sentenceTerminal:
      return consume(propertyScalarPredicate(\.isSentenceTerminal))
    case .terminalPunctuation:
      return consume(propertyScalarPredicate(\.isTerminalPunctuation))
    case .unifiedIdiograph: // spelling?
      return consume(propertyScalarPredicate(\.isUnifiedIdeograph))
    case .uppercase:
      return consume(propertyScalarPredicate(\.isUppercase))
    case .variationSelector:
      return consume(propertyScalarPredicate(\.isVariationSelector))
    case .whitespace:
      return consume(propertyScalarPredicate(\.isWhitespace))
    case .xidContinue:
      return consume(propertyScalarPredicate(\.isXIDContinue))
    case .xidStart:
      return consume(propertyScalarPredicate(\.isXIDStart))
    case .expandsOnNFC, .expandsOnNFD, .expandsOnNFKD,
        .expandsOnNFKC:
      throw Unsupported("Unicode-deprecated: \(self)")
    }

    throw Unsupported("TODO: map prop \(self)")
  }
}

extension Unicode.POSIXProperty {
  // FIXME: Semantic level, vet for precise defs
  func generateConsumer(
    _ opts: MatchingOptions
  ) -> MEProgram.ConsumeFunction {
    let consume = consumeFunction(for: opts)

    // FIXME: modes, etc
    switch self {
    case .alnum:
      return consume(propertyScalarPredicate {
        $0.isAlphabetic || $0.numericType != nil
      })
    case .blank:
      return consume { s in
        s.properties.generalCategory == .spaceSeparator ||
        s == "\t"
      }

    case .graph:
      return consume(propertyScalarPredicate { p in
        !(
          p.isWhitespace ||
          p.generalCategory == .control ||
          p.generalCategory == .surrogate ||
          p.generalCategory == .unassigned
        )
      })
    case .print:
      return consume(propertyScalarPredicate { p in
        // FIXME: better def
        p.generalCategory != .control
      })
    case .word:
      return consume(propertyScalarPredicate { p in
        // FIXME: better def
        p.isAlphabetic || p.numericType != nil
        || p.isJoinControl
        || p.isDash// marks and connectors...
      })

    case .xdigit:
      return consume(propertyScalarPredicate(\.isHexDigit)) // or number

    }
  }
}

extension Unicode.ExtendedGeneralCategory {
  // FIXME: Semantic level
  func generateConsumer(
    _ opts: MatchingOptions
  ) throws -> MEProgram.ConsumeFunction {
    let consume = consumeFunction(for: opts)

    switch self {
    case .letter:
      return consume(categoriesScalarPredicate([
        .uppercaseLetter, .lowercaseLetter,
        .titlecaseLetter, .modifierLetter,
        .otherLetter
      ]))

    case .mark:
      return consume(categoriesScalarPredicate([
        .nonspacingMark, .spacingMark, .enclosingMark
      ]))

    case .number:
      return consume(categoriesScalarPredicate([
        .decimalNumber, .letterNumber, .otherNumber
      ]))

    case .symbol:
      return consume(categoriesScalarPredicate([
        .mathSymbol, .currencySymbol, .modifierSymbol,
        .otherSymbol
      ]))

    case .punctuation:
      return consume(categoriesScalarPredicate([
        .connectorPunctuation, .dashPunctuation,
        .openPunctuation, .closePunctuation,
        .initialPunctuation, .finalPunctuation,
        .otherPunctuation
      ]))

    case .separator:
      return consume(categoriesScalarPredicate([
        .spaceSeparator, .lineSeparator, .paragraphSeparator
      ]))

    case .other:
      return consume(categoriesScalarPredicate([
        .control, .format, .surrogate, .privateUse, .unassigned
      ]))

    case .casedLetter:
      return consume(categoriesScalarPredicate([
        .uppercaseLetter, .lowercaseLetter, .titlecaseLetter
      ]))

    case .control:
      return consume(categoryScalarPredicate(.control))
    case .format:
      return consume(categoryScalarPredicate(.format))
    case .unassigned:
      return consume(categoryScalarPredicate(.unassigned))
    case .privateUse:
      return consume(categoryScalarPredicate(.privateUse))
    case .surrogate:
      return consume(categoryScalarPredicate(.surrogate))
    case .lowercaseLetter:
      return consume(categoryScalarPredicate(.lowercaseLetter))
    case .modifierLetter:
      return consume(categoryScalarPredicate(.modifierLetter))
    case .otherLetter:
      return consume(categoryScalarPredicate(.otherLetter))
    case .titlecaseLetter:
      return consume(categoryScalarPredicate(.titlecaseLetter))
    case .uppercaseLetter:
      return consume(categoryScalarPredicate(.uppercaseLetter))
    case .spacingMark:
      return consume(categoryScalarPredicate(.spacingMark))
    case .enclosingMark:
      return consume(categoryScalarPredicate(.enclosingMark))
    case .nonspacingMark:
      return consume(categoryScalarPredicate(.nonspacingMark))
    case .decimalNumber:
      return consume(categoryScalarPredicate(.decimalNumber))
    case .letterNumber:
      return consume(categoryScalarPredicate(.letterNumber))
    case .otherNumber:
      return consume(categoryScalarPredicate(.otherNumber))
    case .connectorPunctuation:
      return consume(categoryScalarPredicate(.connectorPunctuation))
    case .dashPunctuation:
      return consume(categoryScalarPredicate(.dashPunctuation))
    case .closePunctuation:
      return consume(categoryScalarPredicate(.closePunctuation))
    case .finalPunctuation:
      return consume(categoryScalarPredicate(.finalPunctuation))
    case .initialPunctuation:
      return consume(categoryScalarPredicate(.initialPunctuation))
    case .otherPunctuation:
      return consume(categoryScalarPredicate(.otherPunctuation))
    case .openPunctuation:
      return consume(categoryScalarPredicate(.openPunctuation))
    case .currencySymbol:
      return consume(categoryScalarPredicate(.currencySymbol))
    case .modifierSymbol:
      return consume(categoryScalarPredicate(.modifierSymbol))
    case .mathSymbol:
      return consume(categoryScalarPredicate(.mathSymbol))
    case .otherSymbol:
      return consume(categoryScalarPredicate(.otherSymbol))
    case .lineSeparator:
      return consume(categoryScalarPredicate(.lineSeparator))
    case .paragraphSeparator:
      return consume(categoryScalarPredicate(.paragraphSeparator))
    case .spaceSeparator:
      return consume(categoryScalarPredicate(.spaceSeparator))
    }
  }
}
