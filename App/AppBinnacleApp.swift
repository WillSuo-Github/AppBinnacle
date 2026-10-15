import SwiftUI

@main
struct AppBinnacleApp: App {
    @State private var model = DashboardModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .tint(Color.accentColor)
                .frame(minWidth: 960, minHeight: 640)
        }
        .defaultSize(width: 1200, height: 820)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Refresh Data") {
                    Task { await model.refresh() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.configuration.apps.isEmpty || model.isRefreshing)
            }

            CommandGroup(after: .sidebar) {
                Button("Back") {
                    model.pop()
                }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(model.navigationPath.isEmpty)
            }
        }

        Settings {
            SettingsView()
                .environment(model)
                .tint(Color.accentColor)
        }
    }
}
