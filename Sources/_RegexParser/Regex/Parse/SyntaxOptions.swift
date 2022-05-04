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


public struct SyntaxOptions: OptionSet {
  public var rawValue: UInt
  public init(rawValue: UInt) { self.rawValue = rawValue }

  private init(_ rawValue: UInt) {
    self.init(rawValue: rawValue)
  }

  public init() { self.init(0) }

  /// `'a \. b' == '/a\.b/'`
  public static var nonSemanticWhitespace: Self { Self(1 << 0) }

  /// `abc # comment`
  public static var endOfLineComments: Self { Self(1 << 1) }

  /// `(?x)` `(?xx)`
  public static var extendedSyntax: Self {
    [.endOfLineComments, .nonSemanticWhitespace]
  }

  // NOTE: Currently, this means we have raw quotes.
  // Better would be to have real Swift string delimiter parsing logic.

  /// `'a "." b' == '/a\Q.\Eb/'`
  public static var experimentalQuotes: Self { Self(1 << 2) }

  // NOTE: traditional comments are not nested. Currently, we are neither.
  // Traditional comments can't have `)`, not even escaped in them either, we
  // can. Traditional comments can have `*/` in them, we can't without
  // escaping. We don't currently do escaping.

  /// `'a /* comment */ b' == '/a(?#. comment )b/'`
  public static var experimentalComments: Self { Self(1 << 3) }

  /// ```
  /// 'a{n...m}' == '/a{n,m}/'
  /// 'a{n..<m}' == '/a{n,m-1}/'
  /// 'a{n...}'  == '/a{n,}/'
  /// 'a{...m}'  == '/a{,m}/'
  /// 'a{..<m}'  == '/a{,m-1}/'
  /// ```
  public static var experimentalRanges: Self { Self(1 << 4) }

  /// `(name: .*)` == `(?<name>.*)`
  /// `(_: .*)` == `(?:.*)`
  public static var experimentalCaptures: Self { Self(1 << 5) }

  /// The default syntax for a multi-line regex literal.
  public static var multilineExtendedSyntax: Self {
    return [Self(1 << 6), .extendedSyntax]
  }

  /*

    /// `<digit>*` == `[[:digit:]]*` == `\d*`
    public static var experimentalConsumers

  */

  public static var traditional: Self { Self(0) }

  public static var experimental: Self {
    // Experimental syntax enables everything except end-of-line comments.
    Self(~0).subtracting(.endOfLineComments)
  }

  // TODO: Probably want to model strict-PCRE etc. options too.
  // E.g. [abc&&b] is [b] in Oniguruma/UTS18 or [abc&] in PCRE
}


