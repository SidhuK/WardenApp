import SwiftUI

/// Showcase view for all animations in the app
struct AnimationShowcase: View {
    @State private var showMessage = false
    @State private var isStreaming = false
    @State private var isLoading = false
    @State private var selectedTab: AnimationTab = .messageArrival

    enum AnimationTab: String, CaseIterable {
        case messageArrival = "Message Arrival"
        case typingIndicators = "Typing Indicators"
        case skeletonLoaders = "Skeleton Loaders"
        case stateTransitions = "State Transitions"
        case scrollAnimations = "Scroll Animations"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 12) {
                Text("Animation Showcase")
                    .font(.title2)
                    .fontWeight(.semibold)

                Picker("Animation Type", selection: $selectedTab) {
                    ForEach(AnimationTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding()
            .background(Color.gray.opacity(0.05))

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    switch selectedTab {
                    case .messageArrival:
                        messageArrivalShowcase
                    case .typingIndicators:
                        typingIndicatorsShowcase
                    case .skeletonLoaders:
                        skeletonLoadersShowcase
                    case .stateTransitions:
                        stateTransitionsShowcase
                    case .scrollAnimations:
                        scrollAnimationsShowcase
                    }
                }
                .padding(16)
            }
        }
    }

    // MARK: - Message Arrival Showcase

    private var messageArrivalShowcase: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Message Arrival")
                .font(.headline)

            VStack(spacing: 12) {
                if showMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Hello! This is a message arriving.")
                            .font(.system(size: 13))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 13)
                                    .fill(Color.accentColor.opacity(0.16))
                            )
                            .messageArrival(duration: 0.35)

                        Text("This one has a slight delay.")
                            .font(.system(size: 13))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 13)
                                    .fill(Color.accentColor.opacity(0.16))
                            )
                            .messageArrival(duration: 0.35, delay: 0.1)

                        Text("And this one arrives last.")
                            .font(.system(size: 13))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 13)
                                    .fill(Color.accentColor.opacity(0.16))
                            )
                            .messageArrival(duration: 0.35, delay: 0.2)
                    }
                    .transition(.identity)
                }
            }

            Button(showMessage ? "Reset" : "Show Messages") {
                showMessage.toggle()
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Typing Indicators Showcase

    private var typingIndicatorsShowcase: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Typing Indicators")
                .font(.headline)

            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Standard")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack {
                        TypingIndicatorView()
                        Spacer()
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Compact")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack {
                        CompactTypingIndicatorView()
                        Spacer()
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Pulsing")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack {
                        PulsingTypingIndicatorView()
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 13)
                    .fill(Color.gray.opacity(0.05))
            )
        }
    }

    // MARK: - Skeleton Loaders Showcase

    private var skeletonLoadersShowcase: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Skeleton Loaders")
                .font(.headline)

            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Standard (4 lines)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    SkeletonLoaderView(lineCount: 4, lineHeight: 12, spacing: 8)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 13)
                                .fill(Color.gray.opacity(0.05))
                        )
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Compact")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    CompactSkeletonLoaderView()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 13)
                                .fill(Color.gray.opacity(0.05))
                        )
                }
            }
        }
    }

    // MARK: - State Transitions Showcase

    private var stateTransitionsShowcase: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("State Transitions")
                .font(.headline)

            VStack(spacing: 12) {
                if isLoading {
                    LoadingView(message: "Processing request...")
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.3), value: isLoading)
                }

                if !isLoading && showMessage {
                    SuccessAnimationView(message: "Success!")
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.3), value: showMessage)
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
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 13)
                    .fill(Color.gray.opacity(0.05))
            )
        }
    }

    // MARK: - Scroll Animations Showcase

    private var scrollAnimationsShowcase: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Scroll Animations")
                .font(.headline)

            Text("Auto-scroll animation: 250-400ms with easeOut curve")
                .font(.system(size: 13))
                .foregroundColor(.secondary)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(0..<10, id: \.self) { index in
                        HStack {
                            Text("Item \(index + 1)")
                                .font(.system(size: 13))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.accentColor.opacity(0.1))
                                )
                            Spacer()
                        }
                        .messageArrival(duration: 0.35, delay: Double(index) * 0.05)
                    }
                }
            }
            .frame(height: 200)
            .background(Color.gray.opacity(0.05))
            .cornerRadius(8)
        }
    }
}

#Preview {
    AnimationShowcase()
}
