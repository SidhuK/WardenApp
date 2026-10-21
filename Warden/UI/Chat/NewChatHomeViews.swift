import CoreData
import SwiftUI

// MARK: - Context Row

/// Project, persona and model summary shown above the new-chat composer. Each part opens the existing picker.
struct NewChatContextRow: View {
    @ObservedObject var chat: ChatEntity

    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \APIServiceEntity.addedDate, ascending: false)],
        animation: .default
    )
    private var apiServices: FetchedResults<APIServiceEntity>

    @State private var showingMoveToProject = false
    @State private var showingPersonaPopover = false

    private var projectTitle: String {
        let name = chat.project?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard chat.project != nil else { return "No project" }
        return name.isEmpty ? "Untitled Project" : name
    }

    private var projectColor: Color {
        guard let project = chat.project else { return .secondary }
        return Color(hex: project.colorCode ?? "#007AFF") ?? .accentColor
    }

    private var personaTitle: String {
        guard let persona = chat.persona else { return "Persona: Default" }
        let name = persona.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return "Persona: \(name.isEmpty ? "Custom" : name)"
    }

    var body: some View {
        HStack(spacing: 4) {
            // Projects live in the history, which a temporary chat isn't part of until it's saved.
            if !chat.isTemporary {
                Button {
                    showingMoveToProject = true
                } label: {
                    ContextRowLabel(title: projectTitle) {
                        Image(systemName: chat.project == nil ? "folder" : "folder.fill")
                            .foregroundStyle(projectColor)
                    }
                }
                .buttonStyle(.plain)
                .help("Choose a project for this chat")
                .accessibilityLabel("Project")
                .accessibilityValue(projectTitle)
                .sheet(isPresented: $showingMoveToProject) {
                    MoveToProjectView(chats: [chat], onComplete: {})
                }

                separator
            }

            Button {
                showingPersonaPopover.toggle()
            } label: {
                ContextRowLabel(title: personaTitle) {
                    Image(systemName: chat.persona == nil ? "person.circle" : "person.circle.fill")
                }
            }
            .buttonStyle(.plain)
            .help("Choose a persona")
            .accessibilityLabel("Persona")
            .accessibilityValue(personaTitle)
            .popover(isPresented: $showingPersonaPopover, arrowEdge: .bottom) {
                PersonaSelectorView(chat: chat)
                    .environment(\.managedObjectContext, viewContext)
                    .frame(width: 400, height: 80)
                    .background(Color(nsColor: .windowBackgroundColor))
            }

            separator

            ModelSelectorPopoverButton(
                apiServices: Array(apiServices),
                selectedProviderType: chat.apiService?.type,
                selectedModelId: chat.gptModel.isEmpty ? nil : chat.gptModel,
                popoverWidth: 440,
                popoverHeight: 560,
                arrowEdge: .bottom,
                onSelect: { provider, modelId in
                    BetterCompactModelSelector.selectModel(
                        provider: provider,
                        modelId: modelId,
                        for: chat,
                        from: Array(apiServices)
                    )
                }
            ) {
                ContextRowLabel(title: BetterCompactModelSelector.shortModelName(for: chat) ?? "Select Model") {
                    Image("logo_\(chat.apiService?.type ?? AppConstants.defaultApiType)")
                        .resizable()
                        .renderingMode(.template)
                        .interpolation(.high)
                        .frame(width: 10, height: 10)
                }
            }
            .help("Choose a model")
            .accessibilityLabel("Model")
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var separator: some View {
        Text("·")
            .font(.system(size: 11))
            .foregroundStyle(.quaternary)
            .accessibilityHidden(true)
    }
}

private struct ContextRowLabel<Icon: View>: View {
    let title: String
    @ViewBuilder let icon: () -> Icon

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 5) {
            icon()
                .font(.system(size: 10, weight: .medium))
            Text(title)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(isHovered ? Color.primary : Color.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(isHovered ? 0.06 : 0))
        )
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

// MARK: - Panels

/// Recent chats to pick up again, newest first.
struct ContinueChatsPanel: View {
    let chats: [ChatEntity]
    let showsProjectNames: Bool
    let onOpen: (ChatEntity) -> Void

    var body: some View {
        NewChatPanel(title: "Continue", systemImage: "clock.arrow.circlepath") {
            ForEach(chats, id: \.objectID) { chat in
                NewChatPanelRow(action: { onOpen(chat) }) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(chat.name.isEmpty ? "Untitled chat" : chat.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        if showsProjectNames, let projectName = chat.project?.name, !projectName.isEmpty {
                            Text(projectName)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 8)

                    Text(RecentChatTimeFormatter.string(for: chat.updatedDate))
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                        .fixedSize()
                }
                .help("Open \"\(chat.name)\"")
            }
        }
    }
}

/// The user's most used saved prompts. Choosing one fills the composer.
struct PromptShortcutsPanel: View {
    let prompts: [PromptEntity]
    let onSelect: (PromptEntity) -> Void

    var body: some View {
        NewChatPanel(title: "Your prompts", systemImage: "text.badge.star") {
            ForEach(prompts, id: \.objectID) { prompt in
                NewChatPanelRow(action: { onSelect(prompt) }) {
                    Text(prompt.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 8)

                    if let shortcut = prompt.shortcut, !shortcut.isEmpty {
                        Text("/\(shortcut)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                .help(prompt.content)
            }
        }
    }
}

private struct NewChatPanel<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                content()
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct NewChatPanelRow<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                content()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(isHovered ? 0.06 : 0))
            )
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

// MARK: - Relative Time

enum RecentChatTimeFormatter {
    /// Compact age such as "Now", "5m", "2h", "Yesterday", "Mon", "Mar 3" or "Mar 3, 2024".
    static func string(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "Now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if calendar.isDate(date, inSameDayAs: now) { return "\(Int(seconds / 3600))h" }
        if calendar.isDateInYesterday(date, relativeTo: now) { return "Yesterday" }

        let startOfToday = calendar.startOfDay(for: now)
        if let weekAgo = calendar.date(byAdding: .day, value: -6, to: startOfToday), date >= weekAgo {
            return date.formatted(.dateTime.weekday(.abbreviated))
        }
        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}

private extension Calendar {
    func isDateInYesterday(_ date: Date, relativeTo now: Date) -> Bool {
        guard let yesterday = self.date(byAdding: .day, value: -1, to: now) else { return false }
        return isDate(date, inSameDayAs: yesterday)
    }
}
