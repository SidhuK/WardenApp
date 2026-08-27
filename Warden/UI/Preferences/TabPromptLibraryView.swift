import CoreData
import SwiftUI

/// Prompt library management inside Preferences: list, add/edit sheet, delete.
@MainActor
struct TabPromptLibraryView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \PromptEntity.category, ascending: true),
            NSSortDescriptor(keyPath: \PromptEntity.name, ascending: true),
        ],
        animation: .default
    )
    private var prompts: FetchedResults<PromptEntity>

    @State private var promptInSheet: PromptInSheet?
    @State private var newPromptSheetIsPresented = false
    @State private var promptToDelete: PromptEntity?
    @State private var showingDeleteConfirmation = false

    struct PromptInSheet: Identifiable {
        let id: NSManagedObjectID
        /// Resolve through `existingObject(with:)` so a deleted prompt yields nil
        /// instead of an unfulfillable fault that would crash the edit sheet.
        func entity(in context: NSManagedObjectContext) -> PromptEntity? {
            try? context.existingObject(with: id) as? PromptEntity
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            SettingsSectionHeader(title: "Your Prompts")
                            Spacer()
                            Button {
                                onAdd()
                            } label: {
                                Label("Add Prompt", systemImage: "plus.circle")
                            }
                            .buttonStyle(.bordered)
                        }

                        Text("Type / in any chat input to insert a prompt. Use {{text}} as a placeholder for pasted or selected content.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if prompts.isEmpty {
                            Text("No prompts yet. Add one to get started.")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 32)
                        } else {
                            promptList
                        }
                    }
                    .padding(16)
                }
            }
            .padding(20)
        }
        .sheet(item: $promptInSheet) { item in
            PromptEditSheet(prompt: item.entity(in: viewContext))
                .environment(\.managedObjectContext, viewContext)
        }
        .sheet(isPresented: $newPromptSheetIsPresented) {
            PromptEditSheet(prompt: nil)
                .environment(\.managedObjectContext, viewContext)
        }
        .confirmationDialog(
            "Delete this prompt?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let target = promptToDelete {
                    PromptLibraryManager.shared.delete(target)
                }
                promptToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                promptToDelete = nil
            }
        } message: {
            Text("This cannot be undone.")
        }
    }

    private var promptList: some View {
        VStack(spacing: 0) {
            ForEach(prompts, id: \.objectID) { prompt in
                PromptListRow(
                    prompt: prompt,
                    onEdit: { promptInSheet = PromptInSheet(id: prompt.objectID) },
                    onDelete: {
                        promptToDelete = prompt
                        showingDeleteConfirmation = true
                    }
                )
                if prompt.objectID != prompts.last?.objectID {
                    Divider().opacity(0.5)
                }
            }
        }
        .background(Color.primary.opacity(0.03))
        .cornerRadius(8)
    }

    private func onAdd() {
        // Don't create anything here — only the sheet's Save persists a new prompt.
        // Creating up front would leak an empty prompt if the user cancels.
        newPromptSheetIsPresented = true
    }
}

private struct PromptListRow: View {
    @ObservedObject var prompt: PromptEntity
    var onEdit: () -> Void
    var onDelete: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.bubble")
                .font(.system(size: 13))
                .foregroundColor(.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(prompt.commandTrigger)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))

                    if let category = prompt.category, !category.isEmpty {
                        Text(category)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.primary.opacity(0.06)))
                    }
                }

                Text(prompt.content ?? "")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if prompt.usageCount > 0 {
                Text("\(prompt.usageCount)x")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 4) {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .help("Edit")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
                .help("Delete")
            }
            .opacity(isHovered ? 1 : 0.35)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(isHovered ? Color.primary.opacity(0.04) : Color.clear)
        .onHover { isHovered = $0 }
    }
}

/// Add-or-edit sheet. Pass nil to create a fresh prompt.
private struct PromptEditSheet: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    let prompt: PromptEntity?

    @State private var name = ""
    @State private var content = ""
    @State private var shortcut = ""
    @State private var category = ""
    @State private var didLoad = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(prompt == nil ? "New Prompt" : "Edit Prompt")
                .font(.system(size: 15, weight: .semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text("Name").font(.system(size: 11)).foregroundColor(.secondary)
                TextField("e.g. Explain This", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Content").font(.system(size: 11)).foregroundColor(.secondary)
                TextEditor(text: $content)
                    .font(.system(size: 13))
                    .frame(minHeight: 140)
                    .border(Color.primary.opacity(0.15))
            }

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Shortcut (for /command)").font(.system(size: 11)).foregroundColor(.secondary)
                    TextField("explain", text: $shortcut)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Category (optional)").font(.system(size: 11)).foregroundColor(.secondary)
                    TextField("Writing", text: $category)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                }
                Spacer()
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
                .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            if let p = prompt {
                name = p.name ?? ""
                content = p.content ?? ""
                shortcut = p.shortcut ?? ""
                category = p.category ?? ""
            }
        }
    }

    private func save() {
        let trimmedShortcut = shortcut.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        if let prompt = prompt {
            prompt.name = trimmedName.isEmpty ? "Untitled Prompt" : trimmedName
            prompt.content = content
            prompt.shortcut = trimmedShortcut.isEmpty ? nil : trimmedShortcut
            prompt.category = trimmedCategory.isEmpty ? nil : trimmedCategory
        } else {
            _ = PromptLibraryManager.shared.addPrompt(
                name: trimmedName.isEmpty ? "Untitled Prompt" : trimmedName,
                content: content,
                shortcut: trimmedShortcut.isEmpty ? nil : trimmedShortcut,
                category: trimmedCategory.isEmpty ? nil : trimmedCategory
            )
        }

        do {
            try viewContext.save()
        } catch {
            WardenLog.app.error("[Prompts] Sheet save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
