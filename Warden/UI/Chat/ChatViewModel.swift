
import Combine
import Foundation
import SwiftUI

class ChatViewModel: ObservableObject {
    @Published var messages: NSOrderedSet
    private let chat: ChatEntity
    private let viewContext: NSManagedObjectContext

    private var _messageManager: MessageManager?
    private var messageManager: MessageManager? {
        get {
            if _messageManager == nil {
                _messageManager = createMessageManager()
            }
            return _messageManager
        }
        set {
            _messageManager = newValue
        }
    }

    private var cancellables = Set<AnyCancellable>()

    init(chat: ChatEntity, viewContext: NSManagedObjectContext) {
        self.chat = chat
        self.messages = chat.messages
        self.viewContext = viewContext
    }

    func sendMessage(_ message: String, contextSize: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let messageManager = self.messageManager else {
            completion(.failure(APIError.noApiService("No valid API service configuration")))
            return
        }
        
        messageManager.sendMessage(message, in: chat, contextSize: contextSize) { [weak self] result in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    @MainActor
    func sendMessageStream(_ message: String, contextSize: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let messageManager = self.messageManager else {
            completion(.failure(APIError.noApiService("No valid API service configuration")))
            return
        }
        
        messageManager.sendMessageStream(message, in: chat, contextSize: contextSize) { [weak self] result in
            switch result {
            case .success:
                self?.chat.objectWillChange.send()
                completion(.success(()))
                self?.reloadMessages()
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    @MainActor
    func sendMessageStreamWithSearch(_ message: String, contextSize: Int, completion: @escaping (Result<Void, Error>) -> Void) async {
        guard let messageManager = self.messageManager else {
            completion(.failure(APIError.noApiService("No valid API service configuration")))
            return
        }
        
        await messageManager.sendMessageStreamWithSearch(message, in: chat, contextSize: contextSize) { [weak self] result in
            switch result {
            case .success:
                self?.chat.objectWillChange.send()
                completion(.success(()))
                self?.reloadMessages()
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    func isSearchCommand(_ message: String) -> Bool {
        return messageManager?.isSearchCommand(message).isSearch ?? false
    }

    func generateChatNameIfNeeded() {
        messageManager?.generateChatNameIfNeeded(chat: chat)
    }

    func reloadMessages() {
        messages = self.messages
    }

    var sortedMessages: [MessageEntity] {
        return self.chat.messagesArray
    }

    private func createMessageManager() -> MessageManager? {
        guard let config = self.loadCurrentAPIConfig() else {
            print("⚠️ Warning: No valid API configuration found for chat \(chat.id)")
            return nil
        }
        print("✅ Creating new MessageManager with URL: \(config.apiUrl) and model: \(config.model)")
        return MessageManager(
            apiService: APIServiceFactory.createAPIService(config: config),
            viewContext: self.viewContext
        )
    }

    func recreateMessageManager() {
        print("🔄 Recreating MessageManager for chat \(chat.id)")
        _messageManager = createMessageManager()
    }

    var canSendMessage: Bool {
        // Check if we have a valid API service and can create a message manager
        guard chat.apiService != nil else {
            return false
        }
        
        // Try to ensure we have a valid message manager
        return messageManager != nil
    }

    private func loadCurrentAPIConfig() -> APIServiceConfiguration? {
        guard let apiService = chat.apiService, 
              let apiServiceUrl: URL = apiService.url,
              !chat.gptModel.isEmpty else {
            print("⚠️ Missing required API service configuration: service=\(chat.apiService?.name ?? "nil"), url=\(chat.apiService?.url?.absoluteString ?? "nil"), model=\(chat.gptModel)")
            return nil
        }

        var apiKey = ""
        do {
            apiKey = try TokenManager.getToken(for: apiService.id?.uuidString ?? "") ?? ""
        }
        catch {
            print("⚠️ Error extracting token: \(error) for service \(apiService.id?.uuidString ?? "")")
            // Don't return nil here - some services (like Ollama) might not need API keys
        }

        let config = APIServiceConfig(
            name: getApiServiceName(),
            apiUrl: apiServiceUrl,
            apiKey: apiKey,
            model: chat.gptModel
        )
        
        return config
    }

    private func getApiServiceName() -> String {
        return chat.apiService?.type ?? "chatgpt"
    }
    
    func regenerateChatName() {
        messageManager?.generateChatNameIfNeeded(chat: chat, force: true)
    }
    
    func stopStreaming() {
        messageManager?.stopStreaming()
    }
}
