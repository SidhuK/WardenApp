
import Highlightr
import SwiftUI

class HighlighterManager {
    static let shared = HighlighterManager()
    private let highlightr = Highlightr()
    private let cache = NSCache<NSString, NSAttributedString>()
    @AppStorage("codeFont") private var codeFont: String = AppConstants.firaCode
    
    // Streaming optimization: track last highlighted content to avoid redundant work
    private var lastStreamingCodeLength: Int = 0
    private var lastStreamingResult: NSAttributedString?
    private var lastStreamingLanguage: String = ""
    private var lastStreamingTheme: String = ""
    
    // Minimum character change to trigger re-highlight during streaming
    private let streamingRehighlightThreshold = 50

    func highlight(code: String, language: String, theme: String, fontSize: Double = 14, isStreaming: Bool = false) -> NSAttributedString? {
        var cacheKey: NSString = ""
        if !isStreaming {
            cacheKey = "\(code):\(language):\(theme):\(codeFont)" as NSString

            if let cached = cache.object(forKey: cacheKey) {
                return cached
            }
        } else {
            // Streaming optimization: skip re-highlighting if content hasn't grown enough
            let currentLength = code.count
            if let lastResult = lastStreamingResult,
               language == lastStreamingLanguage,
               theme == lastStreamingTheme,
               currentLength - lastStreamingCodeLength < streamingRehighlightThreshold {
                return lastResult
            }
        }

        highlightr?.setTheme(to: theme)
        if let highlighted = highlightr?.highlight(code, as: language) {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont(name: codeFont, size: fontSize - 1)
                    ?? NSFont.systemFont(ofSize: fontSize - 1)
            ]
            let attributedString = NSMutableAttributedString(attributedString: highlighted)
            attributedString.addAttributes(attributes, range: NSRange(location: 0, length: attributedString.length))

            if !isStreaming {
                cache.setObject(attributedString, forKey: cacheKey)
            } else {
                // Cache streaming result for next comparison
                lastStreamingCodeLength = code.count
                lastStreamingResult = attributedString
                lastStreamingLanguage = language
                lastStreamingTheme = theme
            }
            return attributedString
        }
        return nil
    }
    
    func invalidateCache() {
        cache.removeAllObjects()
        // Also clear streaming cache
        lastStreamingCodeLength = 0
        lastStreamingResult = nil
    }
    
    /// Call this when streaming ends to clear the streaming cache
    func clearStreamingCache() {
        lastStreamingCodeLength = 0
        lastStreamingResult = nil
        lastStreamingLanguage = ""
        lastStreamingTheme = ""
    }
    
}

