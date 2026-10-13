import SwiftUI

@main
struct AppBinnacleApp: App {
    @State private var model = DashboardModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .frame(minWidth: 940, minHeight: 620)
        }
        .defaultSize(width: 1180, height: 800)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Refresh Data") {
                    Task { await model.refresh() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.selectedApp == nil || model.isRefreshing)
            }
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}
