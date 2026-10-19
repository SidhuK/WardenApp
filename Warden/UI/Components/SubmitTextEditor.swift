import SwiftUI
import AppKit

struct SubmitTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var dynamicHeight: CGFloat
    var focusToken: Int = 0
    var onSubmit: () -> Void
    var font: NSFont = .systemFont(ofSize: 14)
    var maxHeight: CGFloat = 160
    /// Plain-text pastes with more lines than this are offered to `onLongPaste` instead of being inserted;
    /// the handler returns `false` to fall back to a normal paste. 0 disables the behaviour.
    var longPasteLineThreshold: Int = 0
    var onLongPaste: ((String) -> Bool)?
    /// While its menu is visible, arrow keys, Return, Tab and Esc drive the "/" prompt menu instead of the editor.
    var completionState: PromptCompletionState?
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        
        let textView = SubmitAwareTextView()
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.font = font
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 0, height: 8)
        textView.onSubmit = { [weak coordinator = context.coordinator] in
            coordinator?.handleSubmit()
        }
        textView.onCompletionReturn = { [weak coordinator = context.coordinator, weak textView] in
            guard let coordinator, let textView else { return false }
            return coordinator.handleCompletionCommand(#selector(NSResponder.insertNewline(_:)), in: textView)
        }

        // Transparent background
        textView.backgroundColor = .clear
        
        scrollView.documentView = textView
        
        // Initial height calculation
        context.coordinator.updateHeight(for: textView)
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        
        if textView.string != text {
            textView.string = text
            textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        }
        
        if textView.font != font {
            textView.font = font
        }

        if let submitAwareTextView = textView as? SubmitAwareTextView {
            submitAwareTextView.longPasteLineThreshold = longPasteLineThreshold
            submitAwareTextView.onLongPaste = onLongPaste
        }
        
        context.coordinator.updateHeight(for: textView)
        context.coordinator.completionState = completionState
        context.coordinator.requestFocusIfNeeded(on: textView, focusToken: focusToken)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    @MainActor
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SubmitTextEditor
        var completionState: PromptCompletionState?
        private var lastFocusToken: Int?
        
        init(_ parent: SubmitTextEditor) {
            self.parent = parent
            self.completionState = parent.completionState
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            // Updated synchronously so the very next key press already sees the menu state.
            completionState?.update(for: textView.string)
            updateHeight(for: textView)
        }

        /// Handles a key command for the "/" prompt menu. Returns true when the command was consumed.
        func handleCompletionCommand(_ commandSelector: Selector, in textView: NSTextView) -> Bool {
            guard let completionState, completionState.isVisible, !textView.hasMarkedText() else { return false }

            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)):
                completionState.moveSelection(by: -1)
            case #selector(NSResponder.moveDown(_:)):
                completionState.moveSelection(by: 1)
            case #selector(NSResponder.cancelOperation(_:)):
                completionState.dismiss(currentText: textView.string)
            case #selector(NSResponder.insertTab(_:)),
                #selector(NSResponder.insertNewline(_:)),
                #selector(NSResponder.insertLineBreak(_:)),
                #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                if commandSelector != #selector(NSResponder.insertTab(_:)),
                   NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                    return false
                }
                guard let content = completionState.accept() else { return false }
                let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
                // insertText keeps the replacement undoable and reports it through textDidChange.
                textView.insertText(content, replacementRange: fullRange)
            default:
                return false
            }
            return true
        }
        
        func updateHeight(for textView: NSTextView) {
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }
            
            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            let newHeight = min(max(usedRect.height + 16, 20), parent.maxHeight)
            
            DispatchQueue.main.async {
                self.parent.dynamicHeight = newHeight
            }
        }

        func requestFocusIfNeeded(on textView: NSTextView, focusToken: Int) {
            guard focusToken != lastFocusToken else { return }
            lastFocusToken = focusToken

            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }

        func handleSubmit() {
            DispatchQueue.main.async {
                self.parent.onSubmit()
            }
        }
        
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if handleCompletionCommand(commandSelector, in: textView) {
                return true
            }

            let submitCommands: [Selector] = [
                #selector(NSResponder.insertNewline(_:)),
                #selector(NSResponder.insertLineBreak(_:)),
                #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:))
            ]

            if submitCommands.contains(commandSelector) {
                if let event = NSApp.currentEvent, event.modifierFlags.contains(.shift) {
                    return false // Allow new line with Shift+Enter
                } else {
                    handleSubmit()
                    return true // Consume Enter to submit
                }
            }
            return false
        }
    }
}

private final class SubmitAwareTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onCompletionReturn: (() -> Bool)?
    var longPasteLineThreshold: Int = 0
    var onLongPaste: ((String) -> Bool)?

    override func paste(_ sender: Any?) {
        if divertLongPasteIfNeeded() { return }
        super.paste(sender)
    }

    override func pasteAsPlainText(_ sender: Any?) {
        if divertLongPasteIfNeeded() { return }
        super.pasteAsPlainText(sender)
    }

    /// Hands long plain-text pastes to `onLongPaste` (which turns them into an attachment) instead of
    /// inserting them. Pasteboards carrying images or files keep the default behaviour.
    private func divertLongPasteIfNeeded() -> Bool {
        guard longPasteLineThreshold > 0, let onLongPaste else { return false }

        let pasteboard = NSPasteboard.general
        let nonTextTypes: [NSPasteboard.PasteboardType] = [.fileURL, .tiff, .png, .pdf]
        if pasteboard.availableType(from: nonTextTypes) != nil { return false }

        // Attachments truncate their text past the extraction cap, so oversized pastes go in as plain text.
        guard let string = pasteboard.string(forType: .string),
              string.count <= FileAttachment.maxExtractedTextCharacters,
              string.lineCount > longPasteLineThreshold
        else { return false }

        return onLongPaste(string)
    }

    override func keyDown(with event: NSEvent) {
        // Return is normally turned into a submit here, before doCommandBy runs, so the prompt menu gets it first.
        if shouldSubmit(for: event), onCompletionReturn?() == true {
            return
        }

        if shouldSubmit(for: event) {
            onSubmit?()
            return
        }

        super.keyDown(with: event)
    }

    private func shouldSubmit(for event: NSEvent) -> Bool {
        let returnKeyCodes: Set<UInt16> = [36, 76] // Return + keypad Enter
        guard returnKeyCodes.contains(event.keyCode) else { return false }
        if hasMarkedText() {
            return false
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.shift) {
            return false // Shift+Enter inserts newline
        }

        if flags.contains(.command) || flags.contains(.option) || flags.contains(.control) {
            return false
        }

        return true
    }
}

extension String {
    /// Number of lines as displayed in an editor; a single trailing newline does not start a new line.
    var lineCount: Int {
        guard !isEmpty else { return 0 }
        let newlines = reduce(0) { $1.isNewline ? $0 + 1 : $0 }
        return last?.isNewline == true ? newlines : newlines + 1
    }
}
