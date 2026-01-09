import SwiftUI

/// Loading state with spinner animation
struct LoadingView: View {
    let message: String?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "hourglass")
                .loadingSpinner(duration: 1.0)

            if let message {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundColor(AppConstants.textSecondary)
            }
        }
    }
}

/// Error state with subtle pulse
struct ErrorAnimationView: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(AppConstants.destructive)

            Text(message)
                .font(.system(size: 13))
                .foregroundColor(AppConstants.destructive)
        }
    }
}

/// Success state with checkmark
struct SuccessAnimationView: View {
    let message: String
    @State private var isAnimating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .scaleEffect(reduceMotion || isAnimating ? 1.0 : 0.8)
                .opacity(reduceMotion || isAnimating ? 1.0 : 0.7)

            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.green)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                isAnimating = true
            }
        }
    }
}
