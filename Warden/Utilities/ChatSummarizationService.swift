import Foundation
import CoreData

/// Service responsible for generating AI-powered summaries for individual chats
/// Provides concise summaries, topic extraction, and key insights identification
class ChatSummarizationService: ObservableObject {
    private let chatStore: ChatStore
    private let apiServiceManager: APIServiceManager
    
    @Published var isGeneratingSummary = false
    @Published var lastSummarizationError: String?
    
    /// Available summarization lengths
    enum SummaryLength: String, CaseIterable {
        case brief = "brief"
        case standard = "standard"
        case detailed = "detailed"
        
        var description: String {
            switch self {
            case .brief:
                return "Brief (1-2 sentences)"
            case .standard:
                return "Standard (1 paragraph)"
            case .detailed:
                return "Detailed (2-3 paragraphs)"
            }
        }
        
        var maxTokens: Int {
            switch self {
            case .brief:
                return 100
            case .standard:
                return 300
            case .detailed:
                return 600
            }
        }
    }
    
    init(chatStore: ChatStore, apiServiceManager: APIServiceManager) {
        self.chatStore = chatStore
        self.apiServiceManager = apiServiceManager
    }
    
    // MARK: - Public Methods
    
    /// Generates a summary for a specific chat
    /// - Parameters:
    ///   - chat: The chat to summarize
    ///   - length: Desired summary length
    ///   - forceRefresh: Whether to regenerate even if recent summary exists
    /// - Returns: Generated summary text
    @MainActor
    func generateChatSummary(for chat: ChatEntity, length: SummaryLength = .standard, forceRefresh: Bool = false) async throws -> String {
        // Check if we need to regenerate summary
        if !forceRefresh && shouldUseExistingSummary(for: chat) {
            return chat.aiGeneratedSummary ?? ""
        }
        
        isGeneratingSummary = true
        lastSummarizationError = nil
        
        defer {
            isGeneratingSummary = false
        }
        
        do {
            let summary = try await performChatSummarization(for: chat, length: length)
            
            // Update chat with new summary
            chat.aiGeneratedSummary = summary
            chatStore.saveInCoreData()
            
            return summary
        } catch {
            lastSummarizationError = error.localizedDescription
            throw error
        }
    }
    
    /// Generates summaries for multiple chats in batch
    /// - Parameters:
    ///   - chats: Array of chats to summarize
    ///   - length: Desired summary length
    /// - Returns: Dictionary mapping chat IDs to their summaries
    @MainActor
    func batchGenerateChatSummaries(for chats: [ChatEntity], length: SummaryLength = .standard) async -> [UUID: String] {
        var results: [UUID: String] = [:]
        
        for chat in chats {
            do {
                let summary = try await generateChatSummary(for: chat, length: length)
                results[chat.id] = summary
            } catch {
                print("Failed to generate summary for chat \(chat.name): \(error)")
            }
        }
        
        return results
    }
    
    /// Extracts key topics from a chat without full summarization
    /// - Parameter chat: The chat to analyze
    /// - Returns: Array of key topics
    func extractKeyTopics(from chat: ChatEntity) -> [String] {
        let messages = chat.messagesArray
        var allTopics: [String] = []
        
        for message in messages {
            let content = message.body
            let topics = extractTopicsFromText(content)
            allTopics.append(contentsOf: topics)
        }
        
        // Count frequency and return most common topics
        let topicCounts = Dictionary(grouping: allTopics, by: { $0 })
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }
        
        return Array(topicCounts.prefix(5).map { $0.key })
    }
    
    /// Identifies the chat type based on content analysis
    /// - Parameter chat: The chat to analyze
    /// - Returns: Identified chat type
    func identifyChatType(for chat: ChatEntity) -> ChatType {
        let messages = chat.messagesArray
        var codeBlockCount = 0
        var questionCount = 0
        var totalWords = 0
        var technicalTerms = 0
        
        let technicalKeywords = ["code", "function", "api", "database", "algorithm", "debug", "error", "implementation", "class", "method", "variable"]
        
        for message in messages {
            let content = message.body.lowercased()
            totalWords += content.components(separatedBy: .whitespacesAndNewlines).count
            
            // Count code blocks
            codeBlockCount += countCodeBlocks(in: content)
            
            // Count questions
            questionCount += content.components(separatedBy: "?").count - 1
            
            // Count technical terms
            for keyword in technicalKeywords {
                if content.contains(keyword) {
                    technicalTerms += 1
                }
            }
        }
        
        let avgWordsPerMessage = totalWords / max(messages.count, 1)
        
        // Determine chat type based on analysis
        if codeBlockCount > 0 || technicalTerms > 3 {
            return .coding
        } else if questionCount > messages.count / 2 {
            return .questionAnswer
        } else if avgWordsPerMessage > 50 {
            return .research
        } else if messages.count > 20 {
            return .brainstorming
        } else {
            return .general
        }
    }
    
    // MARK: - Private Methods
    
    /// Performs the actual AI-powered chat summarization
    private func performChatSummarization(for chat: ChatEntity, length: SummaryLength) async throws -> String {
        let messages = chat.messagesArray
        
        guard !messages.isEmpty else {
            return "This chat is empty."
        }
        
        // Build chat context
        let chatContext = buildChatContext(for: chat, messages: messages)
        let summaryPrompt = createChatSummaryPrompt(for: chat, context: chatContext, length: length)
        
        // Generate summary using AI service
        let response = try await apiServiceManager.generateSummary(
            prompt: summaryPrompt,
            maxTokens: length.maxTokens,
            temperature: 0.3
        )
        
        return response
    }
    
    /// Builds comprehensive context about the chat
    private func buildChatContext(for chat: ChatEntity, messages: [MessageEntity]) -> ChatContext {
        var context = ChatContext()
        
        // Basic chat info
        context.chatName = chat.name
        context.messageCount = messages.count
        context.createdAt = chat.createdDate
        context.lastActivity = chat.updatedDate
        
        // Analyze message content
        var userMessages: [String] = []
        var assistantMessages: [String] = []
        var totalCodeBlocks = 0
        
        for message in messages {
            let content = message.body
            
            if message.name == "user" || message.own {
                userMessages.append(content)
            } else {
                assistantMessages.append(content)
            }
            
            totalCodeBlocks += countCodeBlocks(in: content)
            context.topics.append(contentsOf: extractTopicsFromText(content))
        }
        
        context.userMessageCount = userMessages.count
        context.assistantMessageCount = assistantMessages.count
        context.codeBlocksCount = totalCodeBlocks
        context.chatType = identifyChatType(for: chat)
        
        // Extract key exchanges (first few and last few messages)
        context.firstMessages = Array(messages.prefix(3)).map { $0.body }
        context.lastMessages = Array(messages.suffix(3)).map { $0.body }
        
        // Deduplicate topics
        context.topics = Array(Set(context.topics))
        
        return context
    }
    
    /// Creates the prompt for AI chat summarization
    private func createChatSummaryPrompt(for chat: ChatEntity, context: ChatContext, length: SummaryLength) -> String {
        var prompt = """
        Summarize this chat conversation providing a \(length.rawValue) summary:
        
        CHAT DETAILS:
        Name: \(context.chatName)
        Messages: \(context.messageCount) (\(context.userMessageCount) user, \(context.assistantMessageCount) assistant)
        Type: \(context.chatType.rawValue)
        """
        
        if context.codeBlocksCount > 0 {
            prompt += "\nCode blocks: \(context.codeBlocksCount)"
        }
        
        if !context.topics.isEmpty {
            prompt += "\nKey topics: \(context.topics.prefix(8).joined(separator: ", "))"
        }
        
        prompt += "\n\nCONVERSATION START:\n"
        for (index, message) in context.firstMessages.enumerated() {
            let truncated = String(message.prefix(200))
            prompt += "\nMessage \(index + 1): \(truncated)"
            if message.count > 200 {
                prompt += "..."
            }
        }
        
        if context.messageCount > 6 {
            prompt += "\n\n[... middle messages omitted ...]\n"
        }
        
        if context.messageCount > 3 {
            prompt += "\nCONVERSATION END:\n"
            for (index, message) in context.lastMessages.enumerated() {
                let truncated = String(message.prefix(200))
                prompt += "\nRecent \(index + 1): \(truncated)"
                if message.count > 200 {
                    prompt += "..."
                }
            }
        }
        
        prompt += "\n\n"
        
        switch length {
        case .brief:
            prompt += "Provide a brief 1-2 sentence summary of what this conversation was about and any key outcomes."
        case .standard:
            prompt += "Provide a concise paragraph summary including: what was discussed, key points covered, and any important conclusions or decisions."
        case .detailed:
            prompt += "Provide a detailed summary including: main discussion topics, key insights and conclusions, any problems solved, decisions made, and overall conversation flow."
        }
        
        return prompt
    }
    
    /// Checks if existing summary is recent enough to avoid regeneration
    private func shouldUseExistingSummary(for chat: ChatEntity) -> Bool {
        guard let chatSummary = chat.aiGeneratedSummary,
              !chatSummary.isEmpty else {
            return false
        }
        
        // For individual chats, we consider the summary valid if the chat hasn't been updated recently
        // This is simpler than project summaries since chats are typically modified in real-time
        let lastModified = chat.updatedDate
        let now = Date()
        
        // Consider summary stale if chat was modified in the last hour
        let staleThreshold: TimeInterval = 60 * 60 // 1 hour
        
        return now.timeIntervalSince(lastModified) > staleThreshold
    }
    
    /// Extracts potential topics from text content
    private func extractTopicsFromText(_ text: String) -> [String] {
        let commonWords = Set(["the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for", "of", "with", "by", "is", "are", "was", "were", "be", "been", "have", "has", "had", "do", "does", "did", "will", "would", "could", "should", "may", "might", "can", "cannot", "i", "you", "he", "she", "it", "we", "they", "me", "him", "her", "us", "them", "my", "your", "his", "hers", "its", "our", "their", "this", "that", "these", "those", "how", "what", "when", "where", "why", "which", "who"])
        
        let words = text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .compactMap { word in
                let cleaned = word.trimmingCharacters(in: .punctuationCharacters)
                return cleaned.count > 3 && !commonWords.contains(cleaned) ? cleaned : nil
            }
        
        // Return most frequent meaningful words
        let wordCounts = Dictionary(grouping: words, by: { $0 })
            .mapValues { $0.count }
            .filter { $0.value > 1 }
        
        return Array(wordCounts.keys.prefix(3))
    }
    
    /// Counts code blocks in text content
    private func countCodeBlocks(in text: String) -> Int {
        let codeBlockPattern = "```[\\s\\S]*?```"
        let regex = try? NSRegularExpression(pattern: codeBlockPattern, options: [])
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex?.numberOfMatches(in: text, options: [], range: range) ?? 0
    }
}

// MARK: - Supporting Data Structures

/// Chat types for better summarization context
enum ChatType: String {
    case coding = "coding"
    case research = "research"
    case questionAnswer = "q&a"
    case brainstorming = "brainstorming"
    case general = "general"
    
    var description: String {
        switch self {
        case .coding:
            return "Coding/Technical"
        case .research:
            return "Research/Analysis"
        case .questionAnswer:
            return "Question & Answer"
        case .brainstorming:
            return "Brainstorming/Ideas"
        case .general:
            return "General Discussion"
        }
    }
}

/// Context information about a chat for AI analysis
private struct ChatContext {
    var chatName: String = ""
    var messageCount: Int = 0
    var userMessageCount: Int = 0
    var assistantMessageCount: Int = 0
    var codeBlocksCount: Int = 0
    var createdAt: Date = Date()
    var lastActivity: Date = Date()
    var chatType: ChatType = .general
    var topics: [String] = []
    var firstMessages: [String] = []
    var lastMessages: [String] = []
} 