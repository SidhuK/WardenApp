import SwiftUI

struct ToastNotification: View {
    let message: String
    let icon: String
    @Binding var isVisible: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
            
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.8))
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        )
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.8)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isVisible)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation {
                    isVisible = false
                }
            }
        }
    }
}

struct ToastManager: View {
    @State private var toasts: [ToastItem] = []
    
    var body: some View {
        VStack(spacing: 8) {
            ForEach(toasts) { toast in
                ToastNotification(
                    message: toast.message,
                    icon: toast.icon,
                    isVisible: .constant(true)
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)
                ))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 60)
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
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            toasts.append(toast)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeInOut(duration: 0.3)) {
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