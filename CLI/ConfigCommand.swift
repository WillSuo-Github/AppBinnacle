import ArgumentParser
import Foundation

struct ConfigCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Show or change AppBinnacle settings.",
        subcommands: [Show.self, SetASC.self, SetGoogle.self, SetApp.self, RemoveApp.self],
        defaultSubcommand: Show.self)
}

extension ConfigCommand {
    struct Show: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "show", abstract: "Show saved settings. Secrets are never printed.")

        mutating func run() async throws {
            let context = try CLIContext.load()
            let settings = context.configuration
            let environment = ProcessInfo.processInfo.environment
            func value(_ text: String) -> String { text.trimmed.isEmpty ? "not set" : text }

            print("Configuration: \(context.configurationPath)")
            print("")
            print("App Store Connect")
            print("  Issuer ID:     \(value(settings.appStoreConnect.issuerID))")
            print("  Key ID:        \(value(settings.appStoreConnect.keyID))")
            print("  Vendor number: \(value(settings.appStoreConnect.vendorNumber))")
            print("  Private key:   \(context.secrets.contains(.appStoreConnectPrivateKey) ? "stored in Keychain" : "not imported")")
            print("")
            print("Google")
            print("  Service account: \(context.secrets.contains(.googleServiceAccount) ? value(settings.google.serviceAccountEmail) + " (Keychain)" : "not imported")")
            print("")
            print("Tracked apps (\(settings.apps.count))")
            for app in settings.apps { print("  " + AppsCommand.describe(app)) }

            let overrides = EnvironmentKey.all.filter { environment[$0]?.trimmed.isEmpty == false }
            if !overrides.isEmpty {
                print("")
                print("Environment overrides: \(overrides.joined(separator: ", "))")
            }
        }
    }

    struct SetASC: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "set-asc",
            abstract: "Save App Store Connect API settings and import the .p8 key into the Keychain.")

        @Option(help: "Issuer ID from Users and Access → Integrations.") var issuerID: String?
        @Option(help: "Key ID. Read from an AuthKey_<KEY ID>.p8 file name when omitted.") var keyID: String?
        @Option(help: "Vendor number from Payments and Financial Reports. Needed for sales reports.") var vendorNumber: String?
        @Option(help: ArgumentHelp("The .p8 key to copy into the Keychain.", valueName: "path")) var privateKey: String?

        mutating func run() async throws {
            var context = try CLIContext.load()
            if let issuerID { context.configuration.appStoreConnect.issuerID = issuerID.trimmed }
            if let keyID { context.configuration.appStoreConnect.keyID = keyID.trimmed }
            if let vendorNumber { context.configuration.appStoreConnect.vendorNumber = vendorNumber.trimmed }
            if let privateKey {
                let url = BinnaclePaths.expand(privateKey)
                let pem = try String(contentsOf: url, encoding: .utf8)
                try AppStoreConnectCredentials.validatePrivateKey(pem)
                try context.secrets.setSecret(pem, for: .appStoreConnectPrivateKey)
                if keyID == nil, let inferred = AppStoreConnectCredentials.keyID(fromFileName: url.lastPathComponent) {
                    context.configuration.appStoreConnect.keyID = inferred
                }
                print("Stored the private key in the Keychain.")
            }
            try context.save()
            print("Saved App Store Connect settings to \(context.configurationPath).")
        }
    }

    struct SetGoogle: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "set-google",
            abstract: "Import a Google service account key (JSON) into the Keychain.")

        @Option(help: ArgumentHelp("The service account key file.", valueName: "path")) var serviceAccount: String

        mutating func run() async throws {
            var context = try CLIContext.load()
            let json = try String(contentsOf: BinnaclePaths.expand(serviceAccount), encoding: .utf8)
            let account = try GoogleServiceAccount.parse(json)
            try context.secrets.setSecret(json, for: .googleServiceAccount)
            context.configuration.google = GoogleSettings(serviceAccountEmail: account.clientEmail, projectID: account.projectID ?? "")
            try context.save()
            print("Stored \(account.clientEmail) in the Keychain.")
            print("Grant it Viewer access on each GA4 property and the Firebase Crashlytics Viewer role in your Firebase project.")
        }
    }

    struct SetApp: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "set-app",
            abstract: "Track an app, or update the settings of a tracked app.")

        @Argument(help: "The app's Apple ID (App Store Connect → App Information).") var appleID: String
        @Option(help: "Display name.") var name: String?
        @Option(help: "Bundle ID.") var bundleID: String?
        @Option(help: "SKU, used to attribute in-app purchases.") var sku: String?
        @Option(help: "GA4 property ID, for example 123456789.") var ga4Property: String?
        @Option(help: "GA4 data stream ID, when the property holds several apps or platforms.") var ga4Stream: String?
        @Option(help: "Firebase app ID, for example 1:1234567890:ios:abc123.") var firebaseAppID: String?

        func validate() throws {
            guard !appleID.isEmpty, appleID.allSatisfy(\.isNumber) else {
                throw ValidationError("The Apple ID is the numeric app ID, such as 1234567890.")
            }
            if let ga4Property, !TrackedApp.normalizedPropertyID(ga4Property).allSatisfy(\.isNumber) {
                throw ValidationError("--ga4-property should be numeric, such as 123456789.")
            }
            if let firebaseAppID, !firebaseAppID.isEmpty, TrackedApp.projectNumber(fromFirebaseAppID: firebaseAppID) == nil {
                throw ValidationError("--firebase-app-id should look like 1:1234567890:ios:abc123.")
            }
        }

        mutating func run() async throws {
            var context = try CLIContext.load()
            var app = context.configuration.apps.first { $0.appleID == appleID } ?? TrackedApp(appleID: appleID)
            let isNew = !context.configuration.apps.contains { $0.appleID == appleID }

            if isNew, name == nil || bundleID == nil, let asc = context.credentials().appStoreConnect {
                do {
                    let remote = try await AppStoreConnectClient(credentials: asc).app(id: appleID)
                    app.name = remote.name
                    app.bundleID = remote.bundleID
                    app.sku = remote.sku
                } catch {
                    Console.warn("Could not look up the app in App Store Connect: \(error.localizedDescription)")
                }
            }
            if let name { app.name = name.trimmed }
            if let bundleID { app.bundleID = bundleID.trimmed }
            if let sku { app.sku = sku.trimmed }
            if let ga4Property { app.ga4PropertyID = TrackedApp.normalizedPropertyID(ga4Property) }
            if let ga4Stream { app.ga4StreamID = ga4Stream.trimmed }
            if let firebaseAppID { app.firebaseAppID = firebaseAppID.trimmed }

            if let index = context.configuration.apps.firstIndex(where: { $0.appleID == appleID }) {
                context.configuration.apps[index] = app
            } else {
                context.configuration.apps.append(app)
            }
            try context.save()
            print((isNew ? "Tracking " : "Updated ") + AppsCommand.describe(app))
        }
    }

    struct RemoveApp: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "remove-app", abstract: "Stop tracking an app.")

        @Argument(help: "Apple ID, bundle ID, SKU, or name.") var app: String

        mutating func run() async throws {
            var context = try CLIContext.load()
            guard let match = context.configuration.app(matching: app) else {
                throw ValidationError("No tracked app matches \"\(app)\".")
            }
            context.configuration.apps.removeAll { $0.appleID == match.appleID }
            try context.save()
            print("Stopped tracking \(match.displayName).")
        }
    }
}
