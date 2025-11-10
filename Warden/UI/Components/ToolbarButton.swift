
import SwiftUI

struct ToolbarButton: View {
    let icon: String?
    let text: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon = icon, !icon.isEmpty {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .medium))
                        .scaleEffect(isHovered ? 1.1 : 1.0)
                }

                if !text.isEmpty {
                    Text(text)
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? AppConstants.backgroundSubtle : .clear)
            )
            .foregroundColor(isHovered ? AppConstants.textPrimary : AppConstants.textSecondary)
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.16)) {
                isHovered = hovering
            }
        }
    }
}
