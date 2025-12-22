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
    
    // Predefined color options
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
        VStack {
            // Toolbar
            HStack {
                Button("Cancel") {
                    onCancel()
                }
                
                Spacer()
                
                Text("Create Project")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Create") {
                    createProject()
                }
                .disabled(!isValidInput)
                .buttonStyle(.borderedProminent)
            }
            .padding()
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    headerSection
                    
                    // Project Template Selection
                    templateSection
                    
                    // Project Details
                    detailsSection
                    
                    // Color Selection
                    colorSection
                    
                    // Custom Instructions
                    instructionsSection
                    
                    Spacer(minLength: 100)
                }
                .padding(24)
            }
        }
        .onChange(of: selectedTemplate) { _, newValue in
            if let template = newValue {
                // formatting check
                if !template.name.isEmpty { projectName = template.name }
                if !template.customInstructions.isEmpty { customInstructions = template.customInstructions }
                if !template.colorCode.isEmpty { selectedColor = template.colorCode }
                if projectDescription.isEmpty && !template.description.isEmpty {
                    projectDescription = template.description
                }
            }
            // If nil (Custom), do NOT clear fields. Keep user input.
        }

    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "folder.badge.plus")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                
                Text("New Project")
                    .font(.title2)
                    .fontWeight(.semibold)
            }
            
            Text("Create a new project to organize related chats and set custom AI instructions.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    private var templateSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Project Template")
                    .font(.headline)
                    .fontWeight(.medium)
                
                Spacer()
                
                // Template category picker
                Picker("Category", selection: $selectedCategory) {
                    ForEach(AppConstants.ProjectTemplate.ProjectTemplateCategory.allCases, id: \.self) { category in
                        Label(category.rawValue, systemImage: category.icon)
                            .tag(category)
                    }
                }
                .pickerStyle(.menu)
            }
            
            // Search bar for templates
            if AppConstants.ProjectTemplatePresets.allTemplates.count > 6 {
                TextField("Search templates...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
            }
            
            // Featured templates section
            if selectedCategory == .professional && searchText.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Featured Templates")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                        ForEach(AppConstants.ProjectTemplatePresets.featuredTemplates, id: \.id) { template in
                            AdvancedTemplateCard(
                                template: template,
                                isSelected: selectedTemplate?.id == template.id,
                                onSelect: {
                                    selectedTemplate = template
                                }
                            )
                        }
                    }
                }
            }
            
            // Category templates
            VStack(alignment: .leading, spacing: 12) {
                if !filteredTemplates.isEmpty {
                    Text("\(selectedCategory.rawValue) Templates")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                        // "None/Custom" option
                        CustomTemplateCard(
                            isSelected: selectedTemplate == nil,
                            onSelect: {
                                selectedTemplate = nil
                                // Do not clear fields when selecting Custom
                            }
                        )
                        
                        ForEach(filteredTemplates, id: \.id) { template in
                            AdvancedTemplateCard(
                                template: template,
                                isSelected: selectedTemplate?.id == template.id,
                                onSelect: {
                                    selectedTemplate = template
                                }
                            )
                        }
                    }
                } else if !searchText.isEmpty {
                    Text("No templates found for '\(searchText)'")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 20)
                }
            }
        }
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
                        selectedTemplate = nil
                    }
                    .font(.caption)
                    .foregroundColor(.accentColor)
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("These instructions will be applied to all chats in this project, providing context-specific guidance to the AI.")
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

struct AdvancedTemplateCard: View {
    let template: AppConstants.ProjectTemplate
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 12) {
                // Header with icon and selection indicator
                HStack {
                    Image(systemName: template.icon)
                        .font(.title3)
                        .foregroundColor(Color(hex: template.colorCode) ?? .accentColor)
                    
                    Spacer()
                    
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.accentColor)
                    }
                }
                
                // Template name and category
                VStack(alignment: .leading, spacing: 4) {
                    Text(template.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    
                    Text(template.category.rawValue)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                }
                
                // Description
                Text(template.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                
                // Tags and usage level
                HStack {
                    if !template.tags.isEmpty {
                        HStack(spacing: 2) {
                            ForEach(template.tags.prefix(2), id: \.self) { tag in
                                Text(tag)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.secondary.opacity(0.1))
                                    .cornerRadius(3)
                            }
                            if template.tags.count > 2 {
                                Text("+\(template.tags.count - 2)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Usage level indicator
                    HStack(spacing: 2) {
                        ForEach(0..<4) { index in
                            Circle()
                                .fill(index < usageLevelDots ? Color.accentColor : Color.secondary.opacity(0.3))
                                .frame(width: 4, height: 4)
                        }
                    }
                }
                

            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var usageLevelDots: Int {
        switch template.estimatedUsage {
        case .beginner: return 1
        case .intermediate: return 2
        case .advanced: return 3
        case .expert: return 4
        }
    }
}

struct CustomTemplateCard: View {
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "folder")
                        .font(.title3)
                        .foregroundColor(isSelected ? .accentColor : .primary)
                    
                    Spacer()
                    
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.accentColor)
                    }
                }
                
                Text("Custom Project")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text("Start with a blank project and customize everything yourself")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                
                HStack {
                    Text("custom")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(3)
                    
                    Spacer()
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}



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

#Preview {
    CreateProjectView(onProjectCreated: { _ in }, onCancel: {})
        .environmentObject(PreviewStateManager.shared.chatStore)
        .environment(\.managedObjectContext, PreviewStateManager.shared.persistenceController.container.viewContext)
} 