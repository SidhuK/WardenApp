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
    @State private var selectedTemplate: ProjectTemplate = .none
    
    let onProjectCreated: (ProjectEntity) -> Void
    
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
    
    enum ProjectTemplate: String, CaseIterable {
        case none = "None"
        case codeReview = "Code Review"
        case research = "Research"
        case writing = "Writing"
        case creative = "Creative"
        case learning = "Learning"
        
        var instructions: String {
            switch self {
            case .none:
                return ""
            case .codeReview:
                return "You are helping with code review and software development. Focus on best practices, security, performance, and maintainability. Provide constructive feedback and suggest improvements."
            case .research:
                return "You are assisting with research and analysis. Help gather information, analyze data, synthesize findings, and provide well-reasoned conclusions. Cite sources when possible."
            case .writing:
                return "You are helping with writing and content creation. Focus on clarity, structure, grammar, and engaging storytelling. Adapt your style to the intended audience and purpose."
            case .creative:
                return "You are assisting with creative projects. Encourage innovation, brainstorming, and artistic expression. Help develop ideas and provide constructive creative feedback."
            case .learning:
                return "You are a learning companion. Break down complex topics, provide examples, answer questions patiently, and adapt explanations to the learner's level of understanding."
            }
        }
        
        var description: String {
            switch self {
            case .none:
                return "Start with a blank project"
            case .codeReview:
                return "For reviewing code, debugging, and development discussions"
            case .research:
                return "For research projects, data analysis, and information gathering"
            case .writing:
                return "For writing projects, content creation, and editing"
            case .creative:
                return "For creative projects, brainstorming, and artistic endeavors"
            case .learning:
                return "For educational content, tutorials, and learning sessions"
            }
        }
        
        var icon: String {
            switch self {
            case .none:
                return "folder"
            case .codeReview:
                return "chevron.left.forwardslash.chevron.right"
            case .research:
                return "doc.text.magnifyingglass"
            case .writing:
                return "pencil.and.outline"
            case .creative:
                return "paintbrush"
            case .learning:
                return "graduationcap"
            }
        }
    }
    
    private var isValidInput: Bool {
        !projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        NavigationView {
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
            .navigationTitle("Create Project")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createProject()
                    }
                    .disabled(!isValidInput)
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .frame(width: 600, height: 700)
        .onChange(of: selectedTemplate) { _, newValue in
            if newValue != .none {
                customInstructions = newValue.instructions
            }
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
            Text("Project Template")
                .font(.headline)
                .fontWeight(.medium)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                ForEach(ProjectTemplate.allCases, id: \.self) { template in
                    TemplateCard(
                        template: template,
                        isSelected: selectedTemplate == template,
                        onSelect: {
                            selectedTemplate = template
                        }
                    )
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
                        selectedTemplate = .none
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

struct TemplateCard: View {
    let template: CreateProjectView.ProjectTemplate
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: template.icon)
                        .font(.title3)
                        .foregroundColor(isSelected ? .accentColor : .primary)
                    
                    Spacer()
                    
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.accentColor)
                    }
                }
                
                Text(template.rawValue)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text(template.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
            }
            .padding(12)
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
    CreateProjectView(onProjectCreated: { _ in })
        .environmentObject(PreviewStateManager.shared.chatStore)
        .environment(\.managedObjectContext, PreviewStateManager.shared.persistenceController.container.viewContext)
} 