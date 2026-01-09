import SwiftUI

#if DEBUG
/// Development-only showcase for animation components
struct AnimationShowcase: View {
    @State private var showMessage = false
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Animation Showcase")
                    .font(.title2)
                    .fontWeight(.semibold)

                messageArrivalSection
                typingIndicatorsSection
                skeletonLoadersSection
                stateTransitionsSection
            }
            .padding(16)
        }
    }

    private var messageArrivalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Message Arrival")
                .font(.headline)

            if showMessage {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(0..<3, id: \.self) { index in
                        Text("Message \(index + 1)")
                            .font(.system(size: 13))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 13)
                                    .fill(Color.accentColor.opacity(0.16))
                            )
                            .messageArrival(delay: Double(index) * 0.1)
                    }
                }
            }

            Button(showMessage ? "Reset" : "Show Messages") {
                showMessage.toggle()
            }
            .buttonStyle(.bordered)
        }
    }

    private var typingIndicatorsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Typing Indicators")
                .font(.headline)

            VStack(alignment: .leading, spacing: 16) {
                TypingIndicatorView()
                CompactTypingIndicatorView()
                PulsingTypingIndicatorView()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 13)
                    .fill(Color.gray.opacity(0.05))
            )
        }
    }

    private var skeletonLoadersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Skeleton Loaders")
                .font(.headline)

            VStack(alignment: .leading, spacing: 16) {
                SkeletonLoaderView(lineCount: 3, lineHeight: 12, spacing: 8)
                CompactSkeletonLoaderView()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 13)
                    .fill(Color.gray.opacity(0.05))
            )
        }
    }

    private var stateTransitionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("State Views")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                if isLoading {
                    LoadingView(message: "Processing...")
                }

                if !isLoading && showMessage {
                    SuccessAnimationView(message: "Success!")
                }

                HStack(spacing: 8) {
                    Button("Loading") {
                        isLoading.toggle()
                    }
                    .buttonStyle(.bordered)

                    Button("Success") {
                        if !isLoading {
                            showMessage.toggle()
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 13)
                    .fill(Color.gray.opacity(0.05))
            )
        }
    }
}

#Preview {
    AnimationShowcase()
}
#endif
