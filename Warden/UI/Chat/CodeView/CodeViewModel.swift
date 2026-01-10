
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
    private var highlightTask: Task<Void, Never>?
    
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
        
        highlightTask?.cancel()
        highlightTask = Task(priority: .userInitiated) { [currentCode, currentLanguage, theme, currentFontSize, currentStreaming] in
            if currentStreaming {
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
            guard !Task.isCancelled else { return }
            
            let highlighted = await HighlighterManager.shared.highlight(
                code: currentCode,
                language: currentLanguage,
                theme: theme,
                fontSize: currentFontSize,
                isStreaming: currentStreaming
            )
            guard !Task.isCancelled else { return }
            highlightedCode = highlighted?.value
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
