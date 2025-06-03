
import Foundation

/// Simple test to verify FavoriteModelsManager functionality
class FavoriteModelsManagerTest {
    
    static func runTests() {
        print("🧪 Running FavoriteModelsManager Tests...")
        
        let manager = FavoriteModelsManager.shared
        
        // Clear any existing favorites
        manager.clearAllFavorites()
        assert(manager.favoriteModels.isEmpty, "❌ Clear favorites failed")
        print("✅ Clear favorites test passed")
        
        // Test adding favorites
        manager.addFavorite(provider: "chatgpt", model: "gpt-4o")
        manager.addFavorite(provider: "claude", model: "claude-3-5-sonnet-20241022")
        assert(manager.favoriteModels.count == 2, "❌ Add favorites failed")
        print("✅ Add favorites test passed")
        
        // Test checking if favorite
        assert(manager.isFavorite(provider: "chatgpt", model: "gpt-4o"), "❌ isFavorite check failed")
        assert(!manager.isFavorite(provider: "chatgpt", model: "gpt-3.5-turbo"), "❌ isFavorite negative check failed")
        print("✅ isFavorite test passed")
        
        // Test toggle favorite
        manager.toggleFavorite(provider: "chatgpt", model: "gpt-3.5-turbo")
        assert(manager.isFavorite(provider: "chatgpt", model: "gpt-3.5-turbo"), "❌ Toggle favorite (add) failed")
        
        manager.toggleFavorite(provider: "chatgpt", model: "gpt-4o")
        assert(!manager.isFavorite(provider: "chatgpt", model: "gpt-4o"), "❌ Toggle favorite (remove) failed")
        print("✅ Toggle favorite test passed")
        
        // Test get all favorites
        let allFavorites = manager.getAllFavorites()
        assert(allFavorites.count == 2, "❌ Get all favorites count failed")
        print("✅ Get all favorites test passed")
        
        // Test get favorites for provider
        let chatgptFavorites = manager.getFavorites(for: "chatgpt")
        assert(chatgptFavorites.count == 1, "❌ Get provider favorites failed")
        assert(chatgptFavorites.contains("gpt-3.5-turbo"), "❌ Get provider favorites content failed")
        print("✅ Get provider favorites test passed")
        
        // Clean up
        manager.clearAllFavorites()
        
        print("🎉 All FavoriteModelsManager tests passed!")
    }
} 