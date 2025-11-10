import SwiftUI

/// Helper view for animating state transitions with custom content
struct AnimatedStateView<Content: View>: View {
    let isVisible: Bool
    let duration: Double
    @ViewBuilder let content: () -> Content

    var body: some View {
        if isVisible {
            content()
                .transition(.opacity)
                .animation(.easeInOut(duration: duration), value: isVisible)
        }
    }
}

/// Animates between two states with cross-fade effect
struct StateTransitionView<T: Equatable, Content: View>: View {
    let value: T
    let duration: Double
    @ViewBuilder let content: (T) -> Content

    @State private var displayValue: T

    init(value: T, duration: Double = 0.3, @ViewBuilder content: @escaping (T) -> Content) {
        self.value = value
        self.duration = duration
        self.content = content
        _displayValue = State(initialValue: value)
    }

    var body: some View {
        content(displayValue)
            .transition(.opacity)
            .onChange(of: value) { _, newValue in
                withAnimation(.easeInOut(duration: duration)) {
                    displayValue = newValue
                }
            }
    }
}

/// Loading state with spinner animation
struct LoadingView: View {
    let message: String?
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "hourglass")
                .loadingSpinner(duration: 1.0)

            if let message = message {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundColor(AppConstants.textSecondary)
            }
        }
    }
}

/// Error state with bounce animation
struct ErrorAnimationView: View {
    let message: String
    @State private var isBouncing = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(AppConstants.destructive)
                .scaleEffect(isBouncing ? 1.1 : 1.0)
                .animation(
                    reduceMotion
                        ? nil
                        : Animation.easeInOut(duration: 0.4)
                            .repeatForever(autoreverses: true),
                    value: isBouncing
                )

            Text(message)
                .font(.system(size: 13))
                .foregroundColor(AppConstants.destructive)
        }
        .onAppear {
            if !reduceMotion {
                isBouncing = true
            }
        }
    }
}

/// Success state with checkmark animation
struct SuccessAnimationView: View {
    let message: String
    @State private var isAnimating = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .scaleEffect(isAnimating ? 1.0 : 0.8)
                .opacity(isAnimating ? 1.0 : 0.7)
                .animation(
                    reduceMotion
                        ? nil
                        : Animation.easeOut(duration: 0.3),
                    value: isAnimating
                )

            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.green)
        }
        .onAppear {
            if !reduceMotion {
                isAnimating = true
            }
        }
    }
}
