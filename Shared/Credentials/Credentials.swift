import CryptoKit
import Foundation
import Security

enum SecretItem: String, CaseIterable, Sendable {
    case appStoreConnectPrivateKey = "app-store-connect-private-key"
    case googleServiceAccount = "google-service-account"

    var label: String {
        switch self {
        case .appStoreConnectPrivateKey: return "App Store Connect API key"
        case .googleServiceAccount: return "Google service account"
        }
    }
}

protocol SecretStore: Sendable {
    func secret(for item: SecretItem) throws -> String?
    func setSecret(_ value: String, for item: SecretItem) throws
    func removeSecret(for item: SecretItem) throws
    /// Checks for an item without reading its contents, so it never triggers a Keychain prompt.
    func contains(_ item: SecretItem) -> Bool
}

/// Keeps credentials as generic passwords in the user's login Keychain.
struct KeychainSecretStore: SecretStore {
    var service = "dev.appbinnacle.credentials"

    func secret(for item: SecretItem) throws -> String? {
        var query = baseQuery(item)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw Self.error(status) }
        return String(decoding: data, as: UTF8.self)
    }

    func setSecret(_ value: String, for item: SecretItem) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrLabel as String: "AppBinnacle: \(item.label)",
        ]
        var status = SecItemUpdate(baseQuery(item) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let query = baseQuery(item).merging(attributes) { _, new in new }
            status = SecItemAdd(query as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw Self.error(status) }
    }

    func removeSecret(for item: SecretItem) throws {
        let status = SecItemDelete(baseQuery(item) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Self.error(status) }
    }

    func contains(_ item: SecretItem) -> Bool {
        var query = baseQuery(item)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess
    }

    private func baseQuery(_ item: SecretItem) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: item.rawValue,
        ]
    }

    private static func error(_ status: OSStatus) -> BinnacleError {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown error"
        return .keychain(status: status, message: message)
    }
}

struct AppStoreConnectCredentials: Sendable, Equatable {
    var issuerID: String
    var keyID: String
    var privateKeyPEM: String
    var vendorNumber: String

    static func validatePrivateKey(_ pem: String) throws {
        do {
            _ = try P256.Signing.PrivateKey(pemRepresentation: pem)
        } catch {
            throw BinnacleError.invalidCredential("This is not a valid App Store Connect API key (.p8 file).")
        }
    }

    /// App Store Connect names downloaded keys AuthKey_<KEY ID>.p8.
    static func keyID(fromFileName name: String) -> String? {
        guard name.hasPrefix("AuthKey_"), name.lowercased().hasSuffix(".p8") else { return nil }
        let keyID = name.dropFirst("AuthKey_".count).dropLast(".p8".count)
        return keyID.isEmpty ? nil : String(keyID)
    }
}

struct GoogleServiceAccount: Codable, Sendable, Equatable {
    var type: String?
    var projectID: String?
    var privateKeyID: String?
    var privateKey: String
    var clientEmail: String
    var tokenURI: String?

    enum CodingKeys: String, CodingKey {
        case type
        case projectID = "project_id"
        case privateKeyID = "private_key_id"
        case privateKey = "private_key"
        case clientEmail = "client_email"
        case tokenURI = "token_uri"
    }

    static func parse(_ json: String) throws -> GoogleServiceAccount {
        let account: GoogleServiceAccount
        do {
            account = try JSONDecoder().decode(GoogleServiceAccount.self, from: Data(json.utf8))
        } catch {
            throw BinnacleError.invalidCredential("This is not a Google service account key. Download a JSON key from Google Cloud → IAM → Service accounts.")
        }
        if let type = account.type, type != "service_account" {
            throw BinnacleError.invalidCredential("Expected a service account key, but the file has type \"\(type)\".")
        }
        guard !account.privateKey.trimmed.isEmpty, !account.clientEmail.trimmed.isEmpty else {
            throw BinnacleError.invalidCredential("The service account key is missing client_email or private_key.")
        }
        _ = try RSASigner.privateKey(fromPEM: account.privateKey)
        return account
    }
}

struct ResolvedCredentials: Sendable {
    var appStoreConnect: AppStoreConnectCredentials?
    var google: GoogleServiceAccount?
    var problems: [String] = []
}

/// Combines saved settings, Keychain secrets, and environment overrides into usable credentials.
struct CredentialResolver: Sendable {
    var secrets: any SecretStore
    var environment: [String: String]

    init(secrets: any SecretStore = KeychainSecretStore(),
         environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.secrets = secrets
        self.environment = environment
    }

    func resolve(_ configuration: BinnacleConfiguration) -> ResolvedCredentials {
        var result = ResolvedCredentials()
        resolveAppStoreConnect(configuration.appStoreConnect, into: &result)
        resolveGoogle(into: &result)
        return result
    }

    private func resolveAppStoreConnect(_ settings: AppStoreConnectSettings, into result: inout ResolvedCredentials) {
        let issuerID = value(for: EnvironmentKey.ascIssuerID) ?? settings.issuerID.trimmed
        let keyID = value(for: EnvironmentKey.ascKeyID) ?? settings.keyID.trimmed
        let vendorNumber = value(for: EnvironmentKey.ascVendorNumber) ?? settings.vendorNumber.trimmed

        var privateKey: String?
        if let path = value(for: EnvironmentKey.ascPrivateKeyPath) {
            privateKey = readFile(path, variable: EnvironmentKey.ascPrivateKeyPath, problems: &result.problems)
        } else {
            do {
                privateKey = try secrets.secret(for: .appStoreConnectPrivateKey)
            } catch {
                result.problems.append("Could not read the App Store Connect key from the Keychain: \(error.localizedDescription)")
            }
        }

        if !issuerID.isEmpty, !keyID.isEmpty, let privateKey {
            result.appStoreConnect = AppStoreConnectCredentials(
                issuerID: issuerID, keyID: keyID, privateKeyPEM: privateKey, vendorNumber: vendorNumber)
        } else if !issuerID.isEmpty || !keyID.isEmpty || privateKey != nil {
            var missing: [String] = []
            if issuerID.isEmpty { missing.append("issuer ID") }
            if keyID.isEmpty { missing.append("key ID") }
            if privateKey == nil { missing.append("private key (.p8)") }
            result.problems.append("App Store Connect is missing: \(missing.joined(separator: ", ")).")
        }
    }

    private func resolveGoogle(into result: inout ResolvedCredentials) {
        var json: String?
        var origin = "Keychain"
        if let path = value(for: EnvironmentKey.googleServiceAccountPath) {
            origin = path
            json = readFile(path, variable: EnvironmentKey.googleServiceAccountPath, problems: &result.problems)
        } else {
            do {
                json = try secrets.secret(for: .googleServiceAccount)
            } catch {
                result.problems.append("Could not read the Google service account from the Keychain: \(error.localizedDescription)")
            }
            // GOOGLE_APPLICATION_CREDENTIALS often points at unrelated gcloud credentials,
            // so only use it when nothing else is configured and it holds a service account key.
            if json == nil, let path = value(for: EnvironmentKey.googleApplicationCredentials),
               let text = try? String(contentsOf: BinnaclePaths.expand(path), encoding: .utf8),
               (try? GoogleServiceAccount.parse(text)) != nil {
                origin = path
                json = text
            }
        }
        guard let json else { return }
        do {
            result.google = try GoogleServiceAccount.parse(json)
        } catch {
            result.problems.append("Google service account (\(origin)): \(error.localizedDescription)")
        }
    }

    private func value(for key: String) -> String? {
        guard let value = environment[key]?.trimmed, !value.isEmpty else { return nil }
        return value
    }

    private func readFile(_ path: String, variable: String, problems: inout [String]) -> String? {
        do {
            return try String(contentsOf: BinnaclePaths.expand(path), encoding: .utf8)
        } catch {
            problems.append("Could not read \(variable) (\(path)): \(error.localizedDescription)")
            return nil
        }
    }
}
