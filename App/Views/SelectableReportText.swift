import AppKit
import SwiftUI

enum ReportTextMenuItem {
    case action(String, symbol: String, selected: Bool = false, enabled: Bool = true, perform: @MainActor () -> Void)
    case submenu(String, items: [ReportTextMenuItem])
    case separator
}

/// NSTextView keeps text selection while allowing report actions in its native menu.
struct SelectableReportText: NSViewRepresentable {
    let text: String
    let menuItems: [ReportTextMenuItem]

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay

        let textView = ReportTextView(frame: scrollView.contentView.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.font = .monospacedSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .callout).pointSize, weight: .regular)
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 20, height: 20)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView
        updateNSView(scrollView, context: context)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ReportTextView else { return }
        if textView.string != text { textView.string = text }
        textView.reportMenuItems = menuItems
    }
}

private final class ReportTextView: NSTextView {
    var reportMenuItems: [ReportTextMenuItem] = []
    private var menuTargets: [ReportMenuTarget] = []

    override func menu(for event: NSEvent) -> NSMenu? {
        window?.makeFirstResponder(self)
        menuTargets.removeAll()
        let menu = makeMenu(reportMenuItems)
        menu.addItem(.separator())
        let copySelection = NSMenuItem(title: "Copy Selected Text", action: #selector(copy(_:)), keyEquivalent: "")
        copySelection.target = self
        copySelection.isEnabled = selectedRange().length > 0
        menu.addItem(copySelection)
        let selectAll = NSMenuItem(title: "Select All", action: #selector(selectAll(_:)), keyEquivalent: "")
        selectAll.target = self
        menu.addItem(selectAll)
        return menu
    }

    private func makeMenu(_ items: [ReportTextMenuItem]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for item in items {
            switch item {
            case let .action(title, symbol, selected, enabled, perform):
                let target = ReportMenuTarget(perform: perform)
                menuTargets.append(target)
                let menuItem = NSMenuItem(title: title, action: #selector(ReportMenuTarget.invoke(_:)), keyEquivalent: "")
                menuItem.target = target
                menuItem.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
                menuItem.state = selected ? .on : .off
                menuItem.isEnabled = enabled
                menu.addItem(menuItem)
            case let .submenu(title, children):
                let menuItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                menuItem.submenu = makeMenu(children)
                menu.addItem(menuItem)
            case .separator:
                menu.addItem(.separator())
            }
        }
        return menu
    }
}

private final class ReportMenuTarget: NSObject {
    let perform: @MainActor () -> Void

    init(perform: @escaping @MainActor () -> Void) {
        self.perform = perform
    }

    @MainActor @objc func invoke(_ sender: NSMenuItem) { perform() }
}
