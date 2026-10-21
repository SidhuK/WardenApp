import AppKit
import SwiftUI

/// Watches for text selected in the chat transcript and offers "Quote in Reply", "Explain" and "Copy" next to it.
/// Reply text is drawn by several kinds of read-only text views, so this looks at the window's first responder
/// after each mouse-up instead of hooking into each of them.
struct SelectionActionMonitor: NSViewRepresentable {
    let onQuote: (String) -> Void
    let onExplain: (String) -> Void

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.onQuote = onQuote
        view.onExplain = onExplain
        return view
    }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.onQuote = onQuote
        view.onExplain = onExplain
    }

    static func dismantleNSView(_ view: MonitorView, coordinator: ()) {
        view.stopMonitoring()
    }

    final class MonitorView: NSView {
        var onQuote: ((String) -> Void)?
        var onExplain: ((String) -> Void)?

        private var monitor: Any?
        private var popover: NSPopover?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
                if let self, event.window === self.window {
                    let location = event.locationInWindow
                    // Let the text view finish updating its selection first.
                    DispatchQueue.main.async { [weak self] in
                        self?.showActionsForCurrentSelection(mouseUpAt: location)
                    }
                }
                return event
            }
        }

        func stopMonitoring() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
            popover?.close()
            popover = nil
        }

        private func showActionsForCurrentSelection(mouseUpAt location: NSPoint) {
            guard let window,
                  let textView = window.firstResponder as? NSTextView,
                  !textView.isEditable,
                  textView.isSelectable
            else {
                return
            }

            let range = textView.selectedRange()
            let string = textView.string as NSString
            guard range.length > 0, NSMaxRange(range) <= string.length else {
                popover?.close()
                return
            }
            let selection = string.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !selection.isEmpty else { return }

            // A click elsewhere leaves the text view's selection (and first-responder status) intact, so only a
            // mouse-up on the text itself (with some slack for drags past its edge) counts as a new selection.
            let mouseUpPoint = textView.convert(location, from: nil)
            guard textView.visibleRect.insetBy(dx: -16, dy: -16).contains(mouseUpPoint) else { return }

            // Only selections inside the transcript this monitor covers.
            let transcriptFrame = convert(bounds, to: nil)
            let textFrame = textView.convert(textView.visibleRect, to: nil)
            guard transcriptFrame.intersects(textFrame) else { return }

            let screenRect = textView.firstRect(forCharacterRange: range, actualRange: nil)
            guard screenRect.width > 0 || screenRect.height > 0 else { return }
            let anchor = textView.convert(window.convertFromScreen(screenRect), from: nil)
                .intersection(textView.visibleRect)
            guard !anchor.isNull, !anchor.isEmpty else { return }

            show(for: selection, relativeTo: anchor, of: textView)
        }

        private func show(for selection: String, relativeTo rect: NSRect, of textView: NSTextView) {
            popover?.close()

            let popover = NSPopover()
            popover.behavior = .transient
            popover.animates = true
            let content = SelectionActionsView(
                onQuote: { [weak self] in
                    self?.dismissPopover()
                    self?.onQuote?(selection)
                },
                onExplain: { [weak self] in
                    self?.dismissPopover()
                    self?.onExplain?(selection)
                },
                onCopy: { [weak self] in
                    self?.dismissPopover()
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(selection, forType: .string)
                }
            )
            let host = NSHostingController(rootView: content)
            popover.contentViewController = host
            popover.contentSize = host.view.fittingSize
            popover.show(relativeTo: rect, of: textView, preferredEdge: textView.isFlipped ? .minY : .maxY)
            self.popover = popover
        }

        private func dismissPopover() {
            popover?.close()
            popover = nil
        }
    }
}

private struct SelectionActionsView: View {
    let onQuote: () -> Void
    let onExplain: () -> Void
    let onCopy: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            actionButton("Quote in Reply", icon: "text.quote", action: onQuote)
            actionButton("Explain", icon: "questionmark.bubble", action: onExplain)
            actionButton("Copy", icon: "doc.on.doc", action: onCopy)
        }
        .padding(4)
    }

    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }
}
