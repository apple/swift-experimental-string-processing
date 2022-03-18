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

import _MatchingEngine

extension DSLTree.Node {
  /// Attempt to generate a consumer from this AST node
  ///
  /// A consumer is a Swift closure that matches against
  /// the front of an input range
  func generateConsumer(
    _ opts: MatchingOptions
  ) throws -> MEProgram<String>.ConsumeFunction? {
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

    case .alternation, .conditional, .concatenation, .group,
        .quantification, .trivia, .empty,
        .groupTransform, .absentFunction: return nil

    case .consumer:
      fatalError("FIXME: Is this where we handle them?")
    case .matcher:
      fatalError("FIXME: Is this where we handle them?")
    case .characterPredicate:
      fatalError("FIXME: Is this where we handle them?")
    }
  }
}

extension DSLTree.Atom {
  // TODO: If ByteCodeGen switches first, then this is unnecessary for
  // top-level nodes, but it's also invoked for `.atom` members of a custom CC
  func generateConsumer(
    _ opts: MatchingOptions
  ) throws -> MEProgram<String>.ConsumeFunction? {
    let isCaseInsensitive = opts.isCaseInsensitive
    
    switch self {
    case let .char(c):
      // TODO: Match level?
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

    case .subpattern:
      // TODO: Should we handle?
      return nil

    case .symbolicReference:
      // TODO: Should we handle?
      return nil

    case let .unconverted(a):
      return try a.generateConsumer(opts)
    }

  }
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

  func generateConsumer(
    _ opts: MatchingOptions
  ) throws -> MEProgram<String>.ConsumeFunction? {
    // TODO: Wean ourselves off of this type...
    if let cc = self.characterClass?.withMatchLevel(
      opts.matchLevel
    ) {
      return { input, bounds in
        // FIXME: should we worry about out of bounds?
        cc.matches(in: input, at: bounds.lowerBound)
      }
    }

    switch kind {
    case let .scalar(s):
      assertionFailure(
        "Should have been handled by tree conversion")
      return consumeScalar { $0 == s }

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
      return consumeScalarProp {
        // TODO: alias? casing?
        $0.name == name || $0.nameAlias == name
      }
      
    case .any:
      assertionFailure(
        "Should have been handled by tree conversion")
      fatalError(".atom(.any) is handled in emitAny")

    case .startOfLine, .endOfLine:
      // handled in emitAssertion
      return nil

    case .escaped, .keyboardControl, .keyboardMeta, .keyboardMetaControl,
      .backreference, .subpattern, .callout, .backtrackingDirective:
      // FIXME: implement
      return nil
    }
  }
}

extension DSLTree.CustomCharacterClass.Member {
  func generateConsumer(
    _ opts: MatchingOptions
  ) throws -> MEProgram<String>.ConsumeFunction {
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
          guard s.lowercased().contains(input[bounds.lowerBound].lowercased()) else {
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
      return { _, bounds in
        return bounds.lowerBound
      }
    }

  }
}

extension AST.CustomCharacterClass.Member {
  func generateConsumer(
    _ opts: MatchingOptions
  ) throws -> MEProgram<String>.ConsumeFunction {
    switch self {
    case .custom(let ccc):
      return try ccc.generateConsumer(opts)

    case .range(let r):
      guard let lhs = r.lhs.literalCharacterValue else {
        throw Unsupported("\(r.lhs) in range")
      }
      guard let rhs = r.rhs.literalCharacterValue else {
        throw Unsupported("\(r.rhs) in range")
      }

      return { input, bounds in
        // TODO: check for out of bounds?
        let curIdx = bounds.lowerBound
        if (lhs...rhs).contains(input[curIdx]) {
          // TODO: semantic level
          return input.index(after: curIdx)
        }
        return nil
      }

    case .atom(let atom):
      guard let gen = try atom.generateConsumer(opts) else {
        throw Unsupported("TODO")
      }
      return gen

    case .quote(let q):
      // TODO: Not optimal.
      let consumers = try q.literal.map {
        try AST.Atom(.char($0), .fake).generateConsumer(opts)!
      }
      return { input, bounds in
        for consumer in consumers {
          if let idx = consumer(input, bounds) {
            return idx
          }
        }
        return nil
      }

    case .trivia:
      throw Unreachable(
        "Should have been stripped by caller")

    case .setOperation(let lhs, let op, let rhs):
      // TODO: We should probably have a component type
      // instead of a members array... for now we reconstruct
      // an AST node...
      let start = AST.Located(
        faking: AST.CustomCharacterClass.Start.normal)

      let lhs = try AST.CustomCharacterClass(
        start, lhs, .fake
      ).generateConsumer(opts)
      let rhs = try AST.CustomCharacterClass(
        start, rhs, .fake
      ).generateConsumer(opts)

      return { input, bounds in
        // NOTE: Easy way to implement, not performant
        let lhsIdxOpt = lhs(input, bounds)
        let rhsIdxOpt = rhs(input, bounds)

        // TODO: What if lengths don't line up?
        assert(lhsIdxOpt == rhsIdxOpt || lhsIdxOpt == nil
               || rhsIdxOpt == nil)

        switch op.value {
        case .subtraction:
          guard rhsIdxOpt == nil else { return nil }
          return lhsIdxOpt

        case .intersection:
          if let idx = lhsIdxOpt {
            return rhsIdxOpt == nil ? nil : idx
          }
          return nil

        case .symmetricDifference:
          if let idx = lhsIdxOpt {
            return rhsIdxOpt == nil ? idx : nil
          }
          return rhsIdxOpt
        }
      }
    }
  }
}

extension DSLTree.CustomCharacterClass {
  func generateConsumer(
    _ opts: MatchingOptions
  ) throws -> MEProgram<String>.ConsumeFunction {
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
        // FIXME: semantic level
        return input.index(after: bounds.lowerBound)
      }
      return nil
    }
  }
}

extension AST.CustomCharacterClass {
  func generateConsumer(
    _ opts: MatchingOptions
  ) throws -> MEProgram<String>.ConsumeFunction {
    // NOTE: Easy way to implement, obviously not performant
    let consumers = try strippingTriviaShallow.members.map {
      try $0.generateConsumer(opts)
    }
    return { input, bounds in
      for consumer in consumers {
        if let idx = consumer(input, bounds) {
          return isInverted ? nil : idx
        }
      }
      if isInverted {
        // FIXME: semantic level
        return input.index(after: bounds.lowerBound)
      }
      return nil
    }
  }
}

// NOTE: Conveniences, though not most performant
private func consumeScalarScript(
  _ s: Unicode.Script
) -> MEProgram<String>.ConsumeFunction {
  consumeScalar {
    Unicode.Script($0) == s
  }
}
private func consumeScalarScriptExtension(
  _ s: Unicode.Script
) -> MEProgram<String>.ConsumeFunction {
  consumeScalar {
    let extensions = Unicode.Script.extensions(for: $0)
    return extensions.contains(s)
  }
}
private func consumeScalarGC(
  _ gc: Unicode.GeneralCategory
) -> MEProgram<String>.ConsumeFunction {
  consumeScalar { gc == $0.properties.generalCategory }
}
private func consumeScalarGCs(
  _ gcs: [Unicode.GeneralCategory]
) -> MEProgram<String>.ConsumeFunction {
  consumeScalar { gcs.contains($0.properties.generalCategory) }
}
private func consumeScalarProp(
  _ p: @escaping (Unicode.Scalar.Properties) -> Bool
) -> MEProgram<String>.ConsumeFunction {
  consumeScalar { p($0.properties) }
}
func consumeScalar(
  _ p: @escaping (Unicode.Scalar) -> Bool
) -> MEProgram<String>.ConsumeFunction {
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

extension AST.Atom.CharacterProperty {
  func generateConsumer(
    _ opts: MatchingOptions
  ) throws -> MEProgram<String>.ConsumeFunction {
    // Handle inversion for us, albeit not efficiently
    func invert(
      _ p: @escaping MEProgram<String>.ConsumeFunction
    ) -> MEProgram<String>.ConsumeFunction {
      return { input, bounds in
        if p(input, bounds) != nil { return nil }
        // TODO: semantic level
        // TODO: bounds check
        return input.unicodeScalars.index(
          after: bounds.lowerBound)
      }
    }

    // FIXME: Below is largely scalar based, for convenience,
    // but we want a comprehensive treatment to semantic mode
    // switching.
    let preInversion: MEProgram<String>.ConsumeFunction =
    try {
      switch kind {
        // TODO: is this modeled differently?
      case .any:
        return { input, bounds in
          // TODO: bounds check?
          return input.index(after: bounds.lowerBound)
        }
      case .assigned:
        return consumeScalar {
          $0.properties.generalCategory != .unassigned
        }
      case .ascii:
        return consumeScalar(\.isASCII)

      case .generalCategory(let p):
        return try p.generateConsumer(opts)
//        fatalError("TODO: Map categories: \(p)")

      case .binary(let prop, value: let value):
        let cons = try prop.generateConsumer(opts)
        return value ? cons : invert(cons)

      case .script(let s):
        return consumeScalarScript(s)

      case .scriptExtension(let s):
        return consumeScalarScriptExtension(s)

      case .posix(let p):
        return p.generateConsumer(opts)

      case .pcreSpecial(let s):
        throw Unsupported("TODO: map PCRE special: \(s)")

      case .onigurumaSpecial(let s):
        throw Unsupported("TODO: map Oniguruma special: \(s)")

      case let .other(key, value):
        throw Unsupported(
          "TODO: map other \(key ?? "")=\(value)")
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
  ) throws -> MEProgram<String>.ConsumeFunction {
    switch self {

    case .asciiHexDigit:
      return consumeScalarProp {
        $0.isHexDigit && $0.isASCIIHexDigit
      }
    case .alphabetic:
      return consumeScalarProp(\.isAlphabetic)
    case .bidiControl:
      break


    case .bidiMirrored: 
      return consumeScalarProp(\.isBidiMirrored)
    case .cased:
      return consumeScalarProp(\.isCased)
    case .compositionExclusion:
      break
    case .caseIgnorable:
      return consumeScalarProp(\.isCaseIgnorable)
    case .changesWhenCasefolded:
      return consumeScalarProp(\.changesWhenCaseFolded)
    case .changesWhenCasemapped:
      return consumeScalarProp(\.changesWhenCaseMapped)
    case .changesWhenNFKCCasefolded:
      return consumeScalarProp(\.changesWhenNFKCCaseFolded)
    case .changesWhenLowercased:
      return consumeScalarProp(\.changesWhenLowercased)
    case .changesWhenTitlecased:
      return consumeScalarProp(\.changesWhenTitlecased)
    case .changesWhenUppercased:
      return consumeScalarProp(\.changesWhenUppercased)
    case .dash:
      return consumeScalarProp(\.isDash)
    case .deprecated:
      return consumeScalarProp(\.isDeprecated)
    case .defaultIgnorableCodePoint:
      return consumeScalarProp(\.isDefaultIgnorableCodePoint)
    case .diacratic: // spelling?
      return consumeScalarProp(\.isDiacritic)
    case .emojiModifierBase:
      if #available(macOS 10.12.2, iOS 10.2, tvOS 10.1, watchOS 3.1.1, *) {
        return consumeScalarProp(\.isEmojiModifierBase)
      } else {
        throw Unsupported(
          "isEmojiModifierBase on old OSes")
      }
    case .emojiComponent:
      break
    case .emojiModifier:
      if #available(macOS 10.12.2, iOS 10.2, tvOS 10.1, watchOS 3.1.1, *) {
        return consumeScalarProp(\.isEmojiModifier)
      } else {
        throw Unsupported("isEmojiModifier on old OSes")
      }
    case .emoji:
      if #available(macOS 10.12.2, iOS 10.2, tvOS 10.1, watchOS 3.1.1, *) {
        return consumeScalarProp(\.isEmoji)
      } else {
        throw Unsupported("isEmoji on old OSes")
      }
    case .emojiPresentation:
      if #available(macOS 10.12.2, iOS 10.2, tvOS 10.1, watchOS 3.1.1, *) {
        return consumeScalarProp(\.isEmojiPresentation)
      } else {
        throw Unsupported(
          "isEmojiPresentation on old OSes")
      }
    case .extender:
      return consumeScalarProp(\.isExtender)
    case .extendedPictographic:
      break // NOTE: Stdlib has this data internally
    case .fullCompositionExclusion:
      return consumeScalarProp(\.isFullCompositionExclusion)
    case .graphemeBase:
      return consumeScalarProp(\.isGraphemeBase)
    case .graphemeExtended:
      return consumeScalarProp(\.isGraphemeExtend)
    case .graphemeLink:
      break
    case .hexDigit:
      return consumeScalarProp(\.isHexDigit)
    case .hyphen:
      break
    case .idContinue:
      return consumeScalarProp(\.isIDContinue)
    case .ideographic:
      return consumeScalarProp(\.isIdeographic)
    case .idStart:
      return consumeScalarProp(\.isIDStart)
    case .idsBinaryOperator:
      return consumeScalarProp(\.isIDSBinaryOperator)
    case .idsTrinaryOperator:
      return consumeScalarProp(\.isIDSTrinaryOperator)
    case .joinControl:
      return consumeScalarProp(\.isJoinControl)
    case .logicalOrderException:
      return consumeScalarProp(\.isLogicalOrderException)
    case .lowercase:
      return consumeScalarProp(\.isLowercase)
    case .math:
      return consumeScalarProp(\.isMath)
    case .noncharacterCodePoint:
      return consumeScalarProp(\.isNoncharacterCodePoint)
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
      return consumeScalarProp(\.isPatternSyntax)
    case .patternWhitespace:
      return consumeScalarProp(\.isPatternWhitespace)
    case .prependedConcatenationMark:
      break
    case .quotationMark:
      return consumeScalarProp(\.isQuotationMark)
    case .radical:
      return consumeScalarProp(\.isRadical)
    case .regionalIndicator:
      return consumeScalar { s in
        (0x1F1E6...0x1F1FF).contains(s.value)
      }
    case .softDotted:
      return consumeScalarProp(\.isSoftDotted)
    case .sentenceTerminal:
      return consumeScalarProp(\.isSentenceTerminal)
    case .terminalPunctuation:
      return consumeScalarProp(\.isTerminalPunctuation)
    case .unifiedIdiograph: // spelling?
      return consumeScalarProp(\.isUnifiedIdeograph)
    case .uppercase:
      return consumeScalarProp(\.isUppercase)
    case .variationSelector:
      return consumeScalarProp(\.isVariationSelector)
    case .whitespace:
      return consumeScalarProp(\.isWhitespace)
    case .xidContinue:
      return consumeScalarProp(\.isXIDContinue)
    case .xidStart:
      return consumeScalarProp(\.isXIDStart)
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
  ) -> MEProgram<String>.ConsumeFunction {
    // FIXME: semantic levels, modes, etc
    switch self {
    case .alnum:
      return consumeScalarProp {
        $0.isAlphabetic || $0.numericType != nil
      }
    case .blank:
      return consumeScalar { s in
        s.properties.generalCategory == .spaceSeparator ||
        s == "\t"
      }

    case .graph:
      return consumeScalarProp { p in
        !(
          p.isWhitespace ||
          p.generalCategory == .control ||
          p.generalCategory == .surrogate ||
          p.generalCategory == .unassigned
        )
      }
    case .print:
      return consumeScalarProp { p in
        // FIXME: better def
        p.generalCategory != .control
      }
    case .word:
      return consumeScalarProp { p in
        // FIXME: better def
        p.isAlphabetic || p.numericType != nil
        || p.isJoinControl
        || p.isDash// marks and connectors...
      }

    case .xdigit:
      return consumeScalarProp(\.isHexDigit) // or number

    }
  }
}

extension Unicode.ExtendedGeneralCategory {
  // FIXME: Semantic level
  func generateConsumer(
    _ opts: MatchingOptions
  ) throws -> MEProgram<String>.ConsumeFunction {
    switch self {
    case .letter:
      return consumeScalarGCs([
        .uppercaseLetter, .lowercaseLetter,
        .titlecaseLetter, .modifierLetter,
        .otherLetter
      ])

    case .mark:
      return consumeScalarGCs([
        .nonspacingMark, .spacingMark, .enclosingMark
      ])

    case .number:
      return consumeScalarGCs([
        .decimalNumber, .letterNumber, .otherNumber
      ])

    case .symbol:
      return consumeScalarGCs([
        .mathSymbol, .currencySymbol, .modifierSymbol,
        .otherSymbol
      ])

    case .punctuation:
      return consumeScalarGCs([
        .connectorPunctuation, .dashPunctuation,
        .openPunctuation, .closePunctuation,
        .initialPunctuation, .finalPunctuation,
        .otherPunctuation
      ])

    case .separator:
      return consumeScalarGCs([
        .spaceSeparator, .lineSeparator, .paragraphSeparator
      ])

    case .other:
      return consumeScalarGCs([
        .control, .format, .surrogate, .privateUse, .unassigned
      ])

    case .casedLetter:
      throw Unsupported(
        "TODO: cased letter? not the property?")

    case .control:
      return consumeScalarGC(.control)
    case .format:
      return consumeScalarGC(.format)
    case .unassigned:
      return consumeScalarGC(.unassigned)
    case .privateUse:
      return consumeScalarGC(.privateUse)
    case .surrogate:
      return consumeScalarGC(.surrogate)
    case .lowercaseLetter:
      return consumeScalarGC(.lowercaseLetter)
    case .modifierLetter:
      return consumeScalarGC(.modifierLetter)
    case .otherLetter:
      return consumeScalarGC(.otherLetter)
    case .titlecaseLetter:
      return consumeScalarGC(.titlecaseLetter)
    case .uppercaseLetter:
      return consumeScalarGC(.uppercaseLetter)
    case .spacingMark:
      return consumeScalarGC(.spacingMark)
    case .enclosingMark:
      return consumeScalarGC(.enclosingMark)
    case .nonspacingMark:
      return consumeScalarGC(.nonspacingMark)
    case .decimalNumber:
      return consumeScalarGC(.decimalNumber)
    case .letterNumber:
      return consumeScalarGC(.letterNumber)
    case .otherNumber:
      return consumeScalarGC(.otherNumber)
    case .connectorPunctuation:
      return consumeScalarGC(.connectorPunctuation)
    case .dashPunctuation:
      return consumeScalarGC(.dashPunctuation)
    case .closePunctuation:
      return consumeScalarGC(.closePunctuation)
    case .finalPunctuation:
      return consumeScalarGC(.finalPunctuation)
    case .initialPunctuation:
      return consumeScalarGC(.initialPunctuation)
    case .otherPunctuation:
      return consumeScalarGC(.otherPunctuation)
    case .openPunctuation:
      return consumeScalarGC(.openPunctuation)
    case .currencySymbol:
      return consumeScalarGC(.currencySymbol)
    case .modifierSymbol:
      return consumeScalarGC(.modifierSymbol)
    case .mathSymbol:
      return consumeScalarGC(.mathSymbol)
    case .otherSymbol:
      return consumeScalarGC(.otherSymbol)
    case .lineSeparator:
      return consumeScalarGC(.lineSeparator)
    case .paragraphSeparator:
      return consumeScalarGC(.paragraphSeparator)
    case .spaceSeparator:
      return consumeScalarGC(.spaceSeparator)
    }
  }
}
