
import SwiftUI

struct HighlightedText: View {
    let text: String
    let highlight: String
    let color: Color

    init(_ text: String, highlight: String, color: Color = .yellow) {
        self.text = text
        self.highlight = highlight.lowercased()
        self.color = color
    }

    var body: some View {
        if highlight.isEmpty {
            Text(text)
        } else {
            Text(highlightedAttributedString)
        }
    }

    private var highlightedAttributedString: AttributedString {
        let attributedString = NSMutableAttributedString(string: text)
        let nsText = text as NSString
        let highlightColor = NSColor(color).withAlphaComponent(0.2)

        var searchRange = NSRange(location: 0, length: nsText.length)
        while true {
            let foundRange = nsText.range(
                of: highlight,
                options: [.caseInsensitive],
                range: searchRange
            )
            guard foundRange.location != NSNotFound else { break }

            attributedString.addAttribute(.backgroundColor, value: highlightColor, range: foundRange)

            let nextLocation = foundRange.location + foundRange.length
            guard nextLocation < nsText.length else { break }
            searchRange = NSRange(location: nextLocation, length: nsText.length - nextLocation)
        }

        return AttributedString(attributedString)
    }
}
