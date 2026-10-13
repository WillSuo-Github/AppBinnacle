import ArgumentParser
import Foundation

@main
struct BinnacleCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "binnacle",
        abstract: "Summarize App Store Connect and Firebase data about your apps.",
        discussion: """
        Credentials saved by the AppBinnacle app are read from your login Keychain. For scripts and \
        AI agents, these environment variables override saved settings:
          BINNACLE_ASC_ISSUER_ID, BINNACLE_ASC_KEY_ID, BINNACLE_ASC_VENDOR_NUMBER,
          BINNACLE_ASC_PRIVATE_KEY_PATH, BINNACLE_GOOGLE_SERVICE_ACCOUNT_PATH, BINNACLE_CONFIG
        """,
        version: BinnacleVersion.string,
        subcommands: [
            BriefCommand.self,
            SnapshotCommand.self,
            AppsCommand.self,
            ConfigCommand.self,
            DoctorCommand.self,
        ],
        defaultSubcommand: BriefCommand.self)
}

extension BriefFormat: ExpressibleByArgument {}

extension Day: ExpressibleByArgument {
    init?(argument: String) {
        self.init(iso: argument)
    }
}

struct ReportOptions: ParsableArguments {
    @Option(name: .shortAndLong, help: "Apple ID, bundle ID, SKU, or name of a tracked app. Defaults to every tracked app.")
    var app: String?

    @Option(name: .shortAndLong, help: "Number of days in the period (1-90). It is compared with the same number of days before it.")
    var days: Int = 7

    @Option(help: ArgumentHelp("Last day of the period. Defaults to yesterday in Pacific Time.", valueName: "yyyy-MM-dd"))
    var end: Day?

    @Flag(help: "Download sales reports again instead of reading the local cache.")
    var noCache = false

    func validate() throws {
        guard (1...90).contains(days) else { throw ValidationError("--days must be between 1 and 90.") }
    }
}

/// Saved configuration plus credential lookup, shared by every subcommand.
struct CLIContext {
    var store: ConfigurationStore
    var configuration: BinnacleConfiguration
    var secrets = KeychainSecretStore()

    static func load() throws -> CLIContext {
        let store = ConfigurationStore.standard()
        return CLIContext(store: store, configuration: try store.load())
    }

    var configurationPath: String { store.fileURL.path(percentEncoded: false) }

    func credentials(reportProblems: Bool = true) -> ResolvedCredentials {
        let credentials = CredentialResolver(secrets: secrets).resolve(configuration)
        if reportProblems {
            for problem in credentials.problems { Console.warn(problem) }
        }
        return credentials
    }

    func apps(matching query: String?) throws -> [TrackedApp] {
        guard !configuration.apps.isEmpty else {
            throw ValidationError("No apps are tracked yet. Run 'binnacle apps --import' or 'binnacle config set-app <apple-id>' first.")
        }
        guard let query, !query.trimmed.isEmpty else { return configuration.apps }
        guard let app = configuration.app(matching: query) else {
            let known = configuration.apps.map { "\($0.displayName) (\($0.appleID))" }.joined(separator: ", ")
            throw ValidationError("No tracked app matches \"\(query)\". Tracked apps: \(known)")
        }
        return [app]
    }

    func save() throws {
        try store.save(configuration)
    }
}

enum Console {
    static func warn(_ message: String) {
        write("warning: \(message)")
    }

    static func error(_ message: String) {
        write("error: \(message)")
    }

    /// Flushes stdout first so messages stay in order when both streams go to the same place.
    private static func write(_ line: String) {
        fflush(stdout)
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }
}
