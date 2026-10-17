import Foundation

/// Everything AppBinnacle stores outside the Keychain. Secrets never live here.
struct BinnacleConfiguration: Codable, Equatable, Sendable {
    var appStoreConnect = AppStoreConnectSettings()
    var google = GoogleSettings()
    var apps: [TrackedApp] = []
    var displayCurrency: DisplayCurrency = .usd

    init(appStoreConnect: AppStoreConnectSettings = .init(), google: GoogleSettings = .init(), apps: [TrackedApp] = [], displayCurrency: DisplayCurrency = .usd) {
        self.appStoreConnect = appStoreConnect
        self.google = google
        self.apps = apps
        self.displayCurrency = displayCurrency
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appStoreConnect = try container.decodeIfPresent(AppStoreConnectSettings.self, forKey: .appStoreConnect) ?? .init()
        google = try container.decodeIfPresent(GoogleSettings.self, forKey: .google) ?? .init()
        apps = try container.decodeIfPresent([TrackedApp].self, forKey: .apps) ?? []
        displayCurrency = (try? container.decode(DisplayCurrency.self, forKey: .displayCurrency)) ?? .usd
    }

    func app(matching query: String) -> TrackedApp? {
        if let exact = apps.first(where: { $0.matches(query) }) {
            return exact
        }
        let needle = query.trimmed.lowercased()
        guard !needle.isEmpty else { return nil }
        return apps.first(where: {
            $0.name.lowercased().contains(needle) ||
            $0.bundleID.lowercased().contains(needle) ||
            $0.sku.lowercased().contains(needle)
        })
    }

    /// Adds apps that are not tracked yet and refreshes App Store metadata for tracked ones.
    /// Returns the number of newly added apps.
    @discardableResult
    mutating func mergeApps(_ remoteApps: [ASCApp]) -> Int {
        var added = 0
        for remote in remoteApps {
            if let index = apps.firstIndex(where: { $0.appleID == remote.id }) {
                apps[index].name = remote.name
                apps[index].bundleID = remote.bundleID
                if !remote.sku.isEmpty { apps[index].sku = remote.sku }
            } else {
                apps.append(TrackedApp(appleID: remote.id, name: remote.name, bundleID: remote.bundleID, sku: remote.sku))
                added += 1
            }
        }
        return added
    }
}

struct AppStoreConnectSettings: Codable, Equatable, Sendable {
    var issuerID = ""
    var keyID = ""
    var vendorNumber = ""

    init(issuerID: String = "", keyID: String = "", vendorNumber: String = "") {
        self.issuerID = issuerID
        self.keyID = keyID
        self.vendorNumber = vendorNumber
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        issuerID = try container.decodeIfPresent(String.self, forKey: .issuerID) ?? ""
        keyID = try container.decodeIfPresent(String.self, forKey: .keyID) ?? ""
        vendorNumber = try container.decodeIfPresent(String.self, forKey: .vendorNumber) ?? ""
    }
}

/// Display-only details about the imported service account. The key itself stays in the Keychain.
struct GoogleSettings: Codable, Equatable, Sendable {
    var serviceAccountEmail = ""
    var projectID = ""

    init(serviceAccountEmail: String = "", projectID: String = "") {
        self.serviceAccountEmail = serviceAccountEmail
        self.projectID = projectID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        serviceAccountEmail = try container.decodeIfPresent(String.self, forKey: .serviceAccountEmail) ?? ""
        projectID = try container.decodeIfPresent(String.self, forKey: .projectID) ?? ""
    }
}

struct TrackedApp: Codable, Equatable, Hashable, Identifiable, Sendable {
    /// The numeric App Store Connect app ID (Apple ID).
    var appleID: String
    var name: String
    var bundleID: String
    /// Links in-app purchases in sales reports (their Parent Identifier) to this app.
    var sku: String
    var ga4PropertyID: String
    /// Optional. Limits GA4 numbers to one data stream when a property holds several platforms.
    var ga4StreamID: String
    /// Firebase app ID such as 1:1234567890:ios:abc123.
    var firebaseAppID: String

    var id: String { appleID }

    init(appleID: String, name: String = "", bundleID: String = "", sku: String = "",
         ga4PropertyID: String = "", ga4StreamID: String = "", firebaseAppID: String = "") {
        self.appleID = appleID
        self.name = name
        self.bundleID = bundleID
        self.sku = sku
        self.ga4PropertyID = ga4PropertyID
        self.ga4StreamID = ga4StreamID
        self.firebaseAppID = firebaseAppID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appleID = try container.decode(String.self, forKey: .appleID)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        bundleID = try container.decodeIfPresent(String.self, forKey: .bundleID) ?? ""
        sku = try container.decodeIfPresent(String.self, forKey: .sku) ?? ""
        ga4PropertyID = try container.decodeIfPresent(String.self, forKey: .ga4PropertyID) ?? ""
        ga4StreamID = try container.decodeIfPresent(String.self, forKey: .ga4StreamID) ?? ""
        firebaseAppID = try container.decodeIfPresent(String.self, forKey: .firebaseAppID) ?? ""
    }

    var displayName: String {
        if !name.trimmed.isEmpty { return name }
        if !bundleID.trimmed.isEmpty { return bundleID }
        return appleID
    }

    var firebaseProjectNumber: String? { Self.projectNumber(fromFirebaseAppID: firebaseAppID) }

    func matches(_ query: String) -> Bool {
        let value = query.trimmed.lowercased()
        guard !value.isEmpty else { return false }
        return [appleID, bundleID, name, sku].contains { $0.lowercased() == value }
    }

    /// Firebase app IDs embed the project number: 1:<project number>:<platform>:<hash>.
    static func projectNumber(fromFirebaseAppID appID: String) -> String? {
        let parts = appID.trimmed.split(separator: ":")
        guard parts.count >= 4, parts[0] == "1", !parts[1].isEmpty, parts[1].allSatisfy(\.isNumber) else {
            return nil
        }
        return String(parts[1])
    }

    static func normalizedPropertyID(_ value: String) -> String {
        var property = value.trimmed
        if property.hasPrefix("properties/") { property.removeFirst("properties/".count) }
        return property
    }
}

struct ConfigurationStore: Sendable {
    let fileURL: URL

    static func standard(environment: [String: String] = ProcessInfo.processInfo.environment) -> ConfigurationStore {
        if let path = environment[EnvironmentKey.configPath]?.trimmed, !path.isEmpty {
            return ConfigurationStore(fileURL: BinnaclePaths.expand(path))
        }
        return ConfigurationStore(fileURL: BinnaclePaths.applicationSupport.appending(path: "config.json"))
    }

    func load() throws -> BinnacleConfiguration {
        let path = fileURL.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else { return BinnacleConfiguration() }
        let data = try Data(contentsOf: fileURL)
        if data.isEmpty { return BinnacleConfiguration() }
        do {
            return try JSONDecoder().decode(BinnacleConfiguration.self, from: data)
        } catch {
            throw BinnacleError.fileSystem("Could not read \(path): \(error.localizedDescription)")
        }
    }

    func save(_ configuration: BinnacleConfiguration) throws {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONCoding.encoder(pretty: true).encode(configuration).write(to: fileURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path(percentEncoded: false))
        } catch {
            throw BinnacleError.fileSystem("Could not save \(fileURL.path(percentEncoded: false)): \(error.localizedDescription)")
        }
    }
}
