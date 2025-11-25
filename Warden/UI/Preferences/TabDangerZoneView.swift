
import SwiftUI

struct TabDangerZoneView: View {
    @ObservedObject var store: ChatStore
    @State private var currentAlert: AlertType?

    enum AlertType: Identifiable {
        case deleteChats, deletePersonas, deleteAPIServices
        var id: Self { self }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title2)
                        .foregroundColor(.red)
                    Text("Danger Zone")
                        .font(.headline)
                        .foregroundColor(.red)
                }
                .padding(.bottom, 4)

                Text("These actions are permanent and cannot be undone. Please proceed with caution.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()
                    .padding(.vertical, 8)

                VStack(alignment: .leading, spacing: 16) {
                    dangerActionRow(
                        title: "Delete all chats",
                        description: "Remove all conversation history from the app.",
                        action: { currentAlert = .deleteChats }
                    )

                    dangerActionRow(
                        title: "Delete all AI Assistants",
                        description: "Remove all custom AI assistant configurations.",
                        action: { currentAlert = .deletePersonas }
                    )

                    dangerActionRow(
                        title: "Delete all API Services",
                        description: "Remove all configured API service connections.",
                        action: { currentAlert = .deleteAPIServices }
                    )
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.red.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.red.opacity(0.15), lineWidth: 1)
            )
        }
        .padding(32)
        .alert(item: $currentAlert) { alertType in
            switch alertType {
            case .deleteChats:
                return Alert(
                    title: Text("Delete All Chats"),
                    message: Text("Are you sure you want to delete all chats? This action cannot be undone."),
                    primaryButton: .destructive(Text("Delete")) {
                        store.deleteAllChats()
                    },
                    secondaryButton: .cancel()
                )
            case .deletePersonas:
                return Alert(
                    title: Text("Delete All AI Assistants"),
                    message: Text("Are you sure you want to delete all AI Assistants?"),
                    primaryButton: .destructive(Text("Delete")) {
                        store.deleteAllPersonas()
                    },
                    secondaryButton: .cancel()
                )
            case .deleteAPIServices:
                return Alert(
                    title: Text("Delete All API Services"),
                    message: Text("Are you sure you want to delete all API Services?"),
                    primaryButton: .destructive(Text("Delete")) {
                        store.deleteAllAPIServices()
                    },
                    secondaryButton: .cancel()
                )
            }
        }
    }

    @ViewBuilder
    private func dangerActionRow(title: String, description: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(action: action) {
                Text("Delete")
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.red)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
    }
}
