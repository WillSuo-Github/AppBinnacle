import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class DashboardModel {
    static let rangeOptions = [7, 14, 30, 90]

    var configuration: BinnacleConfiguration {
        didSet {
            guard configuration != oldValue else { return }
            persistConfiguration()
        }
    }

    var selectedAppID: String? {
        didSet { UserDefaults.standard.set(selectedAppID, forKey: DefaultsKey.selectedApp) }
    }

    var rangeDays: Int {
        didSet { UserDefaults.standard.set(rangeDays, forKey: DefaultsKey.rangeDays) }
    }

    private(set) var snapshot: DashboardSnapshot?
    private(set) var brief: AppBrief?
    private(set) var isRefreshing = false
    private(set) var refreshError: String?
    var settingsMessage: String?
    private(set) var hasAppStoreConnectKey = false
    private(set) var hasServiceAccount = false
    private(set) var diagnostics: [DiagnosticResult] = []
    private(set) var isRunningDiagnostics = false
    private(set) var isImportingApps = false

    let store: ConfigurationStore
    private let secrets = KeychainSecretStore()
    private let snapshotCache = SnapshotCache.standard
    @ObservationIgnored private var refreshGeneration = 0

    init(store: ConfigurationStore = .standard()) {
        self.store = store
        var loadError: String?
        let loaded: BinnacleConfiguration
        do {
            loaded = try store.load()
        } catch {
            loaded = BinnacleConfiguration()
            loadError = error.localizedDescription
        }
        configuration = loaded
        let savedRange = UserDefaults.standard.integer(forKey: DefaultsKey.rangeDays)
        rangeDays = Self.rangeOptions.contains(savedRange) ? savedRange : 7
        let savedApp = UserDefaults.standard.string(forKey: DefaultsKey.selectedApp)
        selectedAppID = loaded.apps.contains { $0.appleID == savedApp } ? savedApp : loaded.apps.first?.appleID
        settingsMessage = loadError
        refreshSecretState()
    }

    var selectedApp: TrackedApp? {
        configuration.apps.first { $0.appleID == selectedAppID }
    }

    /// Changes whenever the dashboard should load different data.
    var selectionKey: String { "\(selectedAppID ?? "none")-\(rangeDays)" }

    func loadSelection() async {
        guard let app = selectedApp else {
            snapshot = nil
            brief = nil
            return
        }
        if let cached = snapshotCache.load(appleID: app.appleID, days: rangeDays) {
            apply(cached)
        } else {
            snapshot = nil
            brief = nil
        }
        let isStale = snapshot.map { $0.generatedAt.timeIntervalSinceNow < -3600 || $0.range.end < Day.yesterday() } ?? true
        if isStale { await refresh() }
    }

    func refresh() async {
        guard let app = selectedApp else { return }
        refreshGeneration += 1
        let generation = refreshGeneration
        isRefreshing = true
        refreshError = nil

        let configuration = configuration
        let days = rangeDays
        let credentials = await resolveCredentials(configuration)
        let snapshots = await SnapshotService(configuration: configuration, credentials: credentials)
            .snapshots(for: [app], days: days)

        guard generation == refreshGeneration else { return }
        isRefreshing = false
        if let snapshot = snapshots.first {
            apply(snapshot)
            snapshotCache.save(snapshot)
        }
        if !credentials.problems.isEmpty {
            refreshError = credentials.problems.joined(separator: "\n")
        }
    }

    // MARK: Settings

    func importAppStoreConnectKey(from url: URL) {
        do {
            let pem = try Self.readFile(url)
            try AppStoreConnectCredentials.validatePrivateKey(pem)
            try secrets.setSecret(pem, for: .appStoreConnectPrivateKey)
            if let keyID = AppStoreConnectCredentials.keyID(fromFileName: url.lastPathComponent) {
                configuration.appStoreConnect.keyID = keyID
            }
            settingsMessage = nil
        } catch {
            settingsMessage = error.localizedDescription
        }
        refreshSecretState()
    }

    func importServiceAccount(from url: URL) {
        do {
            let json = try Self.readFile(url)
            let account = try GoogleServiceAccount.parse(json)
            try secrets.setSecret(json, for: .googleServiceAccount)
            configuration.google = GoogleSettings(serviceAccountEmail: account.clientEmail, projectID: account.projectID ?? "")
            settingsMessage = nil
        } catch {
            settingsMessage = error.localizedDescription
        }
        refreshSecretState()
    }

    func removeSecret(_ item: SecretItem) {
        do {
            try secrets.removeSecret(for: item)
            if item == .googleServiceAccount { configuration.google = GoogleSettings() }
            settingsMessage = nil
        } catch {
            settingsMessage = error.localizedDescription
        }
        refreshSecretState()
    }

    func importAppsFromAppStoreConnect() async {
        isImportingApps = true
        defer { isImportingApps = false }
        let credentials = await resolveCredentials(configuration)
        guard let asc = credentials.appStoreConnect else {
            settingsMessage = credentials.problems.first ?? "Add your App Store Connect issuer ID, key ID, and private key first."
            return
        }
        do {
            let apps = try await AppStoreConnectClient(credentials: asc).apps()
            let added = configuration.mergeApps(apps)
            if selectedAppID == nil { selectedAppID = configuration.apps.first?.appleID }
            settingsMessage = "Found \(apps.count) apps in App Store Connect (\(added) new)."
        } catch {
            settingsMessage = error.localizedDescription
        }
    }

    func addApp(appleID: String) {
        let id = appleID.trimmed
        guard !id.isEmpty, id.allSatisfy(\.isNumber) else {
            settingsMessage = "The Apple ID is the numeric app ID shown in App Store Connect → App Information."
            return
        }
        if !configuration.apps.contains(where: { $0.appleID == id }) {
            configuration.apps.append(TrackedApp(appleID: id))
        }
        if selectedAppID == nil { selectedAppID = id }
        settingsMessage = nil
    }

    func removeApp(appleID: String) {
        configuration.apps.removeAll { $0.appleID == appleID }
        if selectedAppID == appleID { selectedAppID = configuration.apps.first?.appleID }
    }

    func binding(forApp appleID: String) -> Binding<TrackedApp> {
        Binding(
            get: { [weak self] in
                self?.configuration.apps.first { $0.appleID == appleID } ?? TrackedApp(appleID: appleID)
            },
            set: { [weak self] app in
                guard let self, let index = self.configuration.apps.firstIndex(where: { $0.appleID == appleID }) else { return }
                self.configuration.apps[index] = app
            })
    }

    func runDiagnostics() async {
        isRunningDiagnostics = true
        defer { isRunningDiagnostics = false }
        let configuration = configuration
        let credentials = await resolveCredentials(configuration)
        diagnostics = await Diagnostics.run(
            configuration: configuration, credentials: credentials,
            configurationPath: store.fileURL.path(percentEncoded: false))
    }

    // MARK: Private

    private func apply(_ snapshot: DashboardSnapshot) {
        self.snapshot = snapshot
        brief = BriefBuilder.make(from: snapshot)
    }

    private func refreshSecretState() {
        hasAppStoreConnectKey = secrets.contains(.appStoreConnectPrivateKey)
        hasServiceAccount = secrets.contains(.googleServiceAccount)
    }

    private func persistConfiguration() {
        do {
            try store.save(configuration)
        } catch {
            settingsMessage = error.localizedDescription
        }
    }

    /// Keychain reads can block on a permission prompt, so they run off the main thread.
    private func resolveCredentials(_ configuration: BinnacleConfiguration) async -> ResolvedCredentials {
        let secrets = secrets
        return await Task.detached {
            CredentialResolver(secrets: secrets, environment: ProcessInfo.processInfo.environment).resolve(configuration)
        }.value
    }

    private static func readFile(_ url: URL) throws -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private enum DefaultsKey {
        static let selectedApp = "selectedAppID"
        static let rangeDays = "rangeDays"
    }
}
