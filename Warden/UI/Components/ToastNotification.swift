import SwiftUI

struct ToastNotification: View {
    let message: String
    let icon: String
    @Binding var isVisible: Bool

    @Environment(\.colorScheme) private var colorScheme

    private var semanticColor: Color {
        switch icon {
        case "checkmark.circle.fill":
            return AppConstants.success
        case "exclamationmark.triangle.fill",
             "exclamationmark.triangle",
             "xmark.octagon.fill":
            return AppConstants.destructive
        case "info.circle.fill",
             "info.circle":
            return Color.accentColor
        default:
            return Color.accentColor
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(semanticColor)

            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(AppConstants.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(AppConstants.backgroundElevated.opacity(colorScheme == .dark ? 0.98 : 0.98))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(AppConstants.borderSubtle, lineWidth: 0.8)
                )
                .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 4)
        )
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : -6)
        .animation(.easeOut(duration: 0.22), value: isVisible)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeOut(duration: 0.22)) {
                    isVisible = false
                }
            }
        }
    }
}

struct ToastManager: View {
    @State private var toasts: [ToastItem] = []
    
    var body: some View {
        VStack(spacing: 10) {
            ForEach(toasts) { toast in
                ToastNotification(
                    message: toast.message,
                    icon: toast.icon,
                    isVisible: .constant(true)
                )
                .transition(
                    .move(edge: .top)
                    .combined(with: .opacity)
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 52)
        .allowsHitTesting(false)
        .onReceive(NotificationCenter.default.publisher(for: .showToast)) { notification in
            if let userInfo = notification.userInfo,
               let message = userInfo["message"] as? String,
               let icon = userInfo["icon"] as? String {
                showToast(message: message, icon: icon)
            }
        }
    }
    
    private func showToast(message: String, icon: String) {
        let toast = ToastItem(message: message, icon: icon)

        withAnimation(.easeOut(duration: 0.22)) {
            toasts.append(toast)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            withAnimation(.easeOut(duration: 0.22)) {
                toasts.removeAll { $0.id == toast.id }
            }
        }
    }
}

struct ToastItem: Identifiable {
    let id = UUID()
    let message: String
    let icon: String
}

extension Notification.Name {
    static let showToast = Notification.Name("showToast")
}

extension View {
    func showToast(_ message: String, icon: String = "checkmark.circle.fill") {
        NotificationCenter.default.post(
            name: .showToast,
            object: nil,
            userInfo: ["message": message, "icon": icon]
        )
    }
} 