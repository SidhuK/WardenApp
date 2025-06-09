import SwiftUI
import CoreData

struct ProjectSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var store: ChatStore
    
    @ObservedObject var project: ProjectEntity
    
    @State private var projectName: String = ""
    @State private var projectDescription: String = ""
    @State private var customInstructions: String = ""
    @State private var selectedColor: String = "#007AFF"
    @State private var showingDeleteConfirmation = false
    
    // Predefined color options (same as CreateProjectView)
    private let colorOptions: [String] = [
        "#007AFF", // Blue
        "#34C759", // Green
        "#FF9500", // Orange
        "#FF3B30", // Red
        "#AF52DE", // Purple
        "#FF2D92", // Pink
        "#5AC8FA", // Light Blue
        "#FFCC00", // Yellow
        "#8E8E93", // Gray
        "#32D74B", // Mint
        "#FF6B35", // Coral
        "#6C7CE0"  // Indigo
    ]
    
    private var isValidInput: Bool {
        !projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private var hasChanges: Bool {
        let trimmedName = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = projectDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedInstructions = customInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return trimmedName != project.name ||
               trimmedDescription != (project.projectDescription ?? "") ||
               trimmedInstructions != (project.customInstructions ?? "") ||
               selectedColor != project.colorCode
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header with project info
                    headerSection
                    
                    // Project Details
                    detailsSection
                    
                    // Color Selection
                    colorSection
                    
                    // Custom Instructions
                    instructionsSection
                    
                    // AI Summary Section
                    summarySection
                    
                    // Danger Zone
                    dangerZoneSection
                    
                    Spacer(minLength: 100)
                }
                .padding(24)
            }
            .navigationTitle("Project Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                    .disabled(!isValidInput || !hasChanges)
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .frame(width: 600, height: 800)
        .onAppear {
            loadProjectData()
        }
        .alert("Delete Project", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteProject()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            let chatCount = project.chats?.count ?? 0
            Text(chatCount > 0 ?
                "This project contains \(chatCount) chat\(chatCount == 1 ? "" : "s"). The chats will be moved to \"No Project\" and won't be deleted." :
                "This action cannot be undone."
            )
        }
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(Color(hex: selectedColor) ?? .accentColor)
                    .frame(width: 24, height: 24)
                
                Text(project.name ?? "Untitled Project")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                // Archive/Unarchive button
                Button(project.isArchived ? "Unarchive" : "Archive") {
                    if project.isArchived {
                        store.unarchiveProject(project)
                    } else {
                        store.archiveProject(project)
                    }
                }
                .foregroundColor(project.isArchived ? .accentColor : .orange)
            }
            
            HStack {
                if let chatCount = project.chats?.count, chatCount > 0 {
                    Label("\(chatCount) chat\(chatCount == 1 ? "" : "s")", systemImage: "message")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let createdAt = project.createdAt {
                    Label("Created \(createdAt, style: .relative)", systemImage: "calendar")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            if let lastSummarized = project.lastSummarizedAt {
                Text("Last summarized \(lastSummarized, style: .relative)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
    
    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Project Details")
                .font(.headline)
                .fontWeight(.medium)
            
            VStack(alignment: .leading, spacing: 12) {
                // Project Name
                VStack(alignment: .leading, spacing: 6) {
                    Text("Project Name")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    TextField("Enter project name", text: $projectName)
                        .textFieldStyle(.roundedBorder)
                }
                
                // Project Description
                VStack(alignment: .leading, spacing: 6) {
                    Text("Description (Optional)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    TextField("Brief description of the project", text: $projectDescription, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
        }
    }
    
    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Project Color")
                .font(.headline)
                .fontWeight(.medium)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                ForEach(colorOptions, id: \.self) { colorHex in
                    ColorOption(
                        colorHex: colorHex,
                        isSelected: selectedColor == colorHex,
                        onSelect: {
                            selectedColor = colorHex
                        }
                    )
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
        }
    }
    
    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Custom Instructions")
                    .font(.headline)
                    .fontWeight(.medium)
                
                Spacer()
                
                if !customInstructions.isEmpty {
                    Button("Clear") {
                        customInstructions = ""
                    }
                    .font(.caption)
                    .foregroundColor(.accentColor)
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("These instructions are applied to all chats in this project, providing context-specific guidance to the AI.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                TextEditor(text: $customInstructions)
                    .font(.system(.body, design: .monospaced))
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(NSColor.textBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                            )
                    )
                    .frame(minHeight: 120)
            }
        }
    }
    
    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("AI Summary")
                    .font(.headline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Button("Refresh") {
                    // TODO: Trigger AI summarization
                    print("Refreshing project summary")
                }
                .foregroundColor(.accentColor)
                .disabled(true) // Disabled until AI integration is complete
            }
            
            VStack(alignment: .leading, spacing: 8) {
                if let summary = project.aiGeneratedSummary, !summary.isEmpty {
                    Text(summary)
                        .font(.body)
                        .foregroundColor(.primary)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(hex: selectedColor)?.opacity(0.05) ?? Color.accentColor.opacity(0.05))
                        )
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.text")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        
                        Text("No summary yet")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Text("AI summaries will be generated automatically as you add chats to this project.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(24)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.primary.opacity(0.05))
                    )
                }
            }
        }
    }
    
    private var dangerZoneSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Danger Zone")
                .font(.headline)
                .fontWeight(.medium)
                .foregroundColor(.red)
            
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Delete Project")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Text("Permanently delete this project. Chats will be moved to \"No Project\".")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button("Delete") {
                        showingDeleteConfirmation = true
                    }
                    .foregroundColor(.red)
                    .buttonStyle(.bordered)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.red.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.red.opacity(0.2), lineWidth: 1)
                    )
            )
        }
    }
    
    private func loadProjectData() {
        projectName = project.name ?? ""
        projectDescription = project.projectDescription ?? ""
        customInstructions = project.customInstructions ?? ""
        selectedColor = project.colorCode ?? "#007AFF"
    }
    
    private func saveChanges() {
        let trimmedName = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = projectDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedInstructions = customInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        
        store.updateProject(
            project,
            name: trimmedName,
            description: trimmedDescription.isEmpty ? nil : trimmedDescription,
            colorCode: selectedColor,
            customInstructions: trimmedInstructions.isEmpty ? nil : trimmedInstructions
        )
        
        dismiss()
    }
    
    private func deleteProject() {
        store.deleteProject(project)
        dismiss()
    }
}

// Reuse ColorOption from CreateProjectView
extension ProjectSettingsView {
    struct ColorOption: View {
        let colorHex: String
        let isSelected: Bool
        let onSelect: () -> Void
        
        private var color: Color {
            Color(hex: colorHex) ?? .accentColor
        }
        
        var body: some View {
            Button(action: onSelect) {
                Circle()
                    .fill(color)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Circle()
                            .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                    )
                    .overlay(
                        Group {
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                            }
                        }
                    )
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
}

#Preview {
    if let project = PreviewStateManager.shared.sampleProject {
        ProjectSettingsView(project: project)
            .environmentObject(PreviewStateManager.shared.chatStore)
            .environment(\.managedObjectContext, PreviewStateManager.shared.persistenceController.container.viewContext)
    } else {
        Text("No sample project available")
    }
} 