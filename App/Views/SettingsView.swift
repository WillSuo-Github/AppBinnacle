import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            AccountsSettingsView()
                .tabItem { Label("Accounts", systemImage: "key") }
            AppsSettingsView()
                .tabItem { Label("Apps", systemImage: "square.stack.3d.up") }
        }
        .frame(width: 680, height: 600)
    }
}

private struct GeneralSettingsView: View {
    @Environment(DashboardModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Picker("Sync Interval", selection: $model.autoRefreshInterval) {
                    ForEach(AutoRefreshInterval.allCases) { interval in
                        Text(interval.title).tag(interval)
                    }
                }
                .help("How frequently AppBinnacle updates data in the background")

                Toggle("Refresh automatically when waking or activating app", isOn: $model.refreshOnActivation)
                    .help("Automatically pulls fresh metrics if data is stale when returning to AppBinnacle")
            } header: {
                Text("Automatic Background Refresh")
            } footer: {
                Text("AppBinnacle periodically syncs App Store Connect and Firebase in the background while complying with Apple and Google API rate limits.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Cache Directory") {
                    Text(BinnaclePaths.caches.path(percentEncoded: false))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                LabeledContent("Config Path") {
                    Text(model.store.fileURL.path(percentEncoded: false))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            } header: {
                Text("Data Storage & Cache")
            } footer: {
                Text("Private keys and tokens remain encrypted in your macOS Keychain service dev.appbinnacle.credentials.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AccountsSettingsView: View {
    @Environment(DashboardModel.self) private var model
    @State private var isImporting = false
    @State private var importTarget = SecretItem.appStoreConnectPrivateKey

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                TextField("Issuer ID", text: $model.configuration.appStoreConnect.issuerID, prompt: Text("xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"))
                TextField("Key ID", text: $model.configuration.appStoreConnect.keyID, prompt: Text("ABC123DEFG"))
                TextField("Vendor Number", text: $model.configuration.appStoreConnect.vendorNumber, prompt: Text("Needed for sales reports"))
                LabeledContent("Private Key") {
                    HStack {
                        Text(model.hasAppStoreConnectKey ? "Stored in Keychain" : "Not imported")
                            .foregroundStyle(model.hasAppStoreConnectKey ? Color.primary : Color.secondary)
                        Button(model.hasAppStoreConnectKey ? "Replace…" : "Import .p8…") {
                            importTarget = .appStoreConnectPrivateKey
                            isImporting = true
                        }
                        if model.hasAppStoreConnectKey {
                            Button("Remove", role: .destructive) { model.removeSecret(.appStoreConnectPrivateKey) }
                        }
                    }
                }
            } header: {
                Text("App Store Connect")
            } footer: {
                Text("Create a team API key in App Store Connect → Users and Access → Integrations. Sales reports need the Sales, Finance, or Admin role. The vendor number is under Payments and Financial Reports.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Service Account") {
                    HStack {
                        Text(model.hasServiceAccount ? (model.configuration.google.serviceAccountEmail.isEmpty ? "Stored in Keychain" : model.configuration.google.serviceAccountEmail) : "Not imported")
                            .foregroundStyle(model.hasServiceAccount ? Color.primary : Color.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        Button(model.hasServiceAccount ? "Replace…" : "Import JSON…") {
                            importTarget = .googleServiceAccount
                            isImporting = true
                        }
                        if model.hasServiceAccount {
                            Button("Remove", role: .destructive) { model.removeSecret(.googleServiceAccount) }
                        }
                    }
                }
            } header: {
                Text("Firebase & Google Analytics")
            } footer: {
                Text("Add the service account as a Viewer on each GA4 property, and give it the Firebase Crashlytics Viewer role in your Firebase project. Enable the Google Analytics Data API and the Firebase Crashlytics API for its Google Cloud project.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Connection Check") {
                HStack {
                    Button("Check Connections") {
                        Task { await model.runDiagnostics() }
                    }
                    .disabled(model.isRunningDiagnostics)
                    if model.isRunningDiagnostics {
                        ProgressView().controlSize(.small)
                    }
                }
                ForEach(model.diagnostics) { result in
                    DiagnosticRow(result: result)
                }
            }

            if let message = model.settingsMessage {
                Section {
                    Label(message, systemImage: "info.circle")
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: importTarget == .googleServiceAccount ? [.json] : [.data, .item]) { result in
            switch result {
            case .success(let url):
                if importTarget == .googleServiceAccount {
                    model.importServiceAccount(from: url)
                } else {
                    model.importAppStoreConnectKey(from: url)
                }
            case .failure(let error):
                model.settingsMessage = error.localizedDescription
            }
        }
    }
}

private struct DiagnosticRow: View {
    let result: DiagnosticResult

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                Text(result.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private var symbol: String {
        switch result.status {
        case .passed: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.circle"
        case .failed: return "xmark.octagon.fill"
        }
    }

    private var color: Color {
        switch result.status {
        case .passed: return .green
        case .warning: return .orange
        case .failed: return .red
        }
    }
}

private struct AppsSettingsView: View {
    @Environment(DashboardModel.self) private var model
    @State private var selection: String?
    @State private var isAddingApp = false
    @State private var newAppleID = ""

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(model.configuration.apps) { app in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.displayName)
                            Text(app.bundleID.isEmpty ? app.appleID : app.bundleID)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(app.appleID)
                    }
                }
                .listStyle(.sidebar)

                Divider()

                HStack(spacing: 4) {
                    Menu {
                        Button("Import from App Store Connect") {
                            Task { await model.importAppsFromAppStoreConnect() }
                        }
                        Button("Add by Apple ID…") { isAddingApp = true }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Add apps")

                    Button {
                        if let selection { model.removeApp(appleID: selection) }
                        selection = model.configuration.apps.first?.appleID
                    } label: {
                        Image(systemName: "minus")
                    }
                    .disabled(selection == nil)
                    .help("Stop tracking the selected app")

                    Spacer()
                    if model.isImportingApps { ProgressView().controlSize(.small) }
                }
                .buttonStyle(.borderless)
                .padding(8)
            }
            .frame(width: 220)

            Divider()

            if let selection, model.configuration.apps.contains(where: { $0.appleID == selection }) {
                AppEditor(app: model.binding(forApp: selection))
            } else {
                ContentUnavailableView {
                    Label("No App Selected", systemImage: "app.dashed")
                } description: {
                    Text(model.settingsMessage ?? "Import your apps from App Store Connect, or add one by its Apple ID.")
                } actions: {
                    Button("Import from App Store Connect") {
                        Task { await model.importAppsFromAppStoreConnect() }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if selection == nil { selection = model.selectedAppID ?? model.configuration.apps.first?.appleID }
        }
        .sheet(isPresented: $isAddingApp) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Add an App").font(.headline)
                Text("Enter the numeric Apple ID from App Store Connect → App Information.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                TextField("Apple ID", text: $newAppleID, prompt: Text("1234567890"))
                    .onSubmit(addApp)
                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) { isAddingApp = false }
                    Button("Add", action: addApp)
                        .keyboardShortcut(.defaultAction)
                        .disabled(newAppleID.trimmed.isEmpty)
                }
            }
            .padding(20)
            .frame(width: 360)
        }
    }

    private func addApp() {
        model.addApp(appleID: newAppleID)
        selection = newAppleID.trimmed
        newAppleID = ""
        isAddingApp = false
    }
}

private struct AppEditor: View {
    @Binding var app: TrackedApp

    var body: some View {
        Form {
            Section("App Store") {
                TextField("Name", text: $app.name)
                TextField("Bundle ID", text: $app.bundleID)
                LabeledContent("Apple ID", value: app.appleID)
                TextField("SKU", text: $app.sku, prompt: Text("Links in-app purchases to this app"))
            }
            Section {
                TextField("Property ID", text: $app.ga4PropertyID, prompt: Text("123456789"))
                TextField("Stream ID", text: $app.ga4StreamID, prompt: Text("Optional"))
            } header: {
                Text("Google Analytics")
            } footer: {
                Text("Find the property ID in Google Analytics → Admin → Property details. Set a stream ID when the property also holds other platforms.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                TextField("Firebase App ID", text: $app.firebaseAppID, prompt: Text("1:1234567890:ios:abc123"))
            } header: {
                Text("Crashlytics")
            } footer: {
                Text("Find it in Firebase → Project settings → Your apps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
