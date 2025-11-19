
import SwiftUI

class CodeViewModel: ObservableObject {
    @Published var highlightedCode: NSAttributedString?
    @Published var isCopied = false
    @AppStorage("chatFontSize") private var chatFontSize: Double = 14.0
    
    public var code: String
    private let language: String
    private let isStreaming: Bool
    
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
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let highlighted = HighlighterManager.shared.highlight(
                code: currentCode,
                language: currentLanguage,
                theme: theme,
                fontSize: currentFontSize,
                isStreaming: currentStreaming
            )
            
            DispatchQueue.main.async {
                self?.highlightedCode = highlighted
            }
        }
    }
    
    func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(code, forType: .string)
        
        withAnimation {
            isCopied = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            withAnimation {
                self.isCopied = false
            }
        }
    }
}
