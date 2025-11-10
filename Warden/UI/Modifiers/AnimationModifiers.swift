import SwiftUI

/// Reusable animation modifiers for consistent animations across the app
extension View {
    /// Message arrival animation: fade in with slight scale from bottom
    /// - Parameters:
    ///   - duration: Animation duration in seconds (default: 0.35s)
    ///   - delay: Delay before animation starts (default: 0)
    func messageArrival(duration: Double = 0.35, delay: Double = 0) -> some View {
        self
            .modifier(MessageArrivalModifier(duration: duration, delay: delay))
    }

    /// Typing pulse animation for streaming content
    /// - Parameters:
    ///   - duration: Animation duration in seconds (default: 1.5s)
    func typingPulse(duration: Double = 1.5) -> some View {
        self
            .modifier(TypingPulseModifier(duration: duration))
    }

    /// Button hover animation with scale and shadow
    /// - Parameters:
    ///   - scale: Scale factor on hover (default: 1.1)
    ///   - duration: Animation duration in seconds (default: 0.15s)
    func buttonHover(scale: CGFloat = 1.1, duration: Double = 0.15) -> some View {
        self
            .modifier(ButtonHoverModifier(scale: scale, duration: duration))
    }

    /// Fade in and out animation
    /// - Parameters:
    ///   - duration: Animation duration in seconds
    func fadeInOut(duration: Double) -> some View {
        self
            .modifier(FadeInOutModifier(duration: duration))
    }

    /// Loading spinner rotation animation
    /// - Parameters:
    ///   - duration: Full rotation duration in seconds (default: 1.0s)
    func loadingSpinner(duration: Double = 1.0) -> some View {
        self
            .modifier(LoadingSpinnerModifier(duration: duration))
    }

    /// Smooth state transition with fade
    /// - Parameters:
    ///   - duration: Animation duration in seconds (default: 0.3s)
    func stateTransition(duration: Double = 0.3) -> some View {
        self
            .transition(.opacity)
            .animation(.easeInOut(duration: duration), value: UUID())
    }

    /// Shimmer effect for skeleton loaders
    func shimmer() -> some View {
        self
            .modifier(ShimmerModifier())
    }

    /// Scale up animation
    /// - Parameters:
    ///   - scale: Target scale (default: 1.05)
    ///   - duration: Animation duration
    func scaleAnimation(scale: CGFloat = 1.05, duration: Double = 0.2) -> some View {
        self
            .modifier(ScaleAnimationModifier(scale: scale, duration: duration))
    }
}

// MARK: - Modifier Implementations

struct MessageArrivalModifier: ViewModifier {
    let duration: Double
    let delay: Double

    @State private var isAppearing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isAppearing ? 1.0 : 0.95)
            .opacity(isAppearing ? 1.0 : 0)
            .offset(y: isAppearing ? 0 : 8)
            .onAppear {
                withAnimation(.easeOut(duration: duration).delay(delay)) {
                    isAppearing = true
                }
            }
    }
}

struct TypingPulseModifier: ViewModifier {
    let duration: Double

    @State private var isAnimating = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isAnimating ? 1.0 : 0.8)
            .animation(
                reduceMotion
                    ? nil
                    : Animation.easeInOut(duration: duration)
                        .repeatForever(autoreverses: true),
                value: isAnimating
            )
            .onAppear {
                if !reduceMotion {
                    isAnimating = true
                }
            }
    }
}

struct ButtonHoverModifier: ViewModifier {
    let scale: CGFloat
    let duration: Double

    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? scale : 1.0)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: duration)) {
                    isHovered = hovering
                }
            }
    }
}

struct FadeInOutModifier: ViewModifier {
    let duration: Double

    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1.0 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: duration)) {
                    isVisible = true
                }
            }
    }
}

struct LoadingSpinnerModifier: ViewModifier {
    let duration: Double

    @State private var isSpinning = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(isSpinning ? 360 : 0))
            .animation(
                reduceMotion
                    ? nil
                    : Animation.linear(duration: duration)
                        .repeatForever(autoreverses: false),
                value: isSpinning
            )
            .onAppear {
                if !reduceMotion {
                    isSpinning = true
                }
            }
    }
}

struct ShimmerModifier: ViewModifier {
    @State private var isShimmering = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: Color.white.opacity(0), location: 0),
                        .init(color: Color.white.opacity(0.2), location: 0.5),
                        .init(color: Color.white.opacity(0), location: 1)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: isShimmering ? 400 : -400)
                .animation(
                    reduceMotion
                        ? nil
                        : Animation.linear(duration: 1.5)
                            .repeatForever(autoreverses: false),
                    value: isShimmering
                )
            )
            .onAppear {
                if !reduceMotion {
                    isShimmering = true
                }
            }
    }
}

struct ScaleAnimationModifier: ViewModifier {
    let scale: CGFloat
    let duration: Double

    @State private var isScaled = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isScaled ? scale : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: duration)) {
                    isScaled = true
                }
            }
    }
}
