import SwiftUI

/// Animated skeleton loader for streaming content
struct SkeletonLoaderView: View {
    let lineCount: Int
    let lineHeight: CGFloat
    let spacing: CGFloat

    @State private var isShimmering = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(0..<lineCount, id: \.self) { index in
                // Vary line widths for more natural look
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color.gray.opacity(0.2), location: 0),
                                .init(color: Color.gray.opacity(0.3), location: 0.5),
                                .init(color: Color.gray.opacity(0.2), location: 1)
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: lineHeight)
                    .frame(maxWidth: index == lineCount - 1 ? .infinity * 0.7 : .infinity)
                    .offset(x: isShimmering ? 400 : -400)
            }
        }
        .animation(
            reduceMotion
                ? nil
                : Animation.linear(duration: 1.5)
                    .repeatForever(autoreverses: false),
            value: isShimmering
        )
        .onAppear {
            if !reduceMotion {
                isShimmering = true
            }
        }
    }
}

/// Compact skeleton loader for small responses
struct CompactSkeletonLoaderView: View {
    @State private var isShimmering = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(0..<2, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 10)
                    .frame(maxWidth: index == 1 ? .infinity * 0.6 : .infinity)
                    .offset(x: isShimmering ? 300 : -300)
            }
        }
        .animation(
            reduceMotion
                ? nil
                : Animation.linear(duration: 1.2)
                    .repeatForever(autoreverses: false),
            value: isShimmering
        )
        .onAppear {
            if !reduceMotion {
                isShimmering = true
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        VStack(alignment: .leading, spacing: 8) {
            Text("Standard Skeleton Loader")
                .font(.caption)
                .foregroundColor(.secondary)
            SkeletonLoaderView(lineCount: 4, lineHeight: 12, spacing: 8)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(RoundedRectangle(cornerRadius: 13).fill(Color.gray.opacity(0.1)))
        }

        VStack(alignment: .leading, spacing: 8) {
            Text("Compact Skeleton Loader")
                .font(.caption)
                .foregroundColor(.secondary)
            CompactSkeletonLoaderView()
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(RoundedRectangle(cornerRadius: 13).fill(Color.gray.opacity(0.1)))
        }

        Spacer()
    }
    .padding()
}
