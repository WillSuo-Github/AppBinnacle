import Foundation
import Security

/// Test data shared by the test suites.
enum Fixtures {
    /// A daily SALES/SUMMARY report gzipped by the gzip command (with a stored file name).
    static let salesReportGzipBase64 = "H4sICGz0zWoCA1NfRF84MDAxMjM0NV8yMDI2MTAxMS50eHQAxZRRb5swEMefb5/CX2AphiYpj4QQrVo7LAir2peJwSWxRGxkm2z59rNJmqSTokbTolpCZ8zd/X93PsGU3PAaFbD9hsSyE0ZtIf9awBQ32MjWfp5z0yB8R6W5FM657ipD5tsWyX2NwvAFt16F4EYfo4j1qxBrDRNcckGmpUFIRL3bxJ02cu0UO6VQVFvYS1uE2n3enRK5OOaJ2rZ5o3hIwhSv0IGt5S6elTbcnPrm3U9dKd6avgRUXNYQW5KltOXGjxMH7pLkXdtKZbAmrCnNQqq1hlcCkmGp+w6gRrVxPlaYiyXEDbdKkCrXRNeYTxFjDwkUOTwl0fxLkrHoAZLf5dqVYKXgCUuzcuhlA8HAH3hAZ0A9sNa7ofTG9/zR6bbIpy6bM9QPboej8V3ovN3a5wLgbCUFAk9zd/xvDLdnEeJvz/bpzRURghn4H9yF8QyCa90E+8Gy9Jy+m/U9w31EIQBvML4AIwxDz/Oo9Q5DOC3zMqC8mJwHajp9ILL3DqNBcI4oKTKYJr3ZEflw9zdRhgJ/2UZT8iiFWb3Pl7pI+/aGMO357P/gOLbDS+5reFj/fWZeXmxzPn5kPtPrzcwfoDU/Ty8GAAA="

    /// "Hello, AppBinnacle!\n" gzipped without a file name.
    static let helloGzipBase64 = "H4sIAAAAAAACA/NIzcnJ11FwLChwyszLS0zOSVXkAgAg40jYFAAAAA=="

    static var salesReportGzip: Data { Data(base64Encoded: salesReportGzipBase64)! }

    /// A 2048-bit RSA key in PKCS#8 PEM form, like the private_key field of a Google service account file.
    /// It is generated for each test run so the repository never contains a private key.
    static let testRSAPrivateKeyPEM: String = {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error),
              let pkcs1 = SecKeyCopyExternalRepresentation(key, &error) as Data?
        else { fatalError("Could not create a test RSA key: \(String(describing: error))") }
        // PrivateKeyInfo ::= SEQUENCE { version 0, AlgorithmIdentifier rsaEncryption, OCTET STRING RSAPrivateKey }
        let rsaEncryption = DERWriter.element(0x06, Data([0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01]))
        let algorithm = DERWriter.element(0x30, rsaEncryption + Data([0x05, 0x00]))
        let info = DERWriter.element(0x30, Data([0x02, 0x01, 0x00]) + algorithm + DERWriter.element(0x04, pkcs1))
        let body = info.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        return "-----BEGIN PRIVATE KEY-----\n\(body)\n-----END PRIVATE KEY-----\n"
    }()

    static let weatherPal = TrackedApp(
        appleID: "1234567890", name: "Weather Pal", bundleID: "com.example.weatherpal", sku: "WEATHERPAL",
        ga4PropertyID: "987654321", firebaseAppID: "1:1234567890:ios:abc123")

    static func day(_ iso: String) -> Day { Day(iso: iso)! }

    /// Noon on the given day in Pacific Time.
    static func pacificNoon(_ iso: String) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .appStoreReporting
        let day = Day(iso: iso)!
        return calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12))!
    }

    static let ga4BatchResponse = """
    {"reports":[
      {"dimensionHeaders":[{"name":"date"}],
       "metricHeaders":[{"name":"activeUsers","type":"TYPE_INTEGER"},{"name":"newUsers","type":"TYPE_INTEGER"},{"name":"sessions","type":"TYPE_INTEGER"},{"name":"crashAffectedUsers","type":"TYPE_INTEGER"},{"name":"crashFreeUsersRate","type":"TYPE_FLOAT"}],
       "rows":[
         {"dimensionValues":[{"value":"20261006"}],"metricValues":[{"value":"120"},{"value":"30"},{"value":"300"},{"value":"2"},{"value":"0.98333"}]},
         {"dimensionValues":[{"value":"20261012"}],"metricValues":[{"value":"0"},{"value":"0"},{"value":"0"},{"value":"0"},{"value":"0"}]},
         {"dimensionValues":[{"value":"20260929"}],"metricValues":[{"value":"200"},{"value":"50"},{"value":"420"},{"value":"1"},{"value":"0.995"}]}
       ],"rowCount":3},
      {"metricHeaders":[{"name":"activeUsers"},{"name":"newUsers"},{"name":"sessions"},{"name":"crashAffectedUsers"},{"name":"crashFreeUsersRate"}],
       "rows":[{"metricValues":[{"value":"800"},{"value":"150"},{"value":"2100"},{"value":"12"},{"value":"0.985"}]}],"rowCount":1},
      {"metricHeaders":[{"name":"activeUsers"},{"name":"newUsers"},{"name":"sessions"},{"name":"crashAffectedUsers"},{"name":"crashFreeUsersRate"}],
       "rows":[{"metricValues":[{"value":"1000"},{"value":"220"},{"value":"2600"},{"value":"5"},{"value":"0.995"}]}],"rowCount":1},
      {"dimensionHeaders":[{"name":"appVersion"}],
       "metricHeaders":[{"name":"activeUsers"},{"name":"crashAffectedUsers"},{"name":"crashFreeUsersRate"}],
       "rows":[
         {"dimensionValues":[{"value":"3.2.0"}],"metricValues":[{"value":"500"},{"value":"10"},{"value":"0.98"}]},
         {"dimensionValues":[{"value":"3.1.0"}],"metricValues":[{"value":"280"},{"value":"2"},{"value":"0.9929"}]},
         {"dimensionValues":[{"value":"(not set)"}],"metricValues":[{"value":"20"},{"value":"0"},{"value":"1"}]}
       ],"rowCount":3}
    ],"kind":"analyticsData#batchRunReports"}
    """

    static let crashlyticsTopIssues = """
    {"groups":[
      {"issue":{"id":"abc123","title":"EXC_BAD_ACCESS in WeatherStore.refresh()","subtitle":"WeatherStore.swift line 88","errorType":"FATAL","uri":"https://console.firebase.google.com/project/demo/crashlytics/issues/abc123"},
       "metrics":[{"startTime":"2026-10-06T00:00:00Z","endTime":"2026-10-13T00:00:00Z","eventsCount":"120","impactedUsersCount":"33"}]},
      {"issue":{"id":"def456","title":"NSInvalidArgumentException","errorType":"NON_FATAL"},
       "metrics":[{"eventsCount":7,"impactedUsersCount":"4"}]},
      {"metrics":[{"eventsCount":"1"}]}
    ]}
    """

    static let customerReviews = """
    {"data":[
      {"type":"customerReviews","id":"r1","attributes":{"rating":1,"title":"Crashes on launch","body":"Since 3.2 the app\\ncrashes every time.","reviewerNickname":"sam","createdDate":"2026-10-11T08:15:22-07:00","territory":"USA"}},
      {"type":"customerReviews","id":"r2","attributes":{"rating":5,"title":"Great","body":"Love it.","reviewerNickname":"kim","createdDate":"2026-10-07T23:59:00.123-07:00","territory":"JPN"}},
      {"type":"customerReviews","id":"r3","attributes":{"rating":4,"title":"Nice","body":"Good app.","reviewerNickname":"lee","createdDate":"2026-10-01T10:00:00-07:00","territory":"CHN"}},
      {"type":"customerReviews","id":"broken","attributes":{"title":"No rating"}}
    ],"links":{"self":"https://api.appstoreconnect.apple.com/v1/apps/1234567890/customerReviews"}}
    """
}

/// Answers requests with a closure and records them for assertions.
final class MockTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    private let handler: @Sendable (URLRequest) throws -> HTTPResponse

    init(_ handler: @escaping @Sendable (URLRequest) throws -> HTTPResponse) {
        self.handler = handler
    }

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        lock.withLock { recorded.append(request) }
        return try handler(request)
    }
}

final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [SecretItem: String]

    init(_ values: [SecretItem: String] = [:]) {
        self.values = values
    }

    func secret(for item: SecretItem) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[item]
    }

    func setSecret(_ value: String, for item: SecretItem) throws {
        lock.lock()
        values[item] = value
        lock.unlock()
    }

    func removeSecret(for item: SecretItem) throws {
        lock.lock()
        values[item] = nil
        lock.unlock()
    }

    func contains(_ item: SecretItem) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return values[item] != nil
    }
}

extension URLRequest {
    func queryValue(_ name: String) -> String? {
        url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
            .queryItems?.first { $0.name == name }?.value
    }
}

extension HTTPResponse {
    static func json(_ text: String, status: Int = 200) -> HTTPResponse {
        HTTPResponse(statusCode: status, data: Data(text.utf8))
    }
}

/// Minimal DER encoding, used to wrap generated keys the way key files store them.
enum DERWriter {
    static func element(_ tag: UInt8, _ content: Data) -> Data {
        var encoded = Data([tag])
        if content.count < 0x80 {
            encoded.append(UInt8(content.count))
        } else {
            var length: [UInt8] = []
            var remaining = content.count
            while remaining > 0 {
                length.insert(UInt8(remaining & 0xFF), at: 0)
                remaining >>= 8
            }
            encoded.append(0x80 | UInt8(length.count))
            encoded.append(contentsOf: length)
        }
        return encoded + content
    }
}
