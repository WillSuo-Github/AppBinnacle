import AppKit
import SwiftUI

struct BriefView: View {
    let snapshot: DashboardSnapshot
    let brief: AppBrief
    @Environment(DashboardModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @State private var format = BriefFormat.markdown
    @State private var didCopy = false

    private var isPortfolio: Bool {
        snapshot.app.appleID == DashboardModel.allAppsID
    }

    var body: some View {
        let text = rendered

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Picker("Format", selection: $format) {
                    Text("Markdown").tag(BriefFormat.markdown)
                    Text("JSON").tag(BriefFormat.json)
                    Text("CSV Table").tag(BriefFormat.csv)
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .labelsHidden()

                if isPortfolio {
                    Text("All \(model.configuration.apps.count) Apps Briefing")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                #if os(macOS)
                Button {
                    exportReport()
                } label: {
                    Label("Export to File…", systemImage: "arrow.down.doc")
                }
                .buttonStyle(.bordered)
                .help("Save report directly to disk as a file")
                #endif

                Button {
                    copyReport()
                } label: {
                    Label(didCopy ? "Copied" : "Copy to Clipboard", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("c", modifiers: [.command, .shift])
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            CurrencyConversionNote()
                .padding(.horizontal, 24)

            SelectableReportText(text: text, menuItems: [
                .action("Copy Report", symbol: "doc.on.doc", perform: copyReport),
                .action("Export Report…", symbol: "arrow.down.doc", perform: exportReport),
                .submenu("Format", items: BriefFormat.allCases.map { choice in
                    .action(choice == .csv ? "CSV Table" : (choice == .json ? "JSON" : "Markdown"), symbol: "doc.text", selected: choice == format) {
                        format = choice
                    }
                }),
                .action("Copy CLI Command", symbol: "terminal") { Clipboard.copy(terminalCommand) },
                .separator,
                .action("Refresh Data", symbol: "arrow.clockwise", enabled: !model.isRefreshing && !model.configuration.apps.isEmpty) {
                    Task { await model.refresh() }
                },
                .action("Settings…", symbol: "gearshape") { openSettings() }
            ])
            .appleCard(cornerRadius: 14)
            .padding(.horizontal, 24)

            HStack(spacing: 12) {
                Image(systemName: "terminal.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(terminalCommand)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .contextMenu {
                        CopyMenuItem(title: "Copy CLI Command", text: terminalCommand)
                    }

                Spacer()

                Text("\(text.count) characters · ~\(max(1, text.count / 4)) AI tokens")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
        .onChange(of: format) { didCopy = false }
        .onChange(of: brief) { didCopy = false }
    }

    private func copyReport() {
        Clipboard.copy(rendered)
        didCopy = true
    }

    private func exportReport() {
        let ext = format == .markdown ? "md" : (format == .json ? "json" : "csv")
        let title = isPortfolio ? "AllApps" : snapshot.app.displayName.replacingOccurrences(of: " ", with: "_")
        SaveFileDialog.save(filename: "AppBinnacle-\(title)-\(snapshot.range.shortLabel).\(ext)", content: rendered)
    }

    private var terminalCommand: String {
        let fmt = format.rawValue
        if isPortfolio {
            return "binnacle brief --days \(snapshot.range.length) --format \(fmt)"
        } else {
            let appIdentifier = snapshot.app.bundleID.isEmpty ? snapshot.app.appleID : snapshot.app.bundleID
            return "binnacle brief --app \(appIdentifier) --days \(snapshot.range.length) --format \(fmt)"
        }
    }

    private var rendered: String {
        let briefsToRender = isPortfolio && !model.loadedSnapshots.isEmpty
            ? model.loadedSnapshots.map { model.displayBrief(BriefBuilder.make(from: $0)) }
            : [model.displayBrief(brief)]
        return (try? BriefRenderer.render(briefsToRender, format: format)) ?? "The brief could not be rendered."
    }
}
