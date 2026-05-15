import Foundation
import Security
import os

class TavilyKeyManager {
    static let shared = TavilyKeyManager()
    
    private let legacyTavilyService = "com.warden.tavily"
    
    private init() {}
    
    // MARK: - Save API Key
    
    func saveApiKey(_ apiKey: String, for provider: WebSearchProvider = .tavily) -> Bool {
        let trimmedApiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedApiKey.isEmpty else {
            return deleteApiKey(for: provider)
        }

        guard let data = trimmedApiKey.data(using: .utf8) else {
            return false
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service(for: provider),
            kSecAttrAccount as String: account(for: provider),
            kSecValueData as String: data
        ]
        
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        #if DEBUG
        if status == errSecSuccess {
            WardenLog.app.debug("\(provider.displayName, privacy: .public) API key saved successfully")
        } else {
            WardenLog.app.debug(
                "Failed to save \(provider.displayName, privacy: .public) API key (status: \(status, privacy: .public))"
            )
        }
        #endif
        
        return status == errSecSuccess
    }
    
    // MARK: - Retrieve API Key
    
    func getApiKey(for provider: WebSearchProvider = .tavily) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service(for: provider),
            kSecAttrAccount as String: account(for: provider),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let apiKey = String(data: data, encoding: .utf8) else {
            #if DEBUG
            if status != errSecItemNotFound {
                WardenLog.app.debug(
                    "Failed to retrieve \(provider.displayName, privacy: .public) API key (status: \(status, privacy: .public))"
                )
            }
            #endif
            return nil
        }
        
        let trimmedApiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedApiKey.isEmpty ? nil : trimmedApiKey
    }
    
    // MARK: - Delete API Key
    
    func deleteApiKey(for provider: WebSearchProvider = .tavily) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service(for: provider),
            kSecAttrAccount as String: account(for: provider)
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        #if DEBUG
        if status == errSecSuccess {
            WardenLog.app.debug("\(provider.displayName, privacy: .public) API key deleted successfully")
        } else if status != errSecItemNotFound {
            WardenLog.app.debug(
                "Failed to delete \(provider.displayName, privacy: .public) API key (status: \(status, privacy: .public))"
            )
        }
        #endif
        
        return status == errSecSuccess || status == errSecItemNotFound
    }
    
    // MARK: - Check if API Key Exists
    
    func hasApiKey(for provider: WebSearchProvider = .tavily) -> Bool {
        return getApiKey(for: provider) != nil
    }

    private func service(for provider: WebSearchProvider) -> String {
        switch provider {
        case .tavily:
            return legacyTavilyService
        case .exa:
            return "com.warden.exa"
        }
    }

    private func account(for provider: WebSearchProvider) -> String {
        switch provider {
        case .tavily:
            return "tavily-api-key"
        case .exa:
            return "exa-api-key"
        }
    }
}
