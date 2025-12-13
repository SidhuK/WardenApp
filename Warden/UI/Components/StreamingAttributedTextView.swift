import AppKit
import SwiftUI

struct StreamingAttributedTextView: NSViewRepresentable {
    let attributedString: NSAttributedString

    func makeNSView(context: Context) -> AutoSizingTextView {
        let textView = AutoSizingTextView()
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.allowsUndo = false
        textView.textContainerInset = .zero

        if let textContainer = textView.textContainer {
            textContainer.lineFragmentPadding = 0
            textContainer.widthTracksTextView = true
            textContainer.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        }

        textView.textStorage?.setAttributedString(attributedString)
        return textView
    }

    func updateNSView(_ nsView: AutoSizingTextView, context: Context) {
        nsView.setAttributedStringIfNeeded(attributedString)
    }

    final class AutoSizingTextView: NSTextView {
        override var intrinsicContentSize: NSSize {
            guard let layoutManager = layoutManager, let textContainer = textContainer else {
                return NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
            }

            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            let height = usedRect.height + textContainerInset.height * 2
            return NSSize(width: NSView.noIntrinsicMetric, height: max(1, height))
        }

        override func layout() {
            super.layout()
            guard let textContainer else { return }
            let width = max(0, bounds.width)
            if textContainer.containerSize.width != width {
                textContainer.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
                invalidateIntrinsicContentSize()
            }
        }

        func setAttributedStringIfNeeded(_ newValue: NSAttributedString) {
            guard let textStorage else { return }

            if textStorage.length == newValue.length, textStorage.string == newValue.string {
                if textStorage.length == 0 {
                    return
                }

                let currentFont = textStorage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
                let newFont = newValue.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
                let currentColor = textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
                let newColor = newValue.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor

                if currentFont == newFont, currentColor == newColor {
                    return
                }
            }

            textStorage.setAttributedString(newValue)
            invalidateIntrinsicContentSize()
        }
    }
}
