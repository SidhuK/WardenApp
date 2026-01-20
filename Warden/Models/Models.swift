
import CoreData
import Foundation

enum RequestMessageRole: String, Codable, Sendable {
    case system
    case user
    case assistant
    case tool
}

struct RequestMessage: Codable, Equatable, Sendable {
    var role: RequestMessageRole
    var content: String?
    var name: String?
    var toolCallId: String?
    var toolCallsJson: String?

    init(
        role: RequestMessageRole,
        content: String? = nil,
        name: String? = nil,
        toolCallId: String? = nil,
        toolCallsJson: String? = nil
    ) {
        self.role = role
        self.content = content
        self.name = name
        self.toolCallId = toolCallId
        self.toolCallsJson = toolCallsJson
    }

    init?(dictionary: [String: String]) {
        guard let roleString = dictionary["role"], let role = RequestMessageRole(rawValue: roleString) else {
            return nil
        }

        self.role = role
        self.content = dictionary["content"]
        self.name = dictionary["name"]
        self.toolCallId = dictionary["tool_call_id"]
        self.toolCallsJson = dictionary["tool_calls_json"]
    }

    var dictionary: [String: String] {
        var result: [String: String] = ["role": role.rawValue]
        if let content { result["content"] = content }
        if let name { result["name"] = name }
        if let toolCallId { result["tool_call_id"] = toolCallId }
        if let toolCallsJson { result["tool_calls_json"] = toolCallsJson }
        return result
    }
}

extension Array where Element == [String: String] {
    var typedRequestMessages: [RequestMessage] {
        compactMap(RequestMessage.init(dictionary:))
    }
}

extension Array where Element == RequestMessage {
    var requestMessageDictionaries: [[String: String]] {
        map(\.dictionary)
    }
}

public class ChatEntity: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var messages: NSOrderedSet
    @NSManaged public var requestMessages: [[String: String]]
    @NSManaged public var newChat: Bool
    @NSManaged public var temperature: Double
    @NSManaged public var top_p: Double
    @NSManaged public var behavior: String?
    @NSManaged public var newMessage: String?
    @NSManaged public var reasoningEffortRaw: String?
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
    
    // Branching properties
    @NSManaged public var parentChat: ChatEntity?
    @NSManaged public var childChats: NSSet
    @NSManaged public var branchSourceMessageID: Int64
    @NSManaged public var branchSourceRole: String?
    @NSManaged public var branchRootID: UUID?

    public var messagesArray: [MessageEntity] {
        messages.array as? [MessageEntity] ?? []
    }
    
    public func nextMessageID() -> Int64 {
        (messagesArray.map(\.id).max() ?? 0) + 1
    }

    public var topP: Double {
        get { top_p }
        set { top_p = newValue }
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
        requestMessages.append(RequestMessage(role: .user, content: message).dictionary)
    }
    
    public func clearMessages() {
        (messages.array as? [MessageEntity])?.forEach { managedObjectContext?.delete($0) }
        messages = NSOrderedSet()
        newChat = true
    }

    var reasoningEffort: ReasoningEffort {
        get {
            guard let reasoningEffortRaw, let effort = ReasoningEffort(rawValue: reasoningEffortRaw) else {
                return .off
            }
            return effort
        }
        set {
            reasoningEffortRaw = newValue == .off ? nil : newValue.rawValue
        }
    }
    
    public var childChatsArray: [ChatEntity] {
        childChats.allObjects as? [ChatEntity] ?? []
    }
    
    public var isBranch: Bool {
        parentChat != nil
    }
}

public class MessageEntity: NSManagedObject, Identifiable {
    @NSManaged public var id: Int64
    @NSManaged public var name: String
    @NSManaged public var body: String
    @NSManaged public var timestamp: Date?
    @NSManaged public var own: Bool
    @NSManaged public var toolCallsJson: String?
    @NSManaged public var searchMetadataJson: String?
    @NSManaged public var waitingForResponse: Bool
    @NSManaged public var chat: ChatEntity?
    
    // Multi-agent response tracking
    @NSManaged public var isMultiAgentResponse: Bool
    @NSManaged public var agentServiceName: String?
    @NSManaged public var agentServiceType: String?
    @NSManaged public var agentModel: String?
    @NSManaged public var multiAgentGroupId: UUID?
    
    private static var toolCallsCacheKey: UInt8 = 0
    private static var toolCallsCacheJsonKey: UInt8 = 1
    private static var searchMetadataCacheKey: UInt8 = 2
    private static var searchMetadataCacheJsonKey: UInt8 = 3

    public var toolCalls: [WardenToolCallStatus] {
        get {
            guard let json = toolCallsJson,
                  let data = json.data(using: .utf8),
                  let calls = try? JSONDecoder().decode([WardenToolCallStatus].self, from: data) else {
                objc_setAssociatedObject(self, &MessageEntity.toolCallsCacheJsonKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                objc_setAssociatedObject(self, &MessageEntity.toolCallsCacheKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                return []
            }

            if let cachedJson = objc_getAssociatedObject(self, &MessageEntity.toolCallsCacheJsonKey) as? String,
               cachedJson == json,
               let cached = objc_getAssociatedObject(self, &MessageEntity.toolCallsCacheKey) as? [WardenToolCallStatus] {
                return cached
            }

            objc_setAssociatedObject(self, &MessageEntity.toolCallsCacheJsonKey, json, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            objc_setAssociatedObject(self, &MessageEntity.toolCallsCacheKey, calls, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return calls
        }
        set {
            if newValue.isEmpty {
                toolCallsJson = nil
                objc_setAssociatedObject(self, &MessageEntity.toolCallsCacheJsonKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                objc_setAssociatedObject(self, &MessageEntity.toolCallsCacheKey, [], .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            } else if let data = try? JSONEncoder().encode(newValue),
                      let json = String(data: data, encoding: .utf8) {
                toolCallsJson = json
                objc_setAssociatedObject(self, &MessageEntity.toolCallsCacheJsonKey, json, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                objc_setAssociatedObject(self, &MessageEntity.toolCallsCacheKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            }
        }
    }
    
    public var searchMetadata: MessageSearchMetadata? {
        get {
            guard let json = searchMetadataJson,
                  let data = json.data(using: .utf8),
                  let metadata = try? JSONDecoder().decode(MessageSearchMetadata.self, from: data) else {
                objc_setAssociatedObject(
                    self,
                    &MessageEntity.searchMetadataCacheJsonKey,
                    nil,
                    .OBJC_ASSOCIATION_RETAIN_NONATOMIC
                )
                objc_setAssociatedObject(
                    self,
                    &MessageEntity.searchMetadataCacheKey,
                    nil,
                    .OBJC_ASSOCIATION_RETAIN_NONATOMIC
                )
                return nil
            }

            if let cachedJson = objc_getAssociatedObject(self, &MessageEntity.searchMetadataCacheJsonKey) as? String,
               cachedJson == json,
               let cached = objc_getAssociatedObject(
                   self,
                   &MessageEntity.searchMetadataCacheKey
               ) as? MessageSearchMetadata {
                return cached
            }

            objc_setAssociatedObject(
                self,
                &MessageEntity.searchMetadataCacheJsonKey,
                json,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
            objc_setAssociatedObject(
                self,
                &MessageEntity.searchMetadataCacheKey,
                metadata,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
            return metadata
        }
        set {
            if let newValue = newValue,
               let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                searchMetadataJson = json
                objc_setAssociatedObject(
                    self,
                    &MessageEntity.searchMetadataCacheJsonKey,
                    json,
                    .OBJC_ASSOCIATION_RETAIN_NONATOMIC
                )
                objc_setAssociatedObject(
                    self,
                    &MessageEntity.searchMetadataCacheKey,
                    newValue,
                    .OBJC_ASSOCIATION_RETAIN_NONATOMIC
                )
            } else {
                searchMetadataJson = nil
                objc_setAssociatedObject(
                    self,
                    &MessageEntity.searchMetadataCacheJsonKey,
                    nil,
                    .OBJC_ASSOCIATION_RETAIN_NONATOMIC
                )
                objc_setAssociatedObject(
                    self,
                    &MessageEntity.searchMetadataCacheKey,
                    nil,
                    .OBJC_ASSOCIATION_RETAIN_NONATOMIC
                )
            }
        }
    }
    
    public var hasSearchResults: Bool {
        searchMetadata != nil
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
    var reasoningEffortRaw: String?
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
        self.reasoningEffortRaw = chatEntity.reasoningEffortRaw
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
