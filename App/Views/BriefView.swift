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

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    didCopy = true
                } label: {
                    Label(didCopy ? "Copied to Clipboard" : "Copy for AI", systemImage: didCopy ? "checkmark" : "doc.on.doc")
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

            HStack(spacing: 8) {
                Image(systemName: "terminal.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(terminalCommand)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
        .onChange(of: format) { didCopy = false }
        .onChange(of: brief) { didCopy = false }
    }

    private var terminalCommand: String {
        if model.isAllApps {
            return "Terminal CLI: binnacle brief --days \(snapshot.range.length)"
        } else {
            let appIdentifier = snapshot.app.bundleID.isEmpty ? snapshot.app.appleID : snapshot.app.bundleID
            return "Terminal CLI: binnacle brief --app \(appIdentifier) --days \(snapshot.range.length)"
        }
    }

    private var rendered: String {
        let briefsToRender = model.isAllApps && !model.loadedSnapshots.isEmpty
            ? model.loadedSnapshots.map { BriefBuilder.make(from: $0) }
            : [brief]
        return (try? BriefRenderer.render(briefsToRender, format: format)) ?? "The brief could not be rendered."
    }
}
