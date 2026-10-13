import AppKit
import SwiftUI

struct BriefView: View {
    let snapshot: DashboardSnapshot
    let brief: AppBrief
    @State private var format = BriefFormat.markdown
    @State private var didCopy = false

    var body: some View {
        let text = rendered

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Picker("Format", selection: $format) {
                    Text("Markdown").tag(BriefFormat.markdown)
                    Text("JSON").tag(BriefFormat.json)
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .labelsHidden()

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    didCopy = true
                } label: {
                    Label(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                Text(text)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }

            Divider()

            Text("From Terminal: binnacle brief --app \(snapshot.app.bundleID.isEmpty ? snapshot.app.appleID : snapshot.app.bundleID) --days \(snapshot.range.length)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
        }
        .onChange(of: format) { didCopy = false }
        .onChange(of: brief) { didCopy = false }
    }

    private var rendered: String {
        (try? BriefRenderer.render([brief], format: format)) ?? "The brief could not be rendered."
    }
}
