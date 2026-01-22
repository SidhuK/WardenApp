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
    
    @State private var searchText = ""
    @State private var hoveredItem: String?
    
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
    
    private var filteredModels: [(provider: String, models: [String])] {
        guard !searchText.isEmpty else { return availableModels }
        let query = searchText.lowercased()
        return availableModels.compactMap { provider, models in
            let filtered = models.filter {
                $0.lowercased().contains(query) || provider.lowercased().contains(query)
            }
            return filtered.isEmpty ? nil : (provider, filtered)
        }
    }
    
    private var favoriteModels: [(provider: String, modelId: String)] {
        guard searchText.isEmpty else { return [] }
        return availableModels.flatMap { provider, models in
            models.compactMap { model in
                favoriteManager.isFavorite(provider: provider, model: model) ? (provider, model) : nil
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            searchBar
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 10)
            
            Divider().opacity(0.5)
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if !favoriteModels.isEmpty {
                        sectionHeader("Favorites", icon: "star.fill")
                        ForEach(favoriteModels, id: \.modelId) { item in
                            modelRow(provider: item.provider, modelId: item.modelId)
                        }
                    }
                    
                    ForEach(filteredModels, id: \.provider) { providerModels in
                        providerSectionHeader(providerModels.provider)
                        ForEach(providerModels.models, id: \.self) { modelId in
                            modelRow(provider: providerModels.provider, modelId: modelId)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 6)
                .padding(.bottom, 8)
            }
        }
        .task {
            if !apiServices.isEmpty {
                modelCache.fetchAllModels(from: apiServices)
            }
        }
    }
    
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
            
            TextField("Search models...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.textBackgroundColor)))
    }
    
    private func sectionHeader(_ title: String, icon: String? = nil) -> some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.accentColor.opacity(0.8))
            }
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
    
    private func providerSectionHeader(_ provider: String) -> some View {
        HStack(spacing: 6) {
            Image("logo_\(provider)")
                .resizable()
                .renderingMode(.template)
                .interpolation(.high)
                .frame(width: 12, height: 12)
                .foregroundStyle(.secondary)
            
            Text((Self.providerNames[provider] ?? provider.capitalized).uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
    
    @ViewBuilder
    private func modelRow(provider: String, modelId: String) -> some View {
        let metadata = metadataCache.getMetadata(provider: provider, modelId: modelId)
        let formattedModel = ModelMetadata.formatModelComponents(modelId: modelId, provider: provider)
        let isHovered = hoveredItem == "\(provider)_\(modelId)"
        let isFavorite = favoriteManager.isFavorite(provider: provider, model: modelId)
        
        Button {
            onSelect(provider, modelId)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(formattedModel.displayName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        
                        if let providerLabel = formattedModel.provider {
                            Text(providerLabel)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.primary.opacity(0.06)))
                        }
                    }
                    
                    if metadata?.hasReasoning == true || metadata?.hasVision == true || metadata?.hasPricing == true {
                        HStack(spacing: 8) {
                            if metadata?.hasReasoning == true {
                                Label("Reasoning", systemImage: "brain")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                            if metadata?.hasVision == true {
                                Label("Vision", systemImage: "eye")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                            if let pricing = metadata?.pricing, let input = pricing.inputPer1M {
                                Text("$\(String(format: "%.2f", input))/M")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                
                Spacer()
                
                HStack(spacing: 10) {
                    Button {
                        favoriteManager.toggleFavorite(provider: provider, model: modelId)
                    } label: {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .font(.system(size: 11))
                            .foregroundStyle(isFavorite ? Color.accentColor : Color.secondary.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(isHovered ? .accentColor : .secondary.opacity(0.5))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredItem = hovering ? "\(provider)_\(modelId)" : nil
        }
    }
}
