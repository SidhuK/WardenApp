
import Foundation
import CoreData

/// Service responsible for rephrasing user input using AI
class RephraseService: ObservableObject {
    @Published var isRephrasing = false
    
    init() {
        // Initialize without viewContext
    }
    
    /// The system prompt for rephrasing text
    private let systemPrompt = """
Rephrase the following sentence to improve clarity and readability, without changing its core meaning. Just return the rephrased text, no other text or comments.
"""
    
    /// Rephrases the given text using the AI service
    func rephraseText(
        _ text: String,
        using apiService: APIServiceEntity,
        completion: @escaping (Result<String, APIError>) -> Void
    ) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion(.failure(.unknown("Cannot rephrase empty text")))
            return
        }
        
        guard let config = loadAPIConfig(for: apiService) else {
            completion(.failure(.noApiService("Invalid API configuration")))
            return
        }
        
        isRephrasing = true
        
        let requestMessages = [
            [
                "role": "system",
                "content": systemPrompt
            ],
            [
                "role": "user", 
                "content": text
            ]
        ]
        
        let apiServiceInstance = APIServiceFactory.createAPIService(config: config)
        
        apiServiceInstance.sendMessage(
            requestMessages,
            temperature: 0.3 // Lower temperature for more consistent rephrasing
        ) { [weak self] result in
            DispatchQueue.main.async {
                self?.isRephrasing = false
                
                switch result {
                case .success(let (rephrasedText, _)):
                    guard let rephrasedText = rephrasedText else {
                        completion(.failure(.invalidResponse))
                        return
                    }
                    
                    // Clean up the response - remove quotes if the AI wrapped the response
                    let cleanedText = rephrasedText
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    completion(.success(cleanedText))
                    
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }
    
    private func loadAPIConfig(for service: APIServiceEntity) -> APIServiceConfiguration? {
        guard let apiServiceUrl = service.url else {
            return nil
        }
        
        var apiKey = ""
        do {
            apiKey = try TokenManager.getToken(for: service.id?.uuidString ?? "") ?? ""
        } catch {
            print("Error extracting token: \(error) for \(service.id?.uuidString ?? "")")
        }
        
        return APIServiceConfig(
            name: service.type ?? "chatgpt",
            apiUrl: apiServiceUrl,
            apiKey: apiKey,
            model: service.model ?? AppConstants.chatGptDefaultModel
        )
    }
} 
