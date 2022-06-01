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

@testable import _RegexParser

import XCTest
@testable import _StringProcessing

enum Transaction: String {
  case credit
  case debit
}

extension RegexTests {
  func testMapOutput() throws {
    let regex0: Regex<(Substring, Substring)> = try Regex(#"Transaction: (credit|debit)"#)
    let string0 = "Transaction: credit"
    
    let regex1 = regex0.mapOutput {
      ($0, transaction: Transaction(rawValue: String($1)))
    }
    
    let match0 = try XCTUnwrap(string0.firstMatch(of: regex1)?.output)
    XCTAssertTrue(match0 == ("Transaction: credit", .credit))
    
    let regex2 = regex1.mapOutput {
      $1
    }
    
    let match1 = try XCTUnwrap(string0.firstMatch(of: regex2)?.output)
    XCTAssertEqual(match1, .credit)
    
    let regex3: Regex<Substring> = try Regex(#"Hello"#)
    let string1 = "Hello"
    
    let regex4 = regex3.mapOutput {
      "\($0) world!"[...]
    }
    
    let match2 = try XCTUnwrap(string1.firstMatch(of: regex4)?.output)
    XCTAssertEqual(match2, "Hello world!")
  }
}
