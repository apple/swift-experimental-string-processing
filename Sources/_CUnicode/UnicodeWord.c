//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

#include "Common/WordData.h"
#include "include/UnicodeData.h"

SWIFT_CC
uint8_t _swift_stdlib_getWordBreakProperty(uint32_t scalar) {
  int low = 0;
  int high = 1086 - 1;
  
  while (high >= low) {
    int idx = low + (high - low) / 2;
    
    const uint64_t entry = _swift_stdlib_words[idx];
    
    // Shift the enum and range count out of the value.
    uint32_t lower = (entry << 43) >> 43;
    
    // Shift the enum out first, then shift out the scalar value.
    uint32_t upper = ((entry >> 21) << 43) >> 43;
    
    // Shift everything out.
    uint8_t enumValue = (uint8_t)(entry >> 42);
    
    if (scalar >= lower && scalar <= upper) {
      return enumValue;
    }
    
    if (scalar > upper) {
      low = idx + 1;
      continue;
    }
    
    if (scalar < lower) {
      high = idx - 1;
      continue;
    }
  }
  
  // If we made it out here, then our scalar was not found in the grapheme
  // array (this occurs when a scalar doesn't map to any grapheme break
  // property). Return the max value here to indicate .any.
  return 0xFF;
}
