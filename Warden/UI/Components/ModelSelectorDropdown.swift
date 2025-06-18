import SwiftUI
import CoreData

struct StandaloneModelSelector: View {
    @ObservedObject var chat: ChatEntity
    @Environment(\.managedObjectContext) private var viewContext
    
    @StateObject private var modelCache = ModelCacheManager.shared
    @StateObject private var selectedModelsManager = SelectedModelsManager.shared
    @State private var isExpanded = false
    @State private var searchText = ""
    @State private var hoveredItem: String? = nil
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \APIServiceEntity.addedDate, ascending: false)],
        animation: .default
    )
    private var apiServices: FetchedResults<APIServiceEntity>
    
    private var currentProvider: String {
        chat.apiService?.type ?? "chatgpt"
    }
    
    private var currentProviderName: String {
        chat.apiService?.name ?? "No AI Service"
    }
    
    private var currentModel: String {
        chat.gptModel ?? "No Model"
    }
    
    private var availableModels: [(provider: String, models: [String])] {
        var result: [(provider: String, models: [String])] = []
        
        for service in apiServices {
            guard let serviceType = service.type else { continue }
            
            // Get cached models for this service
            let serviceModels = modelCache.getModels(for: serviceType)
            
            // Filter models based on user's visibility preferences
            let visibleModels = serviceModels.filter { model in
                // Check if there are custom selections - if not, show all models
                if selectedModelsManager.hasCustomSelection(for: serviceType) {
                    return selectedModelsManager.getSelectedModelIds(for: serviceType).contains(model.id)
                } else {
                    return true  // Show all models if no custom selection
                }
            }
            
            if !visibleModels.isEmpty {
                result.append((provider: serviceType, models: visibleModels.map { $0.id }))
            }
        }
        
        return result
    }
    
    private var filteredModels: [(provider: String, models: [String])] {
        if searchText.isEmpty {
            return availableModels
        }
        
        return availableModels.compactMap { provider, models in
            let filteredModels = models.filter { model in
                model.lowercased().contains(searchText.lowercased()) ||
                provider.lowercased().contains(searchText.lowercased())
            }
            return filteredModels.isEmpty ? nil : (provider: provider, models: filteredModels)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            selectorButton
            
            if isExpanded {
                dropdownContent
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.95).combined(with: .opacity),
                        removal: .scale(scale: 0.98).combined(with: .opacity)
                    ))
            }
        }
        .onAppear {
            modelCache.fetchAllModels(from: Array(apiServices))
        }
        .onChange(of: apiServices.count) { _, _ in
            modelCache.fetchAllModels(from: Array(apiServices))
        }
    }
    
    private var selectorButton: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }) {
            HStack(spacing: 8) {
                // Provider logo
                Image("logo_\(currentProvider)")
                    .resizable()
                    .renderingMode(.template)
                    .interpolation(.high)
                    .frame(width: 16, height: 16)
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(currentProviderName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                    
                    Text(currentModel)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 0 : 0))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    private var dropdownContent: some View {
        VStack(spacing: 0) {
            searchBar
                .padding(.horizontal, 8)
                .padding(.top, 8)
            
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredModels, id: \.provider) { providerData in
                        providerSection(provider: providerData.provider, models: providerData.models)
                    }
                }
            }
            .frame(maxHeight: 280)
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .padding(.top, 4)
    }
    
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            
            TextField("Search models...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
            
            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(NSColor.textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                )
        )
    }
    
    private func providerSection(provider: String, models: [String]) -> some View {
        VStack(spacing: 0) {
            // Provider header
            HStack(spacing: 8) {
                Image("logo_\(provider)")
                    .resizable()
                    .renderingMode(.template)
                    .interpolation(.high)
                    .frame(width: 12, height: 12)
                    .foregroundColor(.secondary)
                
                Text(getProviderDisplayName(provider))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.04))
            
            // Models
            ForEach(models, id: \.self) { model in
                modelRow(provider: provider, model: model)
            }
        }
    }
    
    private func modelRow(provider: String, model: String) -> some View {
        Button(action: {
            handleModelChange(providerType: provider, model: model)
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded = false
            }
        }) {
            HStack(spacing: 8) {
                // Current selection indicator
                Circle()
                    .fill(isCurrentlySelected(provider: provider, model: model) ? 
                          Color.accentColor : Color.clear)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .stroke(Color.primary.opacity(0.2), lineWidth: 0.5)
                    )
                
                Text(model)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Spacer()
                
                // Model type indicators
                if isReasoningModel(model) {
                    Image(systemName: "brain")
                        .font(.system(size: 9))
                        .foregroundColor(.orange)
                }
                
                if isVisionModel(provider: provider, model: model) {
                    Image(systemName: "eye")
                        .font(.system(size: 9))
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Rectangle()
                    .fill(hoveredItem == "\(provider)_\(model)" ? 
                          Color.accentColor.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredItem = hovering ? "\(provider)_\(model)" : nil
        }
    }
    
    private func isCurrentlySelected(provider: String, model: String) -> Bool {
        return chat.apiService?.type == provider && chat.gptModel == model
    }
    
    private func isReasoningModel(_ model: String) -> Bool {
        // For now, only use OpenAI reasoning models since other constants don't exist yet
        return AppConstants.openAiReasoningModels.contains(model) ||
               model.contains("reasoning") ||
               model.contains("deepseek-reasoner") ||
               model.contains("sonar-reasoning")
    }
    
    private func isVisionModel(provider: String, model: String) -> Bool {
        // This would need to be implemented based on your vision model detection logic
        return model.contains("vision") || model.contains("4o") || model.contains("claude-3")
    }
    
    private func getProviderDisplayName(_ provider: String) -> String {
        switch provider {
        case "chatgpt": return "OpenAI"
        case "claude": return "Anthropic"
        case "gemini": return "Google"
        case "xai": return "xAI"
        case "perplexity": return "Perplexity"
        case "deepseek": return "DeepSeek"
        case "groq": return "Groq"
        case "openrouter": return "OpenRouter"
        case "ollama": return "Ollama"
        case "mistral": return "Mistral"
        default: return provider.capitalized
        }
    }
    
    private func handleModelChange(providerType: String, model: String) {
        // Find the API service for this provider type
        guard let service = apiServices.first(where: { $0.type == providerType }) else {
            print("⚠️ No API service found for provider type: \(providerType)")
            return
        }
        
        // Validate that the service has required configuration
        guard let serviceUrl = service.url, !serviceUrl.absoluteString.isEmpty else {
            print("⚠️ API service \(service.name ?? "Unknown") has invalid URL")
            return
        }
        
        // Update chat configuration
        chat.apiService = service
        chat.gptModel = model
        
        print("🔄 Model changed to \(providerType)/\(model) for chat \(chat.id)")
        
        do {
            try viewContext.save()
            
            // Send notification that model changed
            NotificationCenter.default.post(
                name: NSNotification.Name("RecreateMessageManager"),
                object: nil,
                userInfo: ["chatId": chat.id]
            )
            
            print("✅ Model change saved and notification sent")
        } catch {
            print("❌ Failed to save model change: \(error)")
        }
    }
}

#Preview {
    StandaloneModelSelector(chat: PreviewStateManager.shared.sampleChat)
        .environmentObject(PreviewStateManager.shared.chatStore)
        .environment(\.managedObjectContext, PreviewStateManager.shared.persistenceController.container.viewContext)
}

// Keep the original ModelSelectorDropdown as a simple placeholder
struct ModelSelectorDropdown: View {
    @Binding var selectedProvider: String
    @Binding var selectedModel: String
    @Binding var isVisible: Bool
    let chat: ChatEntity?
    let onModelChange: (String, String) -> Void
    
    var body: some View {
        VStack {
            Text("Model Selector")
                .font(.headline)
            Text("Coming Soon")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// Simple model row component
struct ModelRowView: View {
    let provider: String
    let model: AIModel
    let isSelected: Bool
    let isHovered: Bool
    let onTap: () -> Void
    let onHover: (Bool) -> Void
    
    var body: some View {
        HStack {
            Text(model.id)
                .font(.system(size: 11))
                .foregroundColor(isSelected ? .accentColor : .primary)
            
            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onHover { onHover($0) }
    }
}

// Preview
struct StandaloneModelSelector_Previews: PreviewProvider {
    static var previews: some View {
        StandaloneModelSelector(chat: PreviewStateManager.shared.sampleChat)
            .frame(width: 300)
            .padding()
            .environmentObject(PreviewStateManager.shared.chatStore)
    }
} 
