import SwiftUI

/// Animated typing indicator with three bouncing dots
struct TypingIndicatorView: View {
    @State private var dotAnimation: [Bool] = [false, false, false]
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    private let dotSize: CGFloat = 6
    private let dotSpacing: CGFloat = 4
    private let animationDuration: Double = 0.6
    private let totalDuration: Double = 1.2

    var body: some View {
        HStack(spacing: dotSpacing) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(AppConstants.textSecondary)
                    .frame(width: dotSize, height: dotSize)
                    .offset(y: dotAnimation[index] ? -6 : 0)
                    .animation(
                        reduceMotion
                            ? nil
                            : Animation.easeInOut(duration: animationDuration)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.15),
                        value: dotAnimation[index]
                    )
            }
        }
        .onAppear {
            if !reduceMotion {
                for index in 0..<3 {
                    dotAnimation[index] = true
                }
            }
        }
    }
}

// MARK: - Variants

/// Compact typing indicator for inline use (smaller dots)
struct CompactTypingIndicatorView: View {
    @State private var dotAnimation: [Bool] = [false, false, false]
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    private let dotSize: CGFloat = 4
    private let dotSpacing: CGFloat = 3
    private let animationDuration: Double = 0.5

    var body: some View {
        HStack(spacing: dotSpacing) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(AppConstants.textSecondary)
                    .frame(width: dotSize, height: dotSize)
                    .offset(y: dotAnimation[index] ? -4 : 0)
                    .animation(
                        reduceMotion
                            ? nil
                            : Animation.easeInOut(duration: animationDuration)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.12),
                        value: dotAnimation[index]
                    )
            }
        }
        .onAppear {
            if !reduceMotion {
                for index in 0..<3 {
                    dotAnimation[index] = true
                }
            }
        }
    }
}

/// Pulsing typing indicator (single dot that pulses)
struct PulsingTypingIndicatorView: View {
    @State private var isPulsing = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        Circle()
            .fill(AppConstants.textSecondary)
            .frame(width: 6, height: 6)
            .scaleEffect(isPulsing ? 1.2 : 1.0)
            .opacity(isPulsing ? 0.6 : 1.0)
            .animation(
                reduceMotion
                    ? nil
                    : Animation.easeInOut(duration: 0.7)
                        .repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear {
                if !reduceMotion {
                    isPulsing = true
                }
            }
    }
}

#Preview {
    VStack(spacing: 20) {
        VStack(alignment: .leading, spacing: 8) {
            Text("Standard Typing Indicator")
                .font(.caption)
                .foregroundColor(.secondary)
            TypingIndicatorView()
        }

        VStack(alignment: .leading, spacing: 8) {
            Text("Compact Typing Indicator")
                .font(.caption)
                .foregroundColor(.secondary)
            CompactTypingIndicatorView()
        }

        VStack(alignment: .leading, spacing: 8) {
            Text("Pulsing Typing Indicator")
                .font(.caption)
                .foregroundColor(.secondary)
            PulsingTypingIndicatorView()
        }

        Spacer()
    }
    .padding()
}
