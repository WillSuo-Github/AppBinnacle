import CryptoKit
import Foundation
import Testing

struct ConfigurationTests {
    @Test func decodingFillsInMissingFields() throws {
        let json = #"{"apps":[{"appleID":"1234567890","name":"Weather Pal"}]}"#
        let configuration = try JSONDecoder().decode(BinnacleConfiguration.self, from: Data(json.utf8))
        #expect(configuration.appStoreConnect == AppStoreConnectSettings())
        #expect(configuration.apps.first?.ga4PropertyID == "")
        #expect(configuration.app(matching: "weather pal")?.appleID == "1234567890")
        #expect(configuration.app(matching: "weather")?.appleID == "1234567890")
        #expect(configuration.app(matching: "pal")?.appleID == "1234567890")
    }

    @Test func savesAndLoadsRoundTrip() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "binnacle-tests-\(UUID().uuidString)/config.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = ConfigurationStore(fileURL: file)
        #expect(try store.load() == BinnacleConfiguration())

        let configuration = BinnacleConfiguration(
            appStoreConnect: AppStoreConnectSettings(issuerID: "issuer", keyID: "KEY", vendorNumber: "8001"),
            apps: [Fixtures.weatherPal])
        try store.save(configuration)
        #expect(try store.load() == configuration)

        // An empty 0-byte file (e.g. freshly created with touch/mktemp) should decode as default configuration.
        try Data().write(to: file)
        #expect(try store.load() == BinnacleConfiguration())

        let permissions = try FileManager.default.attributesOfItem(atPath: file.path(percentEncoded: false))[.posixPermissions] as? Int
        #expect(permissions == 0o600)
    }

    @Test func readsProjectNumberFromFirebaseAppID() {
        #expect(TrackedApp.projectNumber(fromFirebaseAppID: "1:1234567890:ios:abc123") == "1234567890")
        #expect(TrackedApp.projectNumber(fromFirebaseAppID: "com.example.app") == nil)
        #expect(TrackedApp.normalizedPropertyID("properties/987654321") == "987654321")
    }

    @Test func mergingAppsKeepsLocalSettings() {
        var configuration = BinnacleConfiguration(apps: [Fixtures.weatherPal])
        let added = configuration.mergeApps([
            ASCApp(id: "1234567890", name: "Weather Pal 2", bundleID: "com.example.weatherpal", sku: "WEATHERPAL"),
            ASCApp(id: "5555555555", name: "Other App", bundleID: "com.example.other", sku: "OTHERAPP"),
        ])
        #expect(added == 1)
        #expect(configuration.apps.count == 2)
        #expect(configuration.apps[0].name == "Weather Pal 2")
        #expect(configuration.apps[0].ga4PropertyID == "987654321")
    }

    @Test func resolvesKeychainSecretsWithEnvironmentOverrides() throws {
        let pem = P256.Signing.PrivateKey().pemRepresentation
        let configuration = BinnacleConfiguration(
            appStoreConnect: AppStoreConnectSettings(issuerID: "saved-issuer", keyID: "SAVEDKEY", vendorNumber: "8001"))
        let secrets = InMemorySecretStore([.appStoreConnectPrivateKey: pem])

        let saved = CredentialResolver(secrets: secrets, environment: [:]).resolve(configuration)
        #expect(saved.appStoreConnect?.issuerID == "saved-issuer")
        #expect(saved.appStoreConnect?.privateKeyPEM == pem)
        #expect(saved.google == nil)
        #expect(saved.problems.isEmpty)

        let overridden = CredentialResolver(secrets: secrets, environment: [
            EnvironmentKey.ascIssuerID: "env-issuer",
            EnvironmentKey.ascVendorNumber: "9009",
        ]).resolve(configuration)
        #expect(overridden.appStoreConnect?.issuerID == "env-issuer")
        #expect(overridden.appStoreConnect?.keyID == "SAVEDKEY")
        #expect(overridden.appStoreConnect?.vendorNumber == "9009")
    }

    @Test func reportsIncompleteCredentials() throws {
        let configuration = BinnacleConfiguration(appStoreConnect: AppStoreConnectSettings(issuerID: "issuer"))
        let resolved = CredentialResolver(secrets: InMemorySecretStore(), environment: [
            EnvironmentKey.googleServiceAccountPath: "/nonexistent/service-account.json",
        ]).resolve(configuration)
        #expect(resolved.appStoreConnect == nil)
        #expect(resolved.problems.contains("App Store Connect is missing: key ID, private key (.p8)."))
        #expect(resolved.problems.contains { $0.hasPrefix("Could not read BINNACLE_GOOGLE_SERVICE_ACCOUNT_PATH") })
    }
}
