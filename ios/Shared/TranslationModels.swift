import Foundation

enum TranslationTone: String, CaseIterable, Codable, Equatable, Identifiable {
    case casual
    case professional
    case chatting

    var id: String { rawValue }

    var label: String {
        switch self {
        case .casual: return "Casual"
        case .professional: return "Professional"
        case .chatting: return "Chatting"
        }
    }

    /// Short label for the keyboard suggestion bar.
    var shortLabel: String {
        switch self {
        case .casual: return "Casual"
        case .professional: return "Pro"
        case .chatting: return "Chat"
        }
    }

    var description: String {
        switch self {
        case .casual:
            return "Natural everyday English"
        case .professional:
            return "Formal and polite for work"
        case .chatting:
            return "Short, text-message style"
        }
    }

    var systemImage: String {
        switch self {
        case .casual: return "text.bubble.fill"
        case .professional: return "briefcase.fill"
        case .chatting: return "message.fill"
        }
    }

    var modeHint: String {
        switch self {
        case .casual: return "Casual mode"
        case .professional: return "Professional mode"
        case .chatting: return "Chat mode"
        }
    }

    var next: TranslationTone {
        let all = Self.allCases
        guard let index = all.firstIndex(of: self) else { return .casual }
        return all[(index + 1) % all.count]
    }
}

struct TranslationRequest: Encodable {
    let text: String
    let tone: String
}

struct TranslationResponse: Codable, Equatable {
    let translation: String
    let source: TranslationSource
    let normalized: String
}

enum TranslationSource: String, Codable, Equatable {
    case inMemoryCache = "in-memory"
    case persistedCache = "disk"
    case commonPhrases = "builtin"
    case geminiAPI = "api"

    var label: String {
        switch self {
        case .inMemoryCache: return "Cached"
        case .persistedCache: return "Saved"
        case .commonPhrases: return "Common"
        case .geminiAPI: return "AI"
        }
    }
}

struct APIErrorResponse: Decodable {
    let error: String
}

enum SayWellError: LocalizedError {
    case emptyInput
    case inputTooLong
    case gibberishInput
    case rateLimited(retryAfter: Int?)
    case translationFailed
    case upstreamTimeout
    case invalidRequest
    case network(underlying: Error)
    case unknown(statusCode: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "Please enter some Singlish text to translate."
        case .inputTooLong:
            return "That text is too long. Try a shorter message."
        case .gibberishInput:
            return "That doesn't look like Singlish. Try typing a real word or phrase."
        case .rateLimited(let retryAfter):
            if let retryAfter {
                return "Too many requests. Try again in \(retryAfter) seconds."
            }
            return "Too many requests. Please wait a moment and try again."
        case .translationFailed:
            return "Translation failed. Please try again."
        case .upstreamTimeout:
            return "Translation took too long. Please try again."
        case .invalidRequest:
            return "Something went wrong with that request."
        case .network:
            return "Couldn't reach SayWell. Check your connection."
        case .unknown(_, let message):
            return message ?? "Something unexpected happened."
        }
    }

    static func from(statusCode: Int, errorCode: String?, retryAfter: String?) -> SayWellError {
        switch errorCode {
        case "empty_input":
            return .emptyInput
        case "input_too_long":
            return .inputTooLong
        case "gibberish_input":
            return .gibberishInput
        case "rate_limited":
            let seconds = retryAfter.flatMap { Int($0) }
            return .rateLimited(retryAfter: seconds)
        case "translation_failed":
            return .translationFailed
        case "upstream_timeout":
            return .upstreamTimeout
        case "invalid_json", "invalid_body":
            return .invalidRequest
        default:
            return .unknown(statusCode: statusCode, message: errorCode)
        }
    }
}
