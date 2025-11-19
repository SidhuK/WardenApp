import SwiftUI
import CoreData

struct FavoriteQuickAccessBar: View {
    @ObservedObject var chat: ChatEntity
    @Environment(\.managedObjectContext) private var viewContext
    
    @StateObject private var modelCache = ModelCacheManager.shared
    @StateObject private var favoriteManager = FavoriteModelsManager.shared
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \APIServiceEntity.addedDate, ascending: false)],
        animation: .default
    )
    private var apiServices: FetchedResults<APIServiceEntity>
    
    private var topFavorites: [(provider: String, model: String)] {
        let allFavorites = favoriteManager.getAllFavorites()
        return Array(allFavorites.prefix(4))
    }
    
    private var shouldShow: Bool {
        !topFavorites.isEmpty
    }
    
    var body: some View {
        if shouldShow {
            HStack(spacing: 6) {
                ForEach(topFavorites, id: \.model) { favorite in
                    favoriteButton(provider: favorite.provider, model: favorite.model)
                }
            }
        }
    }
    
    private func favoriteButton(provider: String, model: String) -> some View {
        Button(action: {
            handleModelChange(providerType: provider, model: model)
        }) {
            HStack(spacing: 6) {
                Image("logo_\(provider)")
                    .resizable()
                    .renderingMode(.template)
                    .interpolation(.high)
                    .frame(width: 12, height: 12)
                    .foregroundColor(.white)
                
                Text(model)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isCurrentlySelected(provider: provider, model: model) ? 
                          Color.accentColor : Color.blue.opacity(0.8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                isCurrentlySelected(provider: provider, model: model) ? 
                                    Color.accentColor.opacity(0.6) : Color.blue.opacity(0.4), 
                                lineWidth: 1.0
                            )
                    )
            )
            .help("Switch to \(model)")
        }
        .buttonStyle(.plain)
    }
    
    private func isCurrentlySelected(provider: String, model: String) -> Bool {
        return chat.apiService?.type == provider && chat.gptModel == model
    }
    
    private func handleModelChange(providerType: String, model: String) {
        guard let service = apiServices.first(where: { $0.type == providerType }) else {
            print("⚠️ No API service found for provider type: \(providerType)")
            return
        }
        
        guard let serviceUrl = service.url, !serviceUrl.absoluteString.isEmpty else {
            print("⚠️ API service \(service.name ?? "Unknown") has invalid URL")
            return
        }
        
        chat.apiService = service
        chat.gptModel = model
        
        print("🔄 Model changed to \(providerType)/\(model) via quick access bar")
        
        do {
            try viewContext.save()
            
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
    FavoriteQuickAccessBar(chat: PreviewStateManager.shared.sampleChat)
        .environmentObject(PreviewStateManager.shared.chatStore)
        .environment(\.managedObjectContext, PreviewStateManager.shared.persistenceController.container.viewContext)
}
