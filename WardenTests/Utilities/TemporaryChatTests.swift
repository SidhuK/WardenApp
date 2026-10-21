import CoreData
import XCTest
@testable import Warden

@MainActor
final class TemporaryChatTests: XCTestCase {
    private var container: NSPersistentContainer!
    private var context: NSManagedObjectContext { container.viewContext }

    override func setUp() async throws {
        // Reuse the app's loaded model so each entity maps to a single entity description.
        let model = PersistenceController.shared.container.managedObjectModel
        container = NSPersistentContainer(name: "TemporaryChatTests", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
    }

    override func tearDown() async throws {
        container = nil
    }

    @discardableResult
    private func makeChat(
        _ name: String,
        in context: NSManagedObjectContext,
        updated: Date = Date(),
        pinned: Bool = false,
        project: ProjectEntity? = nil
    ) -> ChatEntity {
        let chat = ChatEntity(context: context)
        chat.id = UUID()
        chat.name = name
        chat.createdDate = updated
        chat.updatedDate = updated
        chat.systemMessage = ""
        chat.gptModel = ""
        chat.isPinned = pinned
        chat.project = project
        let message = MessageEntity(context: context)
        message.id = 1
        message.body = "hello"
        message.name = "user"
        message.own = true
        message.timestamp = updated
        message.chat = chat
        return chat
    }

    private func storedChatNames() throws -> [String] {
        let reader = container.newBackgroundContext()
        return try reader.performAndWait {
            let request = NSFetchRequest<ChatEntity>(entityName: "ChatEntity")
            return try reader.fetch(request).map(\.name)
        }
    }

    // MARK: - Temporary chats

    func testSavingATemporaryChatNeverReachesTheStore() throws {
        let temporary = TemporaryChatContext(parent: context)
        let chat = makeChat("secret", in: temporary)
        XCTAssertTrue(chat.isTemporary)

        try temporary.save()
        try context.save()

        XCTAssertFalse(context.hasChanges)
        XCTAssertEqual(try storedChatNames(), [])
    }

    func testCommitAddsTheChatToTheStore() throws {
        let temporary = TemporaryChatContext(parent: context)
        let chat = makeChat("kept", in: temporary)

        try temporary.commit()

        XCTAssertEqual(try storedChatNames(), ["kept"])
        let saved = try XCTUnwrap(context.existingObject(with: chat.objectID) as? ChatEntity)
        XCTAssertFalse(saved.isTemporary)
        XCTAssertEqual(saved.messagesArray.count, 1)

        // Later saves still go nowhere until the next commit.
        chat.name = "renamed"
        try temporary.save()
        XCTAssertEqual(try storedChatNames(), ["kept"])
    }

    func testDiscardForgetsCachedAttachments() {
        let temporary = TemporaryChatContext(parent: context)
        let id = UUID()
        TemporaryAttachmentCache.shared.storeImage(Data([1, 2, 3]), for: id)
        temporary.registerAttachment(id)

        temporary.discard()

        XCTAssertNil(TemporaryAttachmentCache.shared.imageData(for: id))
        XCTAssertTrue(temporary.attachmentIDs.isEmpty)
    }

    // MARK: - Chat order shortcuts

    func testSidebarOrderPutsPinnedFirstAndSkipsProjectChats() {
        let now = Date()
        let project = ProjectEntity(context: context)
        project.id = UUID()
        project.name = "Work"
        project.createdAt = now
        project.updatedAt = now

        let chats = [
            makeChat("old", in: context, updated: now.addingTimeInterval(-300)),
            makeChat("pinned-old", in: context, updated: now.addingTimeInterval(-600), pinned: true),
            makeChat("in-project", in: context, updated: now, project: project),
            makeChat("new", in: context, updated: now.addingTimeInterval(-10)),
        ]

        XCTAssertEqual(ChatStore.sidebarOrder(chats).map(\.name), ["pinned-old", "new", "old"])
    }

    func testCycledChatWrapsInBothDirections() {
        let chats = ["a", "b", "c"].map { makeChat($0, in: context) }

        XCTAssertEqual(ChatStore.cycledChat(from: chats[0], in: chats, offset: 1)?.name, "b")
        XCTAssertEqual(ChatStore.cycledChat(from: chats[2], in: chats, offset: 1)?.name, "a")
        XCTAssertEqual(ChatStore.cycledChat(from: chats[0], in: chats, offset: -1)?.name, "c")
        XCTAssertEqual(ChatStore.cycledChat(from: nil, in: chats, offset: 1)?.name, "a")
        XCTAssertEqual(ChatStore.cycledChat(from: nil, in: chats, offset: -1)?.name, "c")
        XCTAssertNil(ChatStore.cycledChat(from: nil, in: [], offset: 1))
    }
}
