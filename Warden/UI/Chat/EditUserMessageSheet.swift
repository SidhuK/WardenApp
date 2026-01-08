import SwiftUI

struct EditUserMessageSheet: View {
    @Binding var draft: String
    let onCancel: () -> Void
    let onSaveAndRegenerate: () -> Void

    @FocusState private var isEditorFocused: Bool
    @AppStorage("chatFontSize") private var chatFontSize: Double = 14.0
    
    private var canSave: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    regenerationWarning

                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            SettingsSectionHeader(title: "Message", icon: "pencil", iconColor: .blue)

                            TextEditor(text: $draft)
                                .font(.system(size: max(13, chatFontSize)))
                                .scrollContentBackground(.hidden)
                                .padding(10)
                                .frame(minHeight: 200)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(AppConstants.backgroundInput)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(AppConstants.borderSubtle, lineWidth: 1)
                                )
                                .focused($isEditorFocused)
                            
                            HStack(spacing: 12) {
                                Text("\(draft.count) characters")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                
                                Spacer()
                                
                                if !canSave {
                                    Label("Message required", systemImage: "exclamationmark.circle")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }

            Divider()
            footer
        }
        .background(AppConstants.backgroundWindow)
        .frame(
            minWidth: 520,
            idealWidth: 620,
            maxWidth: 720,
            minHeight: 360,
            idealHeight: 420,
            maxHeight: 560
        )
        .task {
            isEditorFocused = true
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Edit Message")
                    .font(.system(size: 18, weight: .semibold))

                Text("Update your message and regenerate the assistant response from here.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var regenerationWarning: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 6) {
                Text("This affects the rest of the chat")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("Saving will delete all messages after this one and regenerate the assistant response from here.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.orange.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                )
        )
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.escape, modifiers: [])

            Spacer()

            Button(action: onSaveAndRegenerate) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Save & Regenerate")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSave)
            .keyboardShortcut(.defaultAction)
        }
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
