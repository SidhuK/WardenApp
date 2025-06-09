import Foundation
import CoreData

/// Service responsible for generating AI-powered summaries and insights for projects
/// Analyzes all chats within a project to create comprehensive overviews
class ProjectSummarizationService: ObservableObject {
    private let chatStore: ChatStore
    private let apiServiceManager: APIServiceManager
    
    @Published var isGeneratingSummary = false
    @Published var lastSummarizationError: String?
    
    init(chatStore: ChatStore, apiServiceManager: APIServiceManager) {
        self.chatStore = chatStore
        self.apiServiceManager = apiServiceManager
    }
    
    // MARK: - Public Methods
    
    /// Generates a comprehensive summary for a project based on all its chats
    /// - Parameters:
    ///   - project: The project to summarize
    ///   - forceRefresh: Whether to regenerate even if recent summary exists
    /// - Returns: Generated summary text
    @MainActor
    func generateProjectSummary(for project: ProjectEntity, forceRefresh: Bool = false) async throws -> String {
        // Check if we need to regenerate summary
        if !forceRefresh && shouldUseExistingSummary(for: project) {
            return project.aiGeneratedSummary ?? ""
        }
        
        isGeneratingSummary = true
        lastSummarizationError = nil
        
        defer {
            isGeneratingSummary = false
        }
        
        do {
            let summary = try await performProjectSummarization(for: project)
            
            // Update project with new summary
            project.aiGeneratedSummary = summary
            project.lastSummarizedAt = Date()
            project.updatedAt = Date()
            
            chatStore.saveInCoreData()
            
            return summary
        } catch {
            lastSummarizationError = error.localizedDescription
            throw error
        }
    }
    
    /// Generates summaries for multiple projects in batch
    /// - Parameter projects: Array of projects to summarize
    /// - Returns: Dictionary mapping project IDs to their summaries
    @MainActor
    func batchGenerateProjectSummaries(for projects: [ProjectEntity]) async -> [UUID: String] {
        var results: [UUID: String] = [:]
        
        for project in projects {
            do {
                let summary = try await generateProjectSummary(for: project)
                if let projectId = project.id {
                    results[projectId] = summary
                }
            } catch {
                print("Failed to generate summary for project \(project.name ?? "Unknown"): \(error)")
            }
        }
        
        return results
    }
    
    // MARK: - Private Methods
    
    /// Performs the actual AI-powered summarization
    private func performProjectSummarization(for project: ProjectEntity) async throws -> String {
        let chats = project.chatsArray
        
        guard !chats.isEmpty else {
            return "This project is empty. Add some chats to generate meaningful insights."
        }
        
        // Build comprehensive project context
        let projectContext = buildProjectContext(for: project, chats: chats)
        let analysisPrompt = createProjectAnalysisPrompt(for: project, context: projectContext)
        
        // Use the project's preferred AI service or fallback to default
        let response = try await apiServiceManager.generateSummary(
            prompt: analysisPrompt,
            maxTokens: 800,
            temperature: 0.3
        )
        
        return response
    }
    
    /// Builds comprehensive context about the project from all its chats
    private func buildProjectContext(for project: ProjectEntity, chats: [ChatEntity]) -> ProjectContext {
        var context = ProjectContext()
        
        // Basic project info
        context.projectName = project.name ?? "Untitled Project"
        context.projectDescription = project.projectDescription
        context.customInstructions = project.customInstructions
        context.chatCount = chats.count
        context.createdAt = project.createdAt
        
        // Analyze chats
        for chat in chats {
            let chatInfo = analyzeChatForProject(chat)
            context.chatSummaries.append(chatInfo)
            
            // Aggregate statistics
            context.totalMessages += chatInfo.messageCount
            context.codeBlocksCount += chatInfo.codeBlocksCount
            context.topics.append(contentsOf: chatInfo.extractedTopics)
            
            if let lastActivity = chatInfo.lastActivity {
                if context.lastActivity == nil || lastActivity > context.lastActivity! {
                    context.lastActivity = lastActivity
                }
            }
        }
        
        // Deduplicate and sort topics by frequency
        context.topics = Array(Set(context.topics))
        
        return context
    }
    
    /// Analyzes a single chat to extract relevant information for project summary
    private func analyzeChatForProject(_ chat: ChatEntity) -> ChatSummaryInfo {
        let messages = chat.messagesArray
        
        var info = ChatSummaryInfo()
        info.chatName = chat.name
        info.messageCount = messages.count
        info.lastActivity = chat.updatedDate
        info.createdAt = chat.createdDate
        
        // Analyze message content
        for message in messages {
            let content = message.body
            // Extract topics and themes
            info.extractedTopics.append(contentsOf: extractTopicsFromText(content))
            
            // Count code blocks
            info.codeBlocksCount += countCodeBlocks(in: content)
            
            // Track AI model usage
            if message.name == "assistant" {
                info.aiResponsesCount += 1
            }
        }
        
        // Generate brief chat summary if it has substantial content
        if info.messageCount > 3 {
            info.briefSummary = generateBriefChatSummary(from: messages)
        }
        
        return info
    }
    
    /// Creates the prompt for AI project analysis
    private func createProjectAnalysisPrompt(for project: ProjectEntity, context: ProjectContext) -> String {
        var prompt = """
        Analyze this project and provide a comprehensive summary with insights:
        
        PROJECT DETAILS:
        Name: \(context.projectName)
        """
        
        if let description = context.projectDescription {
            prompt += "\nDescription: \(description)"
        }
        
        if let instructions = context.customInstructions {
            prompt += "\nCustom Instructions: \(instructions)"
        }
        
        prompt += """
        
        PROJECT STATISTICS:
        - Total Chats: \(context.chatCount)
        - Total Messages: \(context.totalMessages)
        - Code Blocks: \(context.codeBlocksCount)
        - Created: \(formatDate(context.createdAt))
        """
        
        if let lastActivity = context.lastActivity {
            prompt += "\n- Last Activity: \(formatDate(lastActivity))"
        }
        
        if !context.topics.isEmpty {
            prompt += "\n\nKEY TOPICS: \(context.topics.prefix(10).joined(separator: ", "))"
        }
        
        prompt += "\n\nCHAT SUMMARIES:\n"
        for (index, chatInfo) in context.chatSummaries.enumerated() {
            prompt += "\n\(index + 1). \(chatInfo.chatName) (\(chatInfo.messageCount) messages)"
            if let summary = chatInfo.briefSummary {
                prompt += "\n   Summary: \(summary)"
            }
        }
        
        prompt += """
        
        Please provide a comprehensive project summary including:
        1. **Project Overview**: What this project is about and its main purpose
        2. **Key Themes**: Main topics and areas of focus
        3. **Progress & Insights**: What has been accomplished and learned
        4. **Project Type**: Classification (research, development, creative, learning, etc.)
        5. **Notable Patterns**: Any interesting patterns or recurring themes
        6. **Current Status**: Where the project stands now
        
        Keep the summary informative but concise (3-4 paragraphs maximum).
        """
        
        return prompt
    }
    
    /// Checks if existing summary is recent enough to avoid regeneration
    private func shouldUseExistingSummary(for project: ProjectEntity) -> Bool {
        guard let lastSummarized = project.lastSummarizedAt,
              let projectSummary = project.aiGeneratedSummary,
              !projectSummary.isEmpty else {
            return false
        }
        
        // Consider summary stale if it's older than 7 days or if project was updated after summarization
        let staleDuration: TimeInterval = 7 * 24 * 60 * 60 // 7 days
        let now = Date()
        
        let isRecentEnough = now.timeIntervalSince(lastSummarized) < staleDuration
        let isUpToDate = project.updatedAt ?? Date.distantPast <= lastSummarized
        
        return isRecentEnough && isUpToDate
    }
    
    /// Extracts potential topics from text content
    private func extractTopicsFromText(_ text: String) -> [String] {
        // Simple keyword extraction - could be enhanced with NLP
        let commonWords = Set(["the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for", "of", "with", "by", "is", "are", "was", "were", "be", "been", "have", "has", "had", "do", "does", "did", "will", "would", "could", "should", "may", "might", "can", "cannot", "i", "you", "he", "she", "it", "we", "they", "me", "him", "her", "us", "them", "my", "your", "his", "hers", "its", "our", "their", "this", "that", "these", "those"])
        
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
        
        return Array(wordCounts.keys.prefix(5))
    }
    
    /// Counts code blocks in text content
    private func countCodeBlocks(in text: String) -> Int {
        let codeBlockPattern = "```[\\s\\S]*?```"
        let regex = try? NSRegularExpression(pattern: codeBlockPattern, options: [])
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex?.numberOfMatches(in: text, options: [], range: range) ?? 0
    }
    
    /// Generates a brief summary for a chat based on its messages
    private func generateBriefChatSummary(from messages: [MessageEntity]) -> String {
        // Extract key information from first and last few messages
        let firstMessages = messages.prefix(2)
        let lastMessages = messages.suffix(2)
        
        var topics: [String] = []
        
        for message in firstMessages + lastMessages {
            let content = message.body
            topics.append(contentsOf: extractTopicsFromText(content))
        }
        
        let uniqueTopics = Array(Set(topics)).prefix(3)
        
        if uniqueTopics.isEmpty {
            return "General conversation with \(messages.count) messages"
        } else {
            return "Discussion about \(uniqueTopics.joined(separator: ", "))"
        }
    }
    
    /// Formats date for display in prompts
    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "Unknown" }
        
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - Supporting Data Structures

/// Comprehensive context about a project for AI analysis
private struct ProjectContext {
    var projectName: String = ""
    var projectDescription: String?
    var customInstructions: String?
    var chatCount: Int = 0
    var totalMessages: Int = 0
    var codeBlocksCount: Int = 0
    var createdAt: Date?
    var lastActivity: Date?
    var topics: [String] = []
    var chatSummaries: [ChatSummaryInfo] = []
}

/// Information extracted from individual chats for project analysis
private struct ChatSummaryInfo {
    var chatName: String = ""
    var messageCount: Int = 0
    var aiResponsesCount: Int = 0
    var codeBlocksCount: Int = 0
    var lastActivity: Date?
    var createdAt: Date?
    var extractedTopics: [String] = []
    var briefSummary: String?
}

// MARK: - Extensions

extension ProjectEntity {
    /// Convenience property to get chats as an array
    var chatsArray: [ChatEntity] {
        let chatsSet = chats as? Set<ChatEntity> ?? []
        return Array(chatsSet).sorted { chat1, chat2 in
            return chat1.updatedDate > chat2.updatedDate
        }
    }
}

// Note: ChatEntity already has a messagesArray property in Models.swift 