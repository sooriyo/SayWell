import Foundation

/// Detects obviously non-Singlish input (gibberish) to avoid wasting API calls.
enum GibberishDetection {
  /// Check if input looks like gibberish (returns true = reject).
  static func isLikelyGibberish(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count >= 3 else { return false }

    let tokens = trimmed.split(separator: " ").map(String.init)

    // Single token: strict checks
    if tokens.count == 1 {
      return isSingleTokenGibberish(tokens[0])
    }

    // Multi-token: allow if at least one token looks legit
    let gibberishCount = tokens.filter { isSingleTokenGibberish($0) }.count
    let reasonableTokens = tokens.count - gibberishCount
    return reasonableTokens == 0
  }

  private static func isSingleTokenGibberish(_ token: String) -> Bool {
    // Punctuation only is valid
    if token.allSatisfy({ !$0.isLetter && !$0.isNumber }) { return false }

    // Short tokens are hard to judge
    if token.count <= 3 { return false }

    // Check character patterns
    return hasExcessiveRepetition(token) || hasLongConsonantRun(token)
  }

  /// Reject if one char is >60% of the token. Only check 6+ char tokens.
  private static func hasExcessiveRepetition(_ token: String) -> Bool {
    guard token.count >= 6 else { return false }
    let lower = token.lowercased()
    var charCounts: [Character: Int] = [:]
    for char in lower {
      charCounts[char, default: 0] += 1
    }
    let maxCount = charCounts.values.max() ?? 0
    return Double(maxCount) / Double(lower.count) > 0.6
  }

  /// Reject if 5+ consonants in a row without a vowel (e.g., "bcdfg").
  private static func hasLongConsonantRun(_ token: String) -> Bool {
    let vowels = CharacterSet(charactersIn: "aeiouAEIOU")
    let letters = CharacterSet.letters
    var consonantRun = 0

    for char in token.lowercased() {
      let scalar = UnicodeScalar(String(char))!
      if vowels.contains(scalar) {
        consonantRun = 0
      } else if letters.contains(scalar) {
        consonantRun += 1
        if consonantRun >= 5 {
          return true
        }
      }
    }
    return false
  }
}
