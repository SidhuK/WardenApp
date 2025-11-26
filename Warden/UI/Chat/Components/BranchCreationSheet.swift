import SwiftUI
import CoreData

/// A polished sheet for creating conversation branches.
/// Follows Apple Human Interface Guidelines for macOS with native controls.
struct BranchCreationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme
    
    // Input parameters
    let sourceMessage: MessageEntity
    let sourceChat: ChatEntity
    let origin: BranchOrigin
    let availableServices: [APIServiceEntity]
    let onBranchCreated: (ChatEntity) -> Void
    
    // State
    @State private var selectedService: APIServiceEntity?
    @State private var selectedModel: String = ""
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var showModelSelector = false
    
    // Animation
    @Namespace private var animation
    
    private var branchOriginDescription: String {
        origin == .user
            ? "Continue this conversation with a new AI response"
            : "Fork from this response and continue with your own message"
    }
    
    private var canCreateBranch: Bool {
        selectedService != nil && !selectedModel.isEmpty && !isProcessing
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Source message preview
                    sourceMessageSection
                    
                    // Model selection
                    modelSelectionSection
                    
                    // Branch info
                    branchInfoSection
                }
                .padding(20)
            }
            
            Divider()
            
            // Footer with actions
            footerView
        }
        .frame(width: 480, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear(perform: initializeSelection)
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 40, height: 40)
                
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.accentColor)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Create Branch")
                    .font(.headline)
                
                Text(branchOriginDescription)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Close button
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(isProcessing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
    
    // MARK: - Source Message Section
    
    private var sourceMessageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Branch Point", systemImage: origin == .user ? "person.fill" : "sparkles")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
            
            HStack(alignment: .top, spacing: 12) {
                // Role indicator
                ZStack {
                    Circle()
                        .fill(origin == .user ? Color.accentColor : Color.purple.opacity(0.8))
                        .frame(width: 28, height: 28)
                    
                    Image(systemName: origin == .user ? "person.fill" : "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(origin == .user ? "Your message" : "AI response")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(sourceMessage.body.prefix(200).description)
                        .font(.callout)
                        .lineLimit(3)
                        .foregroundColor(.primary)
                }
                
                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
        }
    }
    
    // MARK: - Model Selection Section
    
    private var modelSelectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("AI Model", systemImage: "cpu")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
            
            Button(action: { showModelSelector.toggle() }) {
                HStack(spacing: 12) {
                    // Provider logo
                    if let service = selectedService, let type = service.type {
                        Image("logo_\(type)")
                            .resizable()
                            .renderingMode(.template)
                            .interpolation(.high)
                            .frame(width: 20, height: 20)
                            .foregroundColor(.primary)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 20, height: 20)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        if let service = selectedService, !selectedModel.isEmpty {
                            Text(formatModelName(selectedModel))
                                .font(.body.weight(.medium))
                                .foregroundColor(.primary)
                            
                            Text(service.name ?? "Unknown Service")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Select a model...")
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: showModelSelector ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(showModelSelector ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(isProcessing)
            
            // Inline model selector
            if showModelSelector {
                modelSelectorContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showModelSelector)
    }
    
    private var modelSelectorContent: some View {
        VStack(spacing: 0) {
            if availableServices.isEmpty {
                emptyServicesView
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(availableServices, id: \.self) { service in
                            serviceSection(for: service)
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 200)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
    
    @ViewBuilder
    private func serviceSection(for service: APIServiceEntity) -> some View {
        let models = getModelsForService(service)
        
        if !models.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                // Service header
                HStack(spacing: 6) {
                    if let type = service.type {
                        Image("logo_\(type)")
                            .resizable()
                            .renderingMode(.template)
                            .interpolation(.high)
                            .frame(width: 12, height: 12)
                            .foregroundColor(.secondary)
                    }
                    
                    Text(service.name ?? "Unknown")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                
                // Models
                ForEach(models, id: \.self) { model in
                    modelRow(model: model, service: service)
                }
            }
        }
    }
    
    private func modelRow(model: String, service: APIServiceEntity) -> some View {
        let isSelected = selectedService == service && selectedModel == model
        
        return Button(action: {
            selectedService = service
            selectedModel = model
            withAnimation(.easeInOut(duration: 0.15)) {
                showModelSelector = false
            }
        }) {
            HStack {
                Text(formatModelName(model))
                    .font(.callout)
                    .foregroundColor(isSelected ? .accentColor : .primary)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private var emptyServicesView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundColor(.orange)
            
            Text("No AI Services Available")
                .font(.callout.weight(.medium))
            
            Text("Add an AI service in Settings to create branches.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
    }
    
    // MARK: - Branch Info Section
    
    private var branchInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("What happens next", systemImage: "info.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 8) {
                infoRow(
                    icon: "doc.on.doc",
                    text: "Messages up to this point will be copied"
                )
                
                if origin == .user {
                    infoRow(
                        icon: "sparkles",
                        text: "The selected AI will generate a new response"
                    )
                } else {
                    infoRow(
                        icon: "text.cursor",
                        text: "You can continue with your own message"
                    )
                }
                
                infoRow(
                    icon: "arrow.triangle.branch",
                    text: "The original conversation remains unchanged"
                )
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentColor.opacity(0.05))
            )
        }
    }
    
    private func infoRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.accentColor)
                .frame(width: 16)
            
            Text(text)
                .font(.caption)
                .foregroundColor(.primary)
        }
    }
    
    // MARK: - Footer
    
    private var footerView: some View {
        VStack(spacing: 12) {
            // Error message
            if let error = errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.red)
                    
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                    
                    Spacer()
                    
                    Button("Dismiss") {
                        errorMessage = nil
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }
            
            // Buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isProcessing)
                
                Spacer()
                
                Button(action: createBranch) {
                    HStack(spacing: 6) {
                        if isProcessing {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 14, height: 14)
                        }
                        
                        Text(isProcessing ? "Creating..." : "Create Branch")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canCreateBranch)
            }
        }
        .padding(20)
    }
    
    // MARK: - Actions
    
    private func initializeSelection() {
        // Pre-select the current chat's service if available
        if let currentService = sourceChat.apiService,
           availableServices.contains(currentService) {
            selectedService = currentService
            selectedModel = sourceChat.gptModel
        } else if let firstService = availableServices.first {
            selectedService = firstService
            let models = getModelsForService(firstService)
            selectedModel = models.first ?? firstService.model ?? ""
        }
    }
    
    private func createBranch() {
        guard let service = selectedService, !selectedModel.isEmpty else { return }
        
        errorMessage = nil
        isProcessing = true
        
        Task {
            do {
                let manager = ChatBranchingManager(viewContext: viewContext)
                let newChat = try await manager.createBranch(
                    from: sourceChat,
                    at: sourceMessage,
                    origin: origin,
                    targetService: service,
                    targetModel: selectedModel,
                    autoGenerate: origin == .user
                )
                
                await MainActor.run {
                    isProcessing = false
                    onBranchCreated(newChat)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func getModelsForService(_ service: APIServiceEntity) -> [String] {
        if let selectedModels = service.selectedModels as? [String], !selectedModels.isEmpty {
            return selectedModels
        }
        if let model = service.model, !model.isEmpty {
            return [model]
        }
        return []
    }
    
    private func formatModelName(_ model: String) -> String {
        let parts = model.split(separator: "/")
        let name = parts.count > 1 ? String(parts.last!) : model
        
        if name.count > 35 {
            return String(name.prefix(32)) + "..."
        }
        return name
    }
}

#Preview {
    Text("Preview requires Core Data context")
        .frame(width: 480, height: 520)
}
