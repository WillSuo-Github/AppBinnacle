import Foundation

enum GoogleEndpoints {
    static let token = "https://oauth2.googleapis.com/token"
    static let analyticsData = "https://analyticsdata.googleapis.com/v1beta"
    static let crashlytics = "https://firebasecrashlytics.googleapis.com/v1alpha"
}

enum GoogleScope {
    static let analyticsReadOnly = "https://www.googleapis.com/auth/analytics.readonly"
    static let cloudPlatform = "https://www.googleapis.com/auth/cloud-platform"
    static let all = [analyticsReadOnly, cloudPlatform]
}

/// Exchanges a service account key for OAuth access tokens and reuses them until they expire.
actor GoogleAccessTokenProvider {
    private let account: GoogleServiceAccount
    private let scopes: [String]
    private let transport: any HTTPTransport
    private var cached: (token: String, expiresAt: Date)?
    private var inFlight: Task<(token: String, expiresAt: Date), any Error>?

    init(account: GoogleServiceAccount, scopes: [String] = GoogleScope.all, transport: any HTTPTransport = URLSessionTransport()) {
        self.account = account
        self.scopes = scopes
        self.transport = transport
    }

    func accessToken() async throws -> String {
        if let cached, cached.expiresAt.timeIntervalSinceNow > 60 { return cached.token }
        if let inFlight { return try await inFlight.value.token }
        let account = account, scopes = scopes, transport = transport
        let task = Task { try await Self.requestToken(account: account, scopes: scopes, transport: transport) }
        inFlight = task
        defer { inFlight = nil }
        let result = try await task.value
        cached = result
        return result.token
    }

    private static func requestToken(account: GoogleServiceAccount, scopes: [String],
                                     transport: any HTTPTransport) async throws -> (token: String, expiresAt: Date) {
        let assertion = try JWT.googleAssertion(account: account, scopes: scopes)
        guard let url = URL(string: account.tokenURI ?? GoogleEndpoints.token) else {
            throw BinnacleError.invalidCredential("The service account has an invalid token_uri.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=\(assertion)".utf8)
        let response = try await transport.send(request)
        guard response.isSuccess else {
            let failure = try? JSONDecoder().decode(TokenError.self, from: response.data)
            let message = [failure?.error, failure?.errorDescription].compactMap { $0 }.joined(separator: ": ")
            throw BinnacleError.http(service: "Google sign-in", status: response.statusCode, message: message)
        }
        guard let token = try? JSONDecoder().decode(TokenResponse.self, from: response.data) else {
            throw BinnacleError.invalidResponse(service: "Google sign-in", message: "missing access_token")
        }
        return (token.accessToken, Date().addingTimeInterval(TimeInterval(token.expiresIn ?? 3600)))
    }

    private struct TokenResponse: Decodable {
        var accessToken: String
        var expiresIn: Int?
        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresIn = "expires_in"
        }
    }

    private struct TokenError: Decodable {
        var error: String?
        var errorDescription: String?
        enum CodingKeys: String, CodingKey {
            case error
            case errorDescription = "error_description"
        }
    }
}

enum GoogleAPI {
    static func send(_ request: URLRequest, service: String, tokens: GoogleAccessTokenProvider,
                     transport: any HTTPTransport) async throws -> Data {
        var request = request
        request.setValue("Bearer \(try await tokens.accessToken())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let response = try await transport.send(request)
        guard response.isSuccess else {
            throw BinnacleError.http(service: service, status: response.statusCode, message: errorMessage(from: response.data))
        }
        return response.data
    }

    static func errorMessage(from data: Data) -> String {
        struct Envelope: Decodable {
            struct Body: Decodable {
                var message: String?
                var status: String?
            }
            var error: Body
        }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else { return "" }
        return [envelope.error.status, envelope.error.message].compactMap { $0 }.joined(separator: ": ")
    }
}

/// Decodes Int64 values that Google APIs send either as JSON strings or numbers.
struct FlexibleInt: Decodable, Sendable {
    var value: Int

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Int.self) {
            value = number
        } else if let text = try? container.decode(String.self), let number = Int(text) {
            value = number
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected an integer or numeric string.")
        }
    }
}
