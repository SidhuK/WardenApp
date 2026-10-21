import SwiftUI

/// Dashed strip at the top of a temporary chat, with a way to keep it.
struct TemporaryChatBanner: View {
    let canSave: Bool
    let onSave: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye.slash")
                .font(.system(size: 11, weight: .medium))
            Text("Temporary chat · Not saved to history")
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)

            Spacer(minLength: 8)

            Button("Save chat", action: onSave)
                .buttonStyle(.borderless)
                .font(.system(size: 12, weight: .medium))
                .disabled(!canSave)
                .help(canSave ? "Add this chat to your history" : "Wait for the reply to finish before saving")
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
        .frame(maxWidth: 1000)
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .accessibilityElement(children: .contain)
    }
}
