import SwiftUI
import CoreData

/// Inline popover for creating conversation branches with model selection
struct BranchPopover: View {
    let sourceMessage: MessageEntity
    let sourceChat: ChatEntity
    let origin: BranchOrigin
    let onBranchCreated: (ChatEntity) -> Void
    let onDismiss: () -> Void
    
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \APIServiceEntity.addedDate, ascending: false)],
        animation: .default
    )
    private var apiServices: FetchedResults<APIServiceEntity>
    
    @State private var isCreating = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 0) {
            header
            
            Divider().opacity(0.5)
            
            if isCreating {
                creatingView
            } else if let error = errorMessage {
                errorView(error)
            } else {
                BranchModelPicker(
                    apiServices: Array(apiServices),
                    onSelect: { provider, model in
                        createBranch(providerType: provider, model: model)
                    }
                )
            }
        }
        .frame(width: 360, height: 420)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 32, height: 32)
                
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.accentColor)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Create Branch")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text(origin == .user ? "Select AI to generate response" : "Select AI to continue chat")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
    
    // MARK: - Creating State
    
    private var creatingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(0.9)
            
            VStack(spacing: 4) {
                Text("Creating branch...")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                
                Text(origin == .user ? "Generating AI response" : "Preparing conversation")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundColor(.orange)
            
            VStack(spacing: 4) {
                Text("Branch Failed")
                    .font(.system(size: 13, weight: .semibold))
                
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            
            Button(action: { errorMessage = nil }) {
                Text("Try Again")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Branch Creation
    
    private func createBranch(providerType: String, model: String) {
        guard let service = apiServices.first(where: { $0.type == providerType }) else {
            errorMessage = "Service not found"
            return
        }
        
        isCreating = true
        
        Task {
            do {
                let manager = ChatBranchingManager(viewContext: viewContext)
                let newChat = try await manager.createBranch(
                    from: sourceChat,
                    at: sourceMessage,
                    origin: origin,
                    targetService: service,
                    targetModel: model,
                    autoGenerate: origin == .user
                )
                
                await MainActor.run {
                    isCreating = false
                    onBranchCreated(newChat)
                    onDismiss()
                }
            } catch {
                await MainActor.run {
                    isCreating = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Branch Model Picker

private struct BranchModelPicker: View {
    let apiServices: [APIServiceEntity]
    let onSelect: (String, String) -> Void
    
    @ObservedObject private var modelCache = ModelCacheManager.shared
    @ObservedObject private var favoriteManager = FavoriteModelsManager.shared
    @ObservedObject private var selectedModelsManager = SelectedModelsManager.shared
    @ObservedObject private var metadataCache = ModelMetadataCache.shared
    
    private static let providerNames: [String: String] = [
        "chatgpt": "OpenAI", "claude": "Anthropic", "gemini": "Google",
        "xai": "xAI", "perplexity": "Perplexity", "deepseek": "DeepSeek",
        "groq": "Groq", "openrouter": "OpenRouter", "ollama": "Ollama", "mistral": "Mistral"
    ]
    
    private var availableModels: [(provider: String, models: [String])] {
        var result: [(provider: String, models: [String])] = []
        for service in apiServices {
            guard let serviceType = service.type else { continue }
            let serviceModels = modelCache.getModels(for: serviceType)
            
            let visibleModels = serviceModels.filter { model in
                if selectedModelsManager.hasCustomSelection(for: serviceType) {
                    return selectedModelsManager.getSelectedModelIds(for: serviceType).contains(model.id)
                }
                return true
            }
            
            if !visibleModels.isEmpty {
                result.append((provider: serviceType, models: visibleModels.map { $0.id }))
            }
        }
        return result
    }
    
    private var favoriteModels: [(provider: String, modelId: String)] {
        availableModels.flatMap { provider, models in
            models.compactMap { model in
                favoriteManager.isFavorite(provider: provider, model: model) ? (provider, model) : nil
            }
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Select a model to branch with")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                
                if !favoriteModels.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("FAVORITES")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                        
                        ForEach(favoriteModels, id: \.modelId) { item in
                            modelMenuItem(provider: item.provider, modelId: item.modelId)
                        }
                    }
                }
                
                ForEach(availableModels, id: \.provider) { providerModels in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image("logo_\(providerModels.provider)")
                                .resizable()
                                .renderingMode(.template)
                                .interpolation(.high)
                                .frame(width: 12, height: 12)
                                .foregroundStyle(.secondary)
                            
                            Text((Self.providerNames[providerModels.provider] ?? providerModels.provider.capitalized).uppercased())
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14)

                        if providerModels.provider == "openrouter" {
                            let groupedModels = ModelMetadata.groupModelIDsByNamespace(modelIds: providerModels.models)
                            ForEach(groupedModels, id: \.namespaceDisplayName) { group in
                                Text(group.namespaceDisplayName)
                                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 14)
                                    .padding(.top, 4)

                                ForEach(group.modelIds, id: \.self) { modelId in
                                    modelMenuItem(provider: providerModels.provider, modelId: modelId)
                                }
                            }
                        } else {
                            ForEach(providerModels.models, id: \.self) { modelId in
                                modelMenuItem(provider: providerModels.provider, modelId: modelId)
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 12)
        }
        .task {
            if !apiServices.isEmpty {
                modelCache.fetchAllModels(from: apiServices)
            }
        }
    }
    
    @ViewBuilder
    private func modelMenuItem(provider: String, modelId: String) -> some View {
        let displayName = ModelMetadata.formatModelDisplayName(modelId: modelId, provider: provider)
        let isFavorite = favoriteManager.isFavorite(provider: provider, model: modelId)
        let metadata = metadataCache.getMetadata(provider: provider, modelId: modelId)
        
        Menu {
            if let meta = metadata {
                if meta.hasReasoning {
                    Label("Reasoning", systemImage: "brain")
                }
                if meta.hasVision {
                    Label("Vision", systemImage: "eye")
                }
                if meta.hasFunctionCalling {
                    Label("Function Calling", systemImage: "wrench")
                }
                if let context = meta.maxContextTokens {
                    Label("\(context.formatted()) tokens", systemImage: "text.alignleft")
                }
                if let pricing = meta.pricing, let input = pricing.inputPer1M {
                    if let output = pricing.outputPer1M {
                        Label("$\(String(format: "%.2f", input)) / $\(String(format: "%.2f", output)) per 1M", systemImage: "dollarsign.circle")
                    } else {
                        Label("$\(String(format: "%.2f", input)) per 1M", systemImage: "dollarsign.circle")
                    }
                }
                if let latency = meta.latency {
                    Label(latency.rawValue.capitalized, systemImage: "speedometer")
                }
                
                Divider()
            }
            
            Button {
                favoriteManager.toggleFavorite(provider: provider, model: modelId)
            } label: {
                Label(isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: isFavorite ? "star.slash" : "star")
            }
        } label: {
            HStack(spacing: 10) {
                Text(displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                Spacer()
                
                if metadata?.hasReasoning == true {
                    Image(systemName: "brain")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                if metadata?.hasVision == true {
                    Image(systemName: "eye")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                if isFavorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.yellow)
                }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary.opacity(0.5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.001))
            .contentShape(Rectangle())
        } primaryAction: {
            onSelect(provider, modelId)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }
}
