import Foundation

/// Collapses romanized Singlish spellings into one canonical string (mirrors `backend/src/normalize.ts`).
enum SinglishNormalizer {
    private static var variantLookup: [String: String] = [:]
    private static var canonicalTokens: [String] = []
    private static var dynamicVocabulary: Set<String> = []
    private static var isBootstrapped = false

    private static let bundledVariants: [String: [String]] = {
        guard let url = Bundle.main.url(forResource: "variants", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        var table: [String: [String]] = [:]
        for (key, value) in raw where !key.hasPrefix("_") {
            if let variants = value as? [String] {
                table[key] = variants
            }
        }
        return table
    }()

    private static let punctuationTrimPattern = try? NSRegularExpression(
        pattern: #"^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$"#,
        options: []
    )

    private static let elongationPattern = try? NSRegularExpression(
        pattern: #"(.)\1{2,}"#,
        options: []
    )

    // MARK: - Bootstrap

    static func bootstrap() {
        guard !isBootstrapped else { return }
        isBootstrapped = true
        applyVariants(bundledVariants)
        if let phrases = CommonPhrasesStore.loadLocal()?.phrases {
            rebuildVocabulary(fromPhraseKeys: Array(phrases.keys))
        }
        if let synced = CommonPhrasesStore.loadLocal()?.variants {
            applyVariants(synced)
        }
    }

    /// Replace the variant fold table (from bundle sync or bundled fallback).
    static func applyVariants(_ table: [String: [String]]) {
        var lookup: [String: String] = [:]
        var canonicals: [String] = []

        for (canonical, variants) in table where !canonical.hasPrefix("_") {
            let canon = canonical.lowercased()
            canonicals.append(canon)
            lookup[canon] = canon
            for variant in variants {
                let v = variant.lowercased()
                if lookup[v] == nil {
                    lookup[v] = canon
                }
            }
        }

        variantLookup = lookup
        canonicalTokens = canonicals.sorted()
        dynamicVocabulary.formUnion(canonicals)
    }

    /// Grow fuzzy-match vocabulary from phrase keys and user-learned normalized forms.
    static func rebuildVocabulary(fromPhraseKeys phraseKeys: [String]) {
        var tokens = Set<String>()
        tokens.formUnion(canonicalTokens)

        for phrase in phraseKeys {
            for token in tokenize(phrase) {
                tokens.insert(token)
            }
        }

        dynamicVocabulary = tokens
    }

    static func addVocabulary(from normalizedPhrases: [String]) {
        guard !normalizedPhrases.isEmpty else { return }
        bootstrap()
        for phrase in normalizedPhrases {
            for token in tokenize(phrase) {
                dynamicVocabulary.insert(token)
            }
        }
    }

    // MARK: - Normalize

    static func normalize(_ text: String) -> String {
        bootstrap()
        guard !text.isEmpty else { return "" }

        let cleaned = text
            .precomposedStringWithCompatibilityMapping
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { return "" }

        let endingPunct = trailingPunctuation(in: cleaned)
        let withoutEnding = endingPunct.isEmpty
            ? cleaned
            : String(cleaned.dropLast(endingPunct.count)).trimmingCharacters(in: .whitespacesAndNewlines)

        var tokens: [String] = []
        for rawToken in withoutEnding.split(separator: " ", omittingEmptySubsequences: true) {
            var token = trimPunctuation(String(rawToken))
            guard !token.isEmpty else { continue }
            token = collapseElongation(token)
            tokens.append(
                variantLookup[token]
                    ?? fuzzyCanonicalMatch(token)
                    ?? token
            )
        }

        if !endingPunct.isEmpty {
            tokens.append(endingPunct)
        }

        return tokens.joined(separator: " ")
    }

    /// Resolve the best cache lookup key: personal alias → algorithmic normalize.
    static func cacheKeyPhrase(for typed: String, tone: TranslationTone) -> String {
        bootstrap()
        if let alias = PhraseAliasStore.lookup(typed: typed, tone: tone) {
            return alias
        }
        return normalize(typed)
    }

    // MARK: - Internals

    private static func tokenize(_ phrase: String) -> [String] {
        let ending = trailingPunctuation(in: phrase.lowercased())
        let body = ending.isEmpty ? phrase : String(phrase.dropLast(ending.count))
        return body
            .lowercased()
            .split(separator: " ", omittingEmptySubsequences: true)
            .map { trimPunctuation(String($0)) }
            .filter { !$0.isEmpty }
    }

    private static func trailingPunctuation(in text: String) -> String {
        guard let match = text.range(of: #"[.!?]+$"#, options: .regularExpression) else { return "" }
        return String(text[match])
    }

    private static func trimPunctuation(_ token: String) -> String {
        guard let pattern = punctuationTrimPattern else { return token }
        let range = NSRange(token.startIndex..., in: token)
        return pattern.stringByReplacingMatches(in: token, range: range, withTemplate: "")
    }

    private static func collapseElongation(_ token: String) -> String {
        guard let pattern = elongationPattern else { return token }
        let range = NSRange(token.startIndex..., in: token)
        return pattern.stringByReplacingMatches(in: token, range: range, withTemplate: "$1")
    }

    private static func fuzzyCanonicalMatch(_ token: String) -> String? {
        guard token.count >= 4 else { return nil }

        var match: String?
        let candidates = canonicalTokens + dynamicVocabulary.sorted()
        for canonical in candidates {
            guard abs(canonical.count - token.count) <= 1 else { continue }
            if isEditDistanceOne(token, canonical) {
                if match != nil, match != canonical { return nil }
                match = canonical
            }
        }
        return match
    }

    private static func isEditDistanceOne(_ a: String, _ b: String) -> Bool {
        let aChars = Array(a)
        let bChars = Array(b)
        let la = aChars.count
        let lb = bChars.count
        if abs(la - lb) > 1 { return false }

        if la == lb {
            var diff = 0
            for i in 0..<la {
                if aChars[i] != bChars[i] {
                    diff += 1
                    if diff > 1 { return false }
                }
            }
            return diff == 1
        }

        let (short, long) = la < lb ? (aChars, bChars) : (bChars, aChars)
        var i = 0
        var j = 0
        var diff = 0
        while i < short.count && j < long.count {
            if short[i] == long[j] {
                i += 1
                j += 1
            } else {
                diff += 1
                if diff > 1 { return false }
                j += 1
            }
        }
        return true
    }
}
