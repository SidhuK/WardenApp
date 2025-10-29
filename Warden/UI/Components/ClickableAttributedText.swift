import SwiftUI

/// Placeholder - not used
struct ClickableAttributedText: View {
    let attributedString: NSAttributedString
    
    var body: some View {
        Text(AttributedString(attributedString))
    }
}
