import Foundation

/// A minimal Square REST client: JSON in, JSON out, Square's error shape
/// turned into a readable message. What the kiosk does with Square outside
/// the card reader — the customer directory, looking a payment up — goes
/// through here.
enum SquareAPI {

    struct Failure: LocalizedError {
        let message: String
        /// Square's error code (e.g. "NOT_FOUND"), when it sent one.
        var code: String? = nil
        var errorDescription: String? { message }
    }

    /// Send a request and decode the response. `body` is any Encodable, or
    /// nil for GET.
    static func send<Response: Decodable>(
        _ method: String,
        _ path: String,
        query: [URLQueryItem] = [],
        body: (any Encodable)? = nil,
        as: Response.Type = Response.self
    ) async throws -> Response {
        var url = KioskConfig.squareBaseURL.appendingPathComponent(path)
        if !query.isEmpty { url.append(queryItems: query) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue("Bearer \(KioskConfig.squareAccessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(KioskConfig.squareAPIVersion, forHTTPHeaderField: "Square-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body {
            request.httpBody = try encoder.encode(AnyEncodable(body))
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let errors = (try? decoder.decode(ErrorBody.self, from: data))?.errors ?? []
            let first = errors.first
            let message = first?.detail ?? first?.code ?? "Square returned HTTP \(status)."
            NSLog("Square \(method) \(path) failed (\(status)): \(String(decoding: data, as: UTF8.self))")
            throw Failure(message: message, code: first?.code)
        }
        return try decoder.decode(Response.self, from: data)
    }

    // MARK: - Wire types

    private struct ErrorBody: Decodable {
        struct Item: Decodable {
            let code: String?
            let detail: String?
        }
        let errors: [Item]?
    }

    private struct AnyEncodable: Encodable {
        let value: any Encodable
        init(_ value: any Encodable) { self.value = value }
        func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}
