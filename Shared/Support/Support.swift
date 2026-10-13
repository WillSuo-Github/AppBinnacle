import Foundation

enum BinnacleVersion {
    static let string = "0.1.0"
}

enum BinnacleError: LocalizedError, Equatable, Sendable {
    case notConfigured(String)
    case invalidCredential(String)
    case invalidArgument(String)
    case keychain(status: Int32, message: String)
    case http(service: String, status: Int, message: String)
    case invalidResponse(service: String, message: String)
    case fileSystem(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured(let message), .invalidCredential(let message),
             .invalidArgument(let message), .fileSystem(let message):
            return message
        case .keychain(let status, let message):
            return "Keychain error \(status): \(message)"
        case .http(let service, let status, let message):
            return message.isEmpty
                ? "\(service) returned HTTP \(status)."
                : "\(service) returned HTTP \(status): \(message)"
        case .invalidResponse(let service, let message):
            return "\(service) sent an unexpected response: \(message)"
        }
    }
}

/// Environment variables the CLI honors. They take precedence over the saved configuration.
enum EnvironmentKey {
    static let configPath = "BINNACLE_CONFIG"
    static let ascIssuerID = "BINNACLE_ASC_ISSUER_ID"
    static let ascKeyID = "BINNACLE_ASC_KEY_ID"
    static let ascVendorNumber = "BINNACLE_ASC_VENDOR_NUMBER"
    static let ascPrivateKeyPath = "BINNACLE_ASC_PRIVATE_KEY_PATH"
    static let googleServiceAccountPath = "BINNACLE_GOOGLE_SERVICE_ACCOUNT_PATH"
    static let googleApplicationCredentials = "GOOGLE_APPLICATION_CREDENTIALS"

    static let all = [
        configPath, ascIssuerID, ascKeyID, ascVendorNumber, ascPrivateKeyPath,
        googleServiceAccountPath, googleApplicationCredentials,
    ]
}

enum BinnaclePaths {
    static var applicationSupport: URL {
        URL.applicationSupportDirectory.appending(path: "AppBinnacle", directoryHint: .isDirectory)
    }

    static var caches: URL {
        URL.cachesDirectory.appending(path: "AppBinnacle", directoryHint: .isDirectory)
    }

    static func expand(_ path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }
}

enum JSONCoding {
    static func encoder(pretty: Bool = false) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = pretty
            ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            : [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func string<T: Encodable>(_ value: T, pretty: Bool = true) throws -> String {
        String(decoding: try encoder(pretty: pretty).encode(value), as: UTF8.self)
    }
}

enum ISO8601 {
    static func parse(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string)
    }

    static func string(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

/// Locale-independent formatting so CLI output stays stable for scripts and AI agents.
enum Format {
    private static let english = Locale(identifier: "en_US")

    static func integer(_ value: Int) -> String {
        value.formatted(.number.locale(english))
    }

    static func integer(_ value: Double) -> String {
        integer(Int(value.rounded()))
    }

    static func number(_ value: Double, fractionDigits: Int = 1) -> String {
        value.formatted(.number.precision(.fractionLength(fractionDigits)).locale(english))
    }

    static func percent(_ value: Double) -> String {
        number(value, fractionDigits: 1) + "%"
    }

    static func signedPercent(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        let sign = value > 0 ? "+" : (value < 0 ? "-" : "")
        return sign + percent(abs(value))
    }

    /// Formats a 0...1 fraction as a percentage with two decimals.
    static func rate(_ fraction: Double?) -> String {
        guard let fraction else { return "n/a" }
        return number(fraction * 100, fractionDigits: 2) + "%"
    }

    /// Formats the difference between two 0...1 fractions in percentage points.
    static func points(_ fractionDelta: Double) -> String {
        number(fractionDelta * 100, fractionDigits: 2) + " pp"
    }

    static func money(_ amount: Decimal, currency: String) -> String {
        "\(currency) " + amount.formatted(.number.precision(.fractionLength(2)).locale(english))
    }
}

extension StringProtocol {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
