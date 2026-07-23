import Foundation

actor SayWellAPI {
    static let shared = SayWellAPI()

    /// Keyboard extension session — fail fast when offline instead of waiting for connectivity.
    static let keyboard: SayWellAPI = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = SayWellAPI.requestTimeout
        config.timeoutIntervalForResource = SayWellAPI.requestTimeout
        config.waitsForConnectivity = false
        return SayWellAPI(session: URLSession(configuration: config))
    }()

    /// Live Worker from README / deploy.
    static let productionBaseURL = URL(string: "https://saywell-backend.saywell.workers.dev")!

    /// Must stay at or under the Worker's `MAX_INPUT_CHARS` (rejects at 300 in live checks).
    static let maxInputChars = 256

    /// Slightly above the Worker's 8s Gemini abort so the client surfaces `upstream_timeout` cleanly.
    private static let requestTimeout: TimeInterval = 12

    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = SayWellAPI.productionBaseURL, session: URLSession? = nil) {
        self.baseURL = baseURL

        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = Self.requestTimeout
            config.timeoutIntervalForResource = Self.requestTimeout
            config.waitsForConnectivity = true
            self.session = URLSession(configuration: config)
        }
    }

    func translate(text: String, tone: TranslationTone = KeyboardStatusStore.translationTone) async throws -> TranslationResponse {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SayWellError.emptyInput }
        guard trimmed.count <= Self.maxInputChars else { throw SayWellError.inputTooLong }

        var request = URLRequest(url: baseURL.appendingPathComponent("translate"))
        request.httpMethod = "POST"
        request.timeoutInterval = Self.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(DeviceIDStore.deviceID, forHTTPHeaderField: "X-Device-Id")
        request.httpBody = try JSONEncoder().encode(
            TranslationRequest(text: trimmed, tone: tone.rawValue)
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw SayWellError.upstreamTimeout
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw urlError
        } catch {
            throw SayWellError.network(underlying: error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SayWellError.network(underlying: URLError(.badServerResponse))
        }

        if httpResponse.statusCode == 200 {
            do {
                return try JSONDecoder().decode(TranslationResponse.self, from: data)
            } catch {
                throw SayWellError.invalidRequest
            }
        }

        let errorCode = try? JSONDecoder().decode(APIErrorResponse.self, from: data).error
        let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
        throw SayWellError.from(
            statusCode: httpResponse.statusCode,
            errorCode: errorCode,
            retryAfter: retryAfter
        )
    }

    func healthCheck() async -> Bool {
        let url = baseURL.appendingPathComponent("health")
        do {
            let (_, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            return httpResponse.statusCode == 200
        } catch {
            return false
        }
    }
}
