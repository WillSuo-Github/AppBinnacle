import AppKit
import SwiftUI

struct BriefView: View {
    let snapshot: DashboardSnapshot
    let brief: AppBrief
    @Environment(DashboardModel.self) private var model
    @State private var format = BriefFormat.markdown
    @State private var didCopy = false

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

                if model.isAllApps {
                    Text("All \(model.configuration.apps.count) Apps Briefing")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                #if os(macOS)
                Button {
                    let ext = format == .markdown ? "md" : (format == .json ? "json" : "csv")
                    let title = model.isAllApps ? "AllApps" : snapshot.app.displayName.replacingOccurrences(of: " ", with: "_")
                    let filename = "AppBinnacle-\(title)-\(snapshot.range.shortLabel).\(ext)"
                    SaveFileDialog.save(filename: filename, content: text)
                } label: {
                    Label("Export to File…", systemImage: "arrow.down.doc")
                }
                .buttonStyle(.bordered)
                .help("Save report directly to disk as a file")
                #endif

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    didCopy = true
                } label: {
                    Label(didCopy ? "Copied" : "Copy to Clipboard", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("c", modifiers: [.command, .shift])
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            ScrollView {
                Text(text)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
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

    private var terminalCommand: String {
        let fmt = format.rawValue
        if model.isAllApps {
            return "binnacle brief --days \(snapshot.range.length) --format \(fmt)"
        } else {
            let appIdentifier = snapshot.app.bundleID.isEmpty ? snapshot.app.appleID : snapshot.app.bundleID
            return "binnacle brief --app \(appIdentifier) --days \(snapshot.range.length) --format \(fmt)"
        }
    }

    private var rendered: String {
        let briefsToRender = model.isAllApps && !model.loadedSnapshots.isEmpty
            ? model.loadedSnapshots.map { BriefBuilder.make(from: $0) }
            : [brief]
        return (try? BriefRenderer.render(briefsToRender, format: format)) ?? "The brief could not be rendered."
    }
}
