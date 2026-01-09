import SwiftUI

/// Reusable animation modifiers for consistent animations across the app
extension View {
    /// Message arrival animation: fade in with slight scale from bottom
    func messageArrival(duration: Double = 0.35, delay: Double = 0) -> some View {
        modifier(MessageArrivalModifier(duration: duration, delay: delay))
    }

    /// Typing pulse animation for streaming content
    func typingPulse(duration: Double = 1.5) -> some View {
        modifier(TypingPulseModifier(duration: duration))
    }

    /// Loading spinner rotation animation
    func loadingSpinner(duration: Double = 1.0) -> some View {
        modifier(LoadingSpinnerModifier(duration: duration))
    }

    /// Shimmer effect for skeleton loaders
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

// MARK: - Modifier Implementations

struct MessageArrivalModifier: ViewModifier {
    let duration: Double
    let delay: Double

    @State private var isAppearing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(reduceMotion || isAppearing ? 1.0 : 0.95)
            .opacity(reduceMotion || isAppearing ? 1.0 : 0)
            .offset(y: reduceMotion || isAppearing ? 0 : 8)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: duration).delay(delay)) {
                    isAppearing = true
                }
            }
    }
}

struct TypingPulseModifier: ViewModifier {
    let duration: Double

    @State private var isAnimating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(reduceMotion ? 1.0 : (isAnimating ? 1.0 : 0.8))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true)) {
                    isAnimating = true
                }
            }
    }
}

struct LoadingSpinnerModifier: ViewModifier {
    let duration: Double

    @State private var rotation: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(rotation))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    LinearGradient(
                        colors: [
                            .clear,
                            .white.opacity(0.2),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 0.6)
                    .offset(x: phase * geometry.size.width * 1.6 - geometry.size.width * 0.3)
                }
                .mask(content)
            )
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}
