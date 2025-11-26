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
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel = ModelSelectorViewModel()
    @StateObject private var favoriteManager = FavoriteModelsManager.shared
    @StateObject private var metadataCache = ModelMetadataCache.shared
    
    @State private var hoveredItem: String? = nil
    @State private var isCreating = false
    @State private var errorMessage: String?
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \APIServiceEntity.addedDate, ascending: false)],
        animation: .default
    )
    private var apiServices: FetchedResults<APIServiceEntity>
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            Divider()
                .opacity(0.5)
            
            if isCreating {
                creatingView
            } else if let error = errorMessage {
                errorView(error)
            } else {
                // Search bar
                searchBar
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 10)
                
                Divider()
                    .opacity(0.5)
                
                // Model list
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 4, pinnedViews: [.sectionHeaders]) {
                        ForEach(viewModel.filteredSections) { section in
                            if section.id == "favorites" {
                                Section {
                                    ForEach(section.items) { item in
                                        modelRow(item: item)
                                    }
                                } header: {
                                    sectionHeader(section.title, icon: "star.fill")
                                }
                            } else if section.id != "search" {
                                Section {
                                    ForEach(section.items) { item in
                                        modelRow(item: item)
                                    }
                                } header: {
                                    providerSectionHeader(title: section.title, provider: section.id)
                                }
                            }
                        }
                        
                        // Bottom padding
                        Spacer()
                            .frame(height: 8)
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
                }
            }
        }
        .frame(width: 360, height: 420)
        .background(Color(NSColor.controlBackgroundColor))
        .onAppear {
            viewModel.updateServices(Array(apiServices))
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack(spacing: 12) {
            // Branch icon
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
            
            // Close button
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
    
    // MARK: - Search Bar
    
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.tertiary)
            
            TextField("Search models...", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            
            if !viewModel.searchText.isEmpty {
                Button(action: { viewModel.searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.textBackgroundColor))
        )
    }
    
    // MARK: - Section Headers
    
    private func sectionHeader(_ title: String, icon: String? = nil) -> some View {
        HStack(spacing: 6) {
            if let icon = icon {
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
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private func providerSectionHeader(title: String, provider: String) -> some View {
        HStack(spacing: 6) {
            Image("logo_\(provider)")
                .resizable()
                .renderingMode(.template)
                .interpolation(.high)
                .frame(width: 12, height: 12)
                .foregroundStyle(.secondary)
            
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Model Row
    
    private func modelRow(item: ModelSelectorViewModel.ModelItem) -> some View {
        let metadata = metadataCache.getMetadata(provider: item.provider, modelId: item.modelId)
        let isReasoning = metadata?.hasReasoning ?? false
        let isVision = metadata?.hasVision ?? false
        let formattedModel = ModelMetadata.formatModelComponents(modelId: item.modelId, provider: item.provider)
        let isHovered = hoveredItem == item.id
        
        return Button(action: {
            createBranch(providerType: item.provider, model: item.modelId)
        }) {
            HStack(spacing: 10) {
                // Model info
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(formattedModel.displayName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        
                        if let provider = formattedModel.provider {
                            Text(provider)
                                .font(.system(size: 10, weight: .regular))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(
                                    Capsule()
                                        .fill(Color.primary.opacity(0.06))
                                )
                        }
                    }
                    
                    // Capabilities badges
                    if isReasoning || isVision || (metadata?.hasPricing == true) {
                        HStack(spacing: 8) {
                            if isReasoning {
                                HStack(spacing: 3) {
                                    Image(systemName: "brain")
                                        .font(.system(size: 8))
                                    Text("Reasoning")
                                        .font(.system(size: 9))
                                }
                                .foregroundStyle(.secondary)
                            }
                            if isVision {
                                HStack(spacing: 3) {
                                    Image(systemName: "eye")
                                        .font(.system(size: 8))
                                    Text("Vision")
                                        .font(.system(size: 9))
                                }
                                .foregroundStyle(.secondary)
                            }
                            if let pricing = metadata?.pricing, let inputPrice = pricing.inputPer1M {
                                Text(pricing.outputPer1M != nil
                                    ? "$\(String(format: "%.2f", inputPrice))/$\(String(format: "%.2f", pricing.outputPer1M!))/M"
                                    : "$\(String(format: "%.2f", inputPrice))/M")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                
                Spacer()
                
                // Actions
                HStack(spacing: 10) {
                    // Favorite button
                    Button(action: {
                        favoriteManager.toggleFavorite(provider: item.provider, model: item.modelId)
                    }) {
                        Image(systemName: item.isFavorite ? "star.fill" : "star")
                            .font(.system(size: 11))
                            .foregroundStyle(item.isFavorite ? Color.accentColor : Color.secondary.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    
                    // Branch action indicator
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
            withAnimation(.easeInOut(duration: 0.1)) {
                hoveredItem = hovering ? item.id : nil
            }
        }
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
