
import SwiftUI

@MainActor
final class CodeViewModel: ObservableObject {
    @Published var highlightedCode: NSAttributedString?
    @Published var isCopied = false
    @AppStorage("chatFontSize") private var chatFontSize: Double = 14.0
    
    public var code: String
    private let language: String
    private let isStreaming: Bool
    private var copiedResetTask: Task<Void, Never>?
    
    init(code: String, language: String, isStreaming: Bool) {
        self.code = code
        self.language = language
        self.isStreaming = isStreaming
    }
    
    func updateHighlighting(colorScheme: ColorScheme) {
        let theme = colorScheme == .dark ? "monokai-sublime" : "color-brewer"
        let currentCode = code
        let currentLanguage = language
        let currentFontSize = chatFontSize
        let currentStreaming = isStreaming
        
        Task(priority: .userInitiated) { [currentCode, currentLanguage, theme, currentFontSize, currentStreaming] in
            let highlighted = await Task.detached(priority: .userInitiated) {
                HighlighterManager.shared.highlight(
                    code: currentCode,
                    language: currentLanguage,
                    theme: theme,
                    fontSize: currentFontSize,
                    isStreaming: currentStreaming
                )
            }.value

            self.highlightedCode = highlighted
        }
    }
    
    func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(code, forType: .string)
        
        withAnimation {
            isCopied = true
        }
        
        copiedResetTask?.cancel()
        copiedResetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard let self else { return }
            withAnimation {
                self.isCopied = false
            }
        }
    }
}
