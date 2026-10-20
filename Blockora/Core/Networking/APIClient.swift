import Foundation

/// Thin JSON/HTTP wrapper the future RemoteEconomyService talks through. Kept
/// separate from any one service so auth/retry/idempotency-header concerns
/// live in exactly one place (§46/§48).
struct APIClient {
    var baseURL: URL

    static let cloudflare = APIClient(baseURL: URL(string: "https://api.blockora.app/api/v1")!)

    func get<Response: Decodable>(_ path: String) async throws -> Response {
        try await send(path: path, method: "GET", body: Optional<Data>.none)
    }

    func post<Body: Encodable, Response: Decodable>(_ path: String, body: Body) async throws -> Response {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(body)
        return try await send(path: path, method: "POST", body: data)
    }

    private func send<Response: Decodable>(path: String, method: String, body: Data?) async throws -> Response {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.server(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Response.self, from: data)
    }
}

enum APIError: Error {
    case server(statusCode: Int)
    case notImplemented
}
