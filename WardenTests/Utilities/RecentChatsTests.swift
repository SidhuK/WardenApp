import CoreData
import XCTest
@testable import Warden

@MainActor
final class RecentChatsTests: XCTestCase {
    private var container: NSPersistentContainer!
    private var context: NSManagedObjectContext { container.viewContext }

    override func setUp() async throws {
        // Reuse the app's loaded model so each entity maps to a single entity description.
        let model = PersistenceController.shared.container.managedObjectModel
        container = NSPersistentContainer(name: "RecentChatsTests", managedObjectModel: model)
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
        updated: Date,
        project: ProjectEntity? = nil,
        messageCount: Int = 1,
        pinned: Bool = false
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
        for index in 0..<messageCount {
            let message = MessageEntity(context: context)
            message.id = Int64(index)
            message.body = "message \(index)"
            message.name = "user"
            message.own = true
            message.timestamp = updated
            message.chat = chat
        }
        return chat
    }

    private func makeProject(_ name: String) -> ProjectEntity {
        let project = ProjectEntity(context: context)
        project.id = UUID()
        project.name = name
        project.createdAt = Date()
        project.updatedAt = Date()
        return project
    }

    private func recent(
        in project: ProjectEntity? = nil,
        excluding excluded: ChatEntity? = nil,
        limit: Int = 5
    ) throws -> [String] {
        try context.save()
        return ChatStore.recentChats(in: project, excluding: excluded, limit: limit, context: context).map(\.name)
    }

    func testOrdersNewestFirstIgnoringPins() throws {
        let now = Date()
        makeChat("old", updated: now.addingTimeInterval(-300), pinned: true)
        makeChat("newest", updated: now)
        makeChat("middle", updated: now.addingTimeInterval(-60))

        XCTAssertEqual(try recent(), ["newest", "middle", "old"])
    }

    func testExcludesCurrentAndEmptyChats() throws {
        let now = Date()
        let current = makeChat("current", updated: now)
        makeChat("empty", updated: now.addingTimeInterval(-10), messageCount: 0)
        makeChat("kept", updated: now.addingTimeInterval(-20))

        XCTAssertEqual(try recent(excluding: current), ["kept"])
    }

    func testFiltersToProjectWhenGiven() throws {
        let now = Date()
        let work = makeProject("Work")
        let home = makeProject("Home")
        makeChat("work-1", updated: now, project: work)
        makeChat("home-1", updated: now.addingTimeInterval(-10), project: home)
        makeChat("loose", updated: now.addingTimeInterval(-20))
        makeChat("work-2", updated: now.addingTimeInterval(-30), project: work)

        XCTAssertEqual(try recent(in: work), ["work-1", "work-2"])
        XCTAssertEqual(try recent(), ["work-1", "home-1", "loose", "work-2"])
    }

    func testRespectsLimit() throws {
        let now = Date()
        for index in 0..<8 {
            makeChat("chat-\(index)", updated: now.addingTimeInterval(TimeInterval(-index)))
        }

        XCTAssertEqual(try recent(limit: 3), ["chat-0", "chat-1", "chat-2"])
        XCTAssertEqual(try recent(limit: 0), [])
    }

    func testRelativeTimeLabels() {
        let calendar = Calendar.current
        let now = calendar.date(from: DateComponents(year: 2025, month: 6, day: 18, hour: 15))!

        XCTAssertEqual(RecentChatTimeFormatter.string(for: now.addingTimeInterval(-20), now: now), "Now")
        XCTAssertEqual(RecentChatTimeFormatter.string(for: now.addingTimeInterval(-5 * 60), now: now), "5m")
        XCTAssertEqual(RecentChatTimeFormatter.string(for: now.addingTimeInterval(-2 * 3600), now: now), "2h")
        XCTAssertEqual(RecentChatTimeFormatter.string(for: now.addingTimeInterval(-20 * 3600), now: now), "Yesterday")
    }
}
