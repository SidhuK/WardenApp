
import CoreData
import Foundation
import SwiftUI
import UniformTypeIdentifiers

public class ChatEntity: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var messages: NSOrderedSet
    @NSManaged public var requestMessages: [[String: String]]
    @NSManaged public var newChat: Bool
    @NSManaged public var temperature: Double
    @NSManaged public var top_p: Double
    @NSManaged public var behavior: String?
    @NSManaged public var newMessage: String?
    @NSManaged public var createdDate: Date
    @NSManaged public var updatedDate: Date
    @NSManaged public var systemMessage: String
    @NSManaged public var gptModel: String
    @NSManaged public var name: String
    @NSManaged public var waitingForResponse: Bool
    @NSManaged public var persona: PersonaEntity?
    @NSManaged public var apiService: APIServiceEntity?
    @NSManaged public var isPinned: Bool
    @NSManaged public var project: ProjectEntity?
    @NSManaged public var aiGeneratedSummary: String?

    public var messagesArray: [MessageEntity] {
        messages.array as? [MessageEntity] ?? []
    }

    public var lastMessage: MessageEntity? {
        messages.lastObject as? MessageEntity
    }

    public func addToMessages(_ message: MessageEntity) {
        let newMessages = NSMutableOrderedSet(orderedSet: messages)
        newMessages.add(message)
        messages = newMessages
    }

    public func removeFromMessages(_ message: MessageEntity) {
        let newMessages = NSMutableOrderedSet(orderedSet: messages)
        newMessages.remove(message)
        messages = newMessages
    }
    
    public func addUserMessage(_ message: String) {
        self.requestMessages.append(["role": "user", "content": message])
    }
    
    public func clearMessages() {
        (messages.array as? [MessageEntity])?.forEach { managedObjectContext?.delete($0) }
        messages = NSOrderedSet()
        newChat = true
    }
}

public class MessageEntity: NSManagedObject, Identifiable {
    @NSManaged public var id: Int64
    @NSManaged public var name: String
    @NSManaged public var body: String
    @NSManaged public var timestamp: Date?
    @NSManaged public var own: Bool
    @NSManaged public var toolCallsJson: String?
    @NSManaged public var waitingForResponse: Bool
    @NSManaged public var chat: ChatEntity?
    
    // Multi-agent response tracking
    @NSManaged public var isMultiAgentResponse: Bool
    @NSManaged public var agentServiceName: String?
    @NSManaged public var agentServiceType: String?
    @NSManaged public var agentModel: String?
    @NSManaged public var multiAgentGroupId: UUID?
    
    public var toolCalls: [WardenToolCallStatus] {
        get {
            guard let json = toolCallsJson,
                  let data = json.data(using: .utf8),
                  let calls = try? JSONDecoder().decode([WardenToolCallStatus].self, from: data) else {
                return []
            }
            return calls
        }
        set {
            if newValue.isEmpty {
                toolCallsJson = nil
            } else if let data = try? JSONEncoder().encode(newValue),
                      let json = String(data: data, encoding: .utf8) {
                toolCallsJson = json
            }
        }
    }
}

/// Data Transfer Object for Chat backup and export/import
struct ChatBackup: Codable {
    var id: UUID
    var messagePreview: MessageBackup?
    var messages: [MessageBackup] = []
    var requestMessages = [["role": "user", "content": ""]]
    var newChat: Bool = true
    var temperature: Float64?
    var top_p: Float64?
    var behavior: String?
    var newMessage: String?
    var gptModel: String?
    var systemMessage: String?
    var name: String?
    var apiServiceName: String?
    var apiServiceType: String?
    var personaName: String?

    init(chatEntity: ChatEntity) {
        self.id = chatEntity.id
        self.newChat = chatEntity.newChat
        self.temperature = chatEntity.temperature
        self.top_p = chatEntity.top_p
        self.behavior = chatEntity.behavior
        self.newMessage = chatEntity.newMessage
        self.requestMessages = chatEntity.requestMessages
        self.gptModel = chatEntity.gptModel
        self.systemMessage = chatEntity.systemMessage
        self.name = chatEntity.name
        self.apiServiceName = chatEntity.apiService?.name
        self.apiServiceType = chatEntity.apiService?.type
        self.personaName = chatEntity.persona?.name
        
        self.messages = chatEntity.messagesArray.map { MessageBackup(messageEntity: $0) }

        if chatEntity.lastMessage != nil {
            self.messagePreview = MessageBackup(messageEntity: chatEntity.lastMessage!)
        }
    }
}

/// Data Transfer Object for Message backup and export/import
struct MessageBackup: Codable, Equatable {
    var id: Int
    var name: String
    var body: String
    var timestamp: Date
    var own: Bool
    var waitingForResponse: Bool?

    init(messageEntity: MessageEntity) {
        self.id = Int(messageEntity.id)
        self.name = messageEntity.name
        self.body = messageEntity.body
        self.timestamp = messageEntity.timestamp ?? Date()
        self.own = messageEntity.own
        self.waitingForResponse = messageEntity.waitingForResponse
    }
}

extension APIServiceEntity: NSCopying {
    public func copy(with zone: NSZone? = nil) -> Any {
        let copy = APIServiceEntity(context: self.managedObjectContext!)
        copy.name = self.name
        copy.type = self.type
        copy.url = self.url
        copy.model = self.model
        copy.contextSize = self.contextSize
        copy.useStreamResponse = self.useStreamResponse
        copy.generateChatNames = self.generateChatNames
        copy.defaultPersona = self.defaultPersona
        return copy
    }
}

extension URL {
    func getUTType() -> UTType? {
        let fileExtension = pathExtension.lowercased()
        
        switch fileExtension {
        case "txt": return .plainText
        case "csv": return .commaSeparatedText
        case "json": return .json
        case "xml": return .xml
        case "html", "htm": return .html
        case "md", "markdown": return .init(filenameExtension: "md")
        case "rtf": return .rtf
        case "pdf": return .pdf
        case "jpg", "jpeg": return .jpeg
        case "png": return .png
        case "gif": return .gif
        case "heic": return .heic
        case "heif": return .heif
        default: return UTType(filenameExtension: fileExtension) ?? .data
        }
    }
}
