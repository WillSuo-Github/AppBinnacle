import Foundation

struct HTTPResponse: Sendable {
    var statusCode: Int
    var data: Data

    var isSuccess: Bool { (200..<300).contains(statusCode) }
    var text: String { String(decoding: data, as: UTF8.self) }
}

protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}

struct URLSessionTransport: HTTPTransport {
    var session: URLSession = .shared

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        var request = request
        if request.value(forHTTPHeaderField: "User-Agent") == nil {
            request.setValue("AppBinnacle/\(BinnacleVersion.string)", forHTTPHeaderField: "User-Agent")
        }
        request.timeoutInterval = 60
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BinnacleError.invalidResponse(service: request.url?.host() ?? "server", message: "not an HTTP response")
        }
        return HTTPResponse(statusCode: http.statusCode, data: data)
    }
}
