import Foundation

struct DiagnosticResult: Identifiable, Equatable, Sendable {
    enum Status: String, Sendable {
        case passed
        case warning
        case failed
    }

    var id: Int
    var title: String
    var status: Status
    var detail: String
}

/// Checks each configured connection with the smallest request that proves it works.
enum Diagnostics {
    static func run(configuration: BinnacleConfiguration, credentials: ResolvedCredentials, configurationPath: String,
                    transport: any HTTPTransport = URLSessionTransport(), now: Date = Date()) async -> [DiagnosticResult] {
        var results: [DiagnosticResult] = []
        func add(_ title: String, _ status: DiagnosticResult.Status, _ detail: String) {
            results.append(DiagnosticResult(id: results.count, title: title, status: status, detail: detail))
        }

        add("Configuration", configuration.apps.isEmpty ? .warning : .passed,
            configuration.apps.isEmpty
                ? "No apps are tracked yet. Configuration file: \(configurationPath)"
                : "\(configuration.apps.count) tracked app\(configuration.apps.count == 1 ? "" : "s"). Configuration file: \(configurationPath)")
        for problem in credentials.problems {
            add("Credentials", .failed, problem)
        }

        let today = Day(date: now, timeZone: .appStoreReporting)
        if let asc = credentials.appStoreConnect {
            let client = AppStoreConnectClient(credentials: asc, transport: transport)
            do {
                let apps = try await client.apps()
                add("App Store Connect API", .passed, "Signed in. The key can see \(apps.count) app\(apps.count == 1 ? "" : "s").")
            } catch {
                add("App Store Connect API", .failed, error.localizedDescription)
            }
            if asc.vendorNumber.isEmpty {
                add("Sales reports", .warning, "Add your vendor number to load downloads and proceeds.")
            } else {
                let day = today.adding(days: -4)
                do {
                    let report = try await client.dailySalesReport(vendorNumber: asc.vendorNumber, day: day)
                    add("Sales reports", .passed, report == .noSales ? "Reachable (no sales on \(day.iso))." : "Downloaded the report for \(day.iso).")
                } catch {
                    add("Sales reports", .failed, error.localizedDescription)
                }
            }
        } else if !credentials.problems.contains(where: { $0.contains("App Store Connect") }) {
            add("App Store Connect API", .warning, "Not configured.")
        }

        if let account = credentials.google {
            let tokens = GoogleAccessTokenProvider(account: account, transport: transport)
            do {
                _ = try await tokens.accessToken()
                add("Google service account", .passed, "Signed in as \(account.clientEmail).")
                let range = DayRange(ending: today.adding(days: -1), length: 7)
                for app in configuration.apps {
                    if !app.ga4PropertyID.trimmed.isEmpty {
                        do {
                            let users = try await AnalyticsClient(tokens: tokens, transport: transport)
                                .activeUsers(propertyID: app.ga4PropertyID, streamID: app.ga4StreamID, range: range)
                            add("\(app.displayName): Google Analytics", .passed, "\(Format.integer(users)) active users in the last 7 days.")
                        } catch {
                            add("\(app.displayName): Google Analytics", .failed, error.localizedDescription)
                        }
                    }
                    if !app.firebaseAppID.trimmed.isEmpty {
                        do {
                            let issues = try await CrashlyticsClient(tokens: tokens, transport: transport)
                                .topOpenIssues(firebaseAppID: app.firebaseAppID, range: range, limit: 1, now: now)
                            add("\(app.displayName): Crashlytics", .passed, issues.isEmpty ? "Reachable (no open issues this week)." : "Reachable.")
                        } catch {
                            add("\(app.displayName): Crashlytics", .failed, error.localizedDescription)
                        }
                    }
                }
            } catch {
                add("Google service account", .failed, error.localizedDescription)
            }
        } else if !credentials.problems.contains(where: { $0.contains("Google") }) {
            add("Google service account", .warning, "Not configured.")
        }
        return results
    }
}
