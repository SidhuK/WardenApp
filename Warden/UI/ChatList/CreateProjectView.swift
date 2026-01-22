import SwiftUI
import CoreData

struct CreateProjectView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var store: ChatStore
    
    @State private var projectName: String = ""
    @State private var projectDescription: String = ""
    @State private var customInstructions: String = ""
    @State private var selectedColor: String = "#007AFF"
    @State private var selectedTemplate: AppConstants.ProjectTemplate?
    @State private var selectedCategory: AppConstants.ProjectTemplate.ProjectTemplateCategory = .professional
    @State private var searchText: String = ""
    
    let onProjectCreated: (ProjectEntity) -> Void
    let onCancel: () -> Void
    
    private let colorOptions: [String] = [
        "#007AFF", "#34C759", "#FF9500", "#FF3B30",
        "#AF52DE", "#FF2D92", "#5AC8FA", "#FFCC00",
        "#8E8E93", "#32D74B", "#FF6B35", "#6C7CE0"
    ]
    
    private var filteredTemplates: [AppConstants.ProjectTemplate] {
        var templates = AppConstants.ProjectTemplatePresets.templatesByCategory[selectedCategory] ?? []
        if !searchText.isEmpty {
            templates = templates.filter { template in
                template.name.localizedCaseInsensitiveContains(searchText) ||
                template.description.localizedCaseInsensitiveContains(searchText) ||
                template.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
        }
        return templates
    }
    
    private var isValidInput: Bool {
        !projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Form {
                templateSection
                detailsSection
                colorSection
                instructionsSection
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            
            Divider()
            
            HStack {
                Button("Cancel") {
                    onCancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Create Project") {
                    createProject()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValidInput)
            }
            .padding()
        }
        .frame(width: 520, height: 600)
        .onChange(of: selectedTemplate) { _, newValue in
            if let template = newValue {
                if !template.name.isEmpty { projectName = template.name }
                if !template.customInstructions.isEmpty { customInstructions = template.customInstructions }
                if !template.colorCode.isEmpty { selectedColor = template.colorCode }
                if projectDescription.isEmpty && !template.description.isEmpty {
                    projectDescription = template.description
                }
            }
        }
    }
    
    // MARK: - Template Section
    
    private var templateSection: some View {
        Section {
            Picker("Category", selection: $selectedCategory) {
                ForEach(AppConstants.ProjectTemplate.ProjectTemplateCategory.allCases, id: \.self) { category in
                    Label(category.rawValue, systemImage: category.icon)
                        .tag(category)
                }
            }
            
            if AppConstants.ProjectTemplatePresets.allTemplates.count > 6 {
                TextField("Search templates", text: $searchText)
            }
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                TemplateCard(
                    title: "Custom",
                    icon: "folder",
                    description: "Start from scratch",
                    color: .secondary,
                    isSelected: selectedTemplate == nil
                ) {
                    selectedTemplate = nil
                }
                
                ForEach(filteredTemplates, id: \.id) { template in
                    TemplateCard(
                        title: template.name,
                        icon: template.icon,
                        description: template.description,
                        color: Color(hex: template.colorCode) ?? .accentColor,
                        isSelected: selectedTemplate?.id == template.id
                    ) {
                        selectedTemplate = template
                    }
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Template")
        }
    }
    
    // MARK: - Details Section
    
    private var detailsSection: some View {
        Section {
            TextField("Project Name", text: $projectName)
            TextField("Description (optional)", text: $projectDescription, axis: .vertical)
                .lineLimit(2...3)
        } header: {
            Text("Details")
        }
    }
    
    // MARK: - Color Section
    
    private var colorSection: some View {
        Section {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 8) {
                ForEach(colorOptions, id: \.self) { hex in
                    Button {
                        selectedColor = hex
                    } label: {
                        Circle()
                            .fill(Color(hex: hex) ?? .accentColor)
                            .frame(width: 28, height: 28)
                            .overlay {
                                if selectedColor == hex {
                                    Image(systemName: "checkmark")
                                        .font(.caption.bold())
                                        .foregroundStyle(.white)
                                }
                            }
                            .overlay {
                                Circle()
                                    .strokeBorder(selectedColor == hex ? Color.primary : Color.clear, lineWidth: 2)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Color")
        }
    }
    
    // MARK: - Instructions Section
    
    private var instructionsSection: some View {
        Section {
            TextEditor(text: $customInstructions)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 80)
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } header: {
            HStack {
                Text("Custom Instructions")
                Spacer()
                if !customInstructions.isEmpty {
                    Button("Clear") {
                        customInstructions = ""
                        selectedTemplate = nil
                    }
                    .font(.caption)
                }
            }
        } footer: {
            Text("Applied to all chats in this project.")
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Actions
    
    private func createProject() {
        let trimmedName = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = projectDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedInstructions = customInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let project = store.createProject(
            name: trimmedName,
            description: trimmedDescription.isEmpty ? nil : trimmedDescription,
            colorCode: selectedColor,
            customInstructions: trimmedInstructions.isEmpty ? nil : trimmedInstructions
        )
        
        onProjectCreated(project)
        dismiss()
    }
}

// MARK: - Template Card

private struct TemplateCard: View {
    let title: String
    let icon: String
    let description: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void
    
    private var cardBackground: Color {
        isSelected ? Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor)
    }
    
    private var borderColor: Color {
        isSelected ? Color.accentColor : Color.primary.opacity(0.1)
    }
    
    var body: some View {
        Button(action: action) {
            cardContent
        }
        .buttonStyle(.plain)
    }
    
    private var cardContent: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(borderColor, lineWidth: 1)
        )
    }
}

#Preview {
    CreateProjectView(onProjectCreated: { _ in }, onCancel: {})
        .environmentObject(PreviewStateManager.shared.chatStore)
        .environment(\.managedObjectContext, PreviewStateManager.shared.persistenceController.container.viewContext)
}
