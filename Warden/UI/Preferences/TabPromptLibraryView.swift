import CoreData
import SwiftUI

/// Preferences tab for the prompt library: list with usage counts, add/edit sheet, delete.
struct TabPromptLibraryView: View {
    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \PromptEntity.usageCount, ascending: false),
            NSSortDescriptor(keyPath: \PromptEntity.name, ascending: true),
        ],
        animation: .default
    )
    private var prompts: FetchedResults<PromptEntity>

    @State private var editorTarget: EditorTarget?
    @State private var promptPendingDeletion: PromptEntity?

    private enum EditorTarget: Identifiable {
        case new
        case edit(PromptEntity)

        var id: String {
            switch self {
            case .new: return "new"
            case .edit(let prompt): return prompt.objectID.uriRepresentation().absoluteString
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            SettingsSectionHeader(title: "Prompt Library", icon: "text.badge.plus")
                            Spacer()
                            Button {
                                editorTarget = .new
                            } label: {
                                Label("Add Prompt", systemImage: "plus")
                            }
                            .buttonStyle(.bordered)
                        }

                        Text("Type / at the start of the message box to insert a prompt by name or shortcut.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if prompts.isEmpty {
                            Text("No prompts yet. Add one to get started.")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 32)
                        } else {
                            promptList
                        }
                    }
                }
            }
            .padding(20)
        }
        .sheet(item: $editorTarget) { target in
            switch target {
            case .new:
                PromptEditorSheet(prompt: nil)
            case .edit(let prompt):
                PromptEditorSheet(prompt: prompt)
            }
        }
        .confirmationDialog(
            "Delete \"\(promptPendingDeletion?.name ?? "prompt")\"?",
            isPresented: Binding(
                get: { promptPendingDeletion != nil },
                set: { if !$0 { promptPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let prompt = promptPendingDeletion {
                    PromptLibraryManager.shared.deletePrompt(prompt)
                }
                promptPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                promptPendingDeletion = nil
            }
        } message: {
            Text("This can't be undone.")
        }
    }

    private var promptList: some View {
        VStack(spacing: 0) {
            ForEach(prompts) { prompt in
                PromptLibraryRow(
                    prompt: prompt,
                    onEdit: { editorTarget = .edit(prompt) },
                    onDelete: { promptPendingDeletion = prompt }
                )
                if prompt.objectID != prompts.last?.objectID {
                    Divider().opacity(0.5)
                }
            }
        }
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct PromptLibraryRow: View {
    @ObservedObject var prompt: PromptEntity
    var onEdit: () -> Void
    var onDelete: () -> Void
    @State private var isHovered = false

    private var preview: String {
        prompt.content.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.bubble")
                .font(.system(size: 13))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(prompt.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    if let shortcut = prompt.shortcut, !shortcut.isEmpty {
                        Text("/\(shortcut)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(preview)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(prompt.usageCount == 1 ? "Used once" : "Used \(prompt.usageCount)×")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .monospacedDigit()

            HStack(spacing: 4) {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help("Edit")
                .accessibilityLabel("Edit \(prompt.name)")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .help("Delete")
                .accessibilityLabel("Delete \(prompt.name)")
            }
            .opacity(isHovered ? 1 : 0.4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(isHovered ? Color.primary.opacity(0.04) : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2, perform: onEdit)
    }
}

/// Add-or-edit sheet. Nothing is created until Save, so cancelling a new prompt leaves no empty entry.
private struct PromptEditorSheet: View {
    let prompt: PromptEntity?
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var shortcut = ""
    @State private var content = ""
    @State private var didLoad = false

    private var canSave: Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(prompt == nil ? "New Prompt" : "Edit Prompt")
                .font(.system(size: 15, weight: .semibold))

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Name").font(.system(size: 11)).foregroundStyle(.secondary)
                    TextField("e.g. Summarize", text: $name)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Shortcut").font(.system(size: 11)).foregroundStyle(.secondary)
                    HStack(spacing: 2) {
                        Text("/").foregroundStyle(.secondary)
                        TextField("summarize", text: $shortcut)
                            .textFieldStyle(.roundedBorder)
                    }
                    .frame(width: 160)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Prompt").font(.system(size: 11)).foregroundStyle(.secondary)
                TextEditor(text: $content)
                    .font(.system(size: 13))
                    .frame(minHeight: 160)
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                    )
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    save()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            if let prompt {
                name = prompt.name
                shortcut = prompt.shortcut ?? ""
                content = prompt.content
            }
        }
    }

    private func save() {
        let library = PromptLibraryManager.shared
        if let prompt {
            library.updatePrompt(prompt, name: name, content: content, shortcut: shortcut)
        } else {
            library.addPrompt(name: name, content: content, shortcut: shortcut)
        }
    }
}
