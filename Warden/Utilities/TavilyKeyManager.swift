import Foundation
import Security
import os

class TavilyKeyManager {
    static let shared = TavilyKeyManager()
    
    private let service = "com.warden.tavily"
    private let account = "tavily-api-key"
    
    private init() {}
    
    // MARK: - Save API Key
    
    func saveApiKey(_ apiKey: String) -> Bool {
        guard let data = apiKey.data(using: .utf8) else {
            return false
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        #if DEBUG
        if status == errSecSuccess {
            WardenLog.app.debug("Tavily API key saved successfully")
        } else {
            WardenLog.app.debug("Failed to save Tavily API key (status: \(status, privacy: .public))")
        }
        #endif
        
        return status == errSecSuccess
    }
    
    // MARK: - Retrieve API Key
    
    func getApiKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
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
                WardenLog.app.debug("Failed to retrieve Tavily API key (status: \(status, privacy: .public))")
            }
            #endif
            return nil
        }
        
        return apiKey
    }
    
    // MARK: - Delete API Key
    
    func deleteApiKey() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        #if DEBUG
        if status == errSecSuccess {
            WardenLog.app.debug("Tavily API key deleted successfully")
        } else if status != errSecItemNotFound {
            WardenLog.app.debug("Failed to delete Tavily API key (status: \(status, privacy: .public))")
        }
        #endif
        
        return status == errSecSuccess || status == errSecItemNotFound
    }
    
    // MARK: - Check if API Key Exists
    
    func hasApiKey() -> Bool {
        return getApiKey() != nil
    }
}
