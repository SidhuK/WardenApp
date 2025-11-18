import SwiftUI

struct ButtonWithStatusIndicator: View {
    let title: String
    let action: () -> Void
    let isLoading: Bool
    let hasError: Bool
    let errorMessage: String?
    let successMessage: String
    let isSuccess: Bool

    @State private var loadingIconIndex = 0
    @State private var isHovered = false
    @State private var isPressed = false
    
    private let loadingIcons = ["play.fill"]
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                
                Image(
                    systemName: isLoading ? loadingIcons[loadingIconIndex] : (hasError ? "stop.fill" : "circle.fill")
                )
                .resizable()
                .renderingMode(.template)
                .interpolation(.high)
                .antialiased(true)
                .foregroundColor(iconColor)
                .frame(width: 10, height: 10)
                .shadow(color: iconColor, radius: 2, x: 0, y: 0)
                .animation(.easeInOut(duration: 0.3), value: loadingIconIndex)
                .animation(.easeInOut(duration: 0.3), value: isLoading)
                .animation(.easeInOut(duration: 0.3), value: hasError)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? AppConstants.backgroundSubtle : .clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                isHovered ? AppConstants.borderSubtle : AppConstants.borderSubtle.opacity(0.5),
                                lineWidth: 0.5
                            )
                    )
            )
            .foregroundColor(isHovered ? AppConstants.textPrimary : AppConstants.textSecondary)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.97 : (isHovered ? 1.02 : 1.0))
        .shadow(
            color: Color.black.opacity(isHovered ? 0.08 : 0.04),
            radius: isHovered ? 4 : 2,
            x: 0,
            y: isHovered ? 2 : 1
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.16)) {
                isHovered = hovering
            }
        }
        .onLongPressGesture(minimumDuration: .infinity, perform: {}, onPressingChanged: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        })
        .help(hasError ? (errorMessage ?? "Error occurred") : successMessage)
        .onReceive(timer) { _ in
            if isLoading {
                loadingIconIndex = (loadingIconIndex + 1) % loadingIcons.count
            }
        }
    }
    
    private var iconColor: Color {
        if isLoading {
            return .yellow
        } else if hasError {
            return .red
        } else if isSuccess {
            return .green
        }
        return .gray
    }
}
