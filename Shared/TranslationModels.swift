import Foundation

struct TranslationRequest: Encodable {
    let text: String
}

struct TranslationResponse: Decodable, Equatable {
    let translation: String
    let source: TranslationSource
    let normalized: String
}

enum TranslationSource: String, Decodable, Equatable {
    case cache
    case model
}

struct APIErrorResponse: Decodable {
    let error: String
}

enum SayWellError: LocalizedError {
    case emptyInput
    case inputTooLong
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
