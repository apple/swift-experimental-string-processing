
// TODO: mock up multi-line soon

enum Delimiter: Hashable, CaseIterable {
  case regular
  case modern

  var openingAndClosing: (opening: String, closing: String) {
    switch self {
    case .regular: return ("'/", "/'")
    case .modern: return ("'|", "|'")
    }
  }
  var opening: String { openingAndClosing.opening }
  var closing: String { openingAndClosing.closing }

  /// The default set of syntax options that the delimiter indicates.
  var defaultSyntaxOptions: SyntaxOptions {
    switch self {
    case .regular: return .traditional
    case .modern: return .modern
    }
  }
}

struct LexError: Error, CustomStringConvertible {
  enum Kind: Hashable {
    case endOfString
    case invalidUTF8 // TODO: better range reporting
    case unknownDelimiter
  }

  var kind: Kind

  /// The pointer at which to resume lexing.
  var resumePtr: UnsafeRawPointer

  init(_ kind: Kind, resumeAt resumePtr: UnsafeRawPointer) {
    self.kind = kind
    self.resumePtr = resumePtr
  }

  var description: String {
    switch kind {
    case .endOfString: return "unterminated regex literal"
    case .invalidUTF8: return "invalid UTF-8 found in source file"
    case .unknownDelimiter: return "unknown regex literal delimiter"
    }
  }
}

/// Drop a set of regex delimiters from the input string, returning the contents
/// and the delimiter used. The input string must have valid delimiters.
func droppingRegexDelimiters(_ str: String) -> (String, Delimiter) {
  let utf8 = str.utf8
  func stripDelimiter(_ delim: Delimiter) -> String? {
    let prefix = delim.opening.utf8
    let suffix = delim.closing.utf8
    guard utf8.prefix(prefix.count).elementsEqual(prefix),
          utf8.suffix(suffix.count).elementsEqual(suffix) else { return nil }

    return String(utf8.dropFirst(prefix.count).dropLast(suffix.count))
  }
  for d in Delimiter.allCases {
    if let contents = stripDelimiter(d) {
      return (contents, d)
    }
  }
  fatalError("No valid delimiters")
}

/// Attempt to lex a regex literal between `start` and `end`, returning either
/// the contents and pointer from which to resume lexing, or an error.
func lexRegex(
  start: UnsafeRawPointer, end: UnsafeRawPointer
) throws -> (contents: String, Delimiter, end: UnsafeRawPointer) {
  precondition(start <= end)
  var current = start

  func ascii(_ s: Unicode.Scalar) -> UInt8 {
    assert(s.value <= 0x7F)
    return UInt8(truncatingIfNeeded: s.value)
  }
  func load(offset: Int) -> UInt8? {
    guard current + offset < end else { return nil }
    return current.load(fromByteOffset: offset, as: UInt8.self)
  }
  func load() -> UInt8? { load(offset: 0) }
  func advance(_ n: Int = 1) {
    precondition(current + n <= end, "Cannot advance past end")
    current = current.advanced(by: n)
  }

  func tryEat(_ utf8: String.UTF8View) -> Bool {
    for (i, idx) in utf8.indices.enumerated() {
      guard load(offset: i) == utf8[idx] else { return false }
    }
    advance(utf8.count)
    return true
  }

  // Try to lex the opening delimiter.
  guard let delimiter = Delimiter.allCases.first(
    where: { tryEat($0.opening.utf8) }
  ) else {
    throw LexError(.unknownDelimiter, resumeAt: current.successor())
  }

  let contentsStart = current
  while true {
    switch load() {
    case nil, ascii("\n"), ascii("\r"):
      throw LexError(.endOfString, resumeAt: current)

    case ascii("\\"):
      // Skip next byte.
      advance(2)

    default:
      // Try to lex the closing delimiter.
      let contentsEnd = current
      guard tryEat(delimiter.closing.utf8) else {
        advance()
        continue
      }

      // Form a string from the contents and make sure it's valid UTF-8.
      let count = contentsEnd - contentsStart
      let contents = UnsafeRawBufferPointer(
        start: contentsStart, count: count)
      let s = String(decoding: contents, as: UTF8.self)

      guard s.utf8.elementsEqual(contents) else {
        throw LexError(.invalidUTF8, resumeAt: current)
      }
      return (contents: s, delimiter, end: current)
    }
  }
}

private func copyCString(_ str: String) -> UnsafePointer<CChar> {
  let count = str.utf8.count + 1
  return str.withCString {
    assert($0[count-1] == 0)
    let ptr = UnsafeMutablePointer<CChar>.allocate(capacity: count)
    ptr.initialize(from: $0, count: count)
    return UnsafePointer(ptr)
  }
}

/// Interface for libswift.
///
/// Lex a regular expression literal starting at `inputPtr`, making sure not to
/// lex past `bufferEndPtr`. The pointer at which to resume lexing is returned,
/// or nil if this is not a regex literal. The `errOut` parameter will be set
/// if an error is encountered.
func libswiftLexRegexLiteral(
  _ inputPtr: UnsafePointer<CChar>?,
  _ bufferEndPtr: UnsafePointer<CChar>?,
  _ errOut: UnsafeMutablePointer<UnsafePointer<CChar>?>?
) -> UnsafePointer<CChar>? {
  guard let inputPtr = inputPtr, let endPtr = bufferEndPtr else { return nil }
  guard let errOut = errOut else { fatalError("Expected error out param") }

  do {
    let (_, _, endPtr) = try lexRegex(start: inputPtr, end: endPtr)
    return endPtr.assumingMemoryBound(to: CChar.self)
  } catch let error as LexError {
    if error.kind == .unknownDelimiter {
      // An unknown delimiter should be recovered from, as we may want to try
      // lex something else.
      return nil
    }
    errOut.pointee = copyCString("\(error)")
    return error.resumePtr.assumingMemoryBound(to: CChar.self)
  } catch {
    fatalError("Should be a LexError")
  }
}

// The version number for the regex. This gets emitted as an argument to the
// Regex(_regexString:version:) initializer and should be bumped if the format
// of the regex string needs to be changed in such a that requires the runtime
// to updated.
public let currentRegexLiteralFormatVersion: CUnsignedInt = 1

/// Interface for libswift.
///
/// Parse a regex string from `inputPtr`, which should be null-terminated
/// C-string. `errOut` will be set if an error was encountered.
func libswiftParseRegexLiteral(
  _ inputPtr: UnsafePointer<CChar>?,
  _ errOut: UnsafeMutablePointer<UnsafePointer<CChar>?>?,
  _ versionOut: UnsafeMutablePointer<CUnsignedInt>?
) {
  guard let s = inputPtr else { fatalError("Expected input param") }
  guard let errOut = errOut else { fatalError("Expected error out param") }
  guard let versionOut = versionOut else {
    fatalError("Expected version out param")
  }

  versionOut.pointee = currentRegexLiteralFormatVersion

  let str = String(cString: s)
  do {
    let _ = try parseWithDelimiters(str)
  } catch {
    errOut.pointee = copyCString(
      "cannot parse regular expression: \(String(describing: error))")
  }
}
