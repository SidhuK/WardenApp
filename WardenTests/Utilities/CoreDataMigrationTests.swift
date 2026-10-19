import CoreData
import XCTest
@testable import Warden

final class CoreDataMigrationTests: XCTestCase {
    private var storeDirectory: URL!

    override func setUpWithError() throws {
        storeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WardenMigrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let storeDirectory {
            try? FileManager.default.removeItem(at: storeDirectory)
        }
    }

    private func model(named name: String) throws -> NSManagedObjectModel {
        let bundle = Bundle(for: MessageEntity.self)
        let momdURL = try XCTUnwrap(bundle.url(forResource: "wardenDataModel", withExtension: "momd"))
        let url = momdURL.appendingPathComponent("\(name).mom")
        return try XCTUnwrap(NSManagedObjectModel(contentsOf: url), "Missing compiled model \(name)")
    }

    private func loadStore(at url: URL, model: NSManagedObjectModel) throws -> NSPersistentContainer {
        let container = NSPersistentContainer(name: "MigrationTest", managedObjectModel: model)
        let description = NSPersistentStoreDescription(url: url)
        description.shouldAddStoreAsynchronously = false
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }
        if let loadError {
            throw loadError
        }
        return container
    }

    func testVersion1StoreMigratesToCurrentModel() throws {
        let v1 = try model(named: "wardenDataModel 1")
        let current = try model(named: "wardenDataModel")

        XCTAssertNil(v1.entitiesByName["PromptEntity"])
        XCTAssertNil(v1.entitiesByName["MessageEntity"]?.attributesByName["metricsJson"])
        XCTAssertNotNil(current.entitiesByName["PromptEntity"])
        XCTAssertNotNil(current.entitiesByName["MessageEntity"]?.attributesByName["metricsJson"])

        let storeURL = storeDirectory.appendingPathComponent("Warden.sqlite")

        do {
            let container = try loadStore(at: storeURL, model: v1)
            let context = container.viewContext
            let chat = NSEntityDescription.insertNewObject(forEntityName: "ChatEntity", into: context)
            chat.setValue(UUID(), forKey: "id")
            chat.setValue("Legacy chat", forKey: "name")
            let message = NSEntityDescription.insertNewObject(forEntityName: "MessageEntity", into: context)
            message.setValue(Int64(1), forKey: "id")
            message.setValue("Hello from v1", forKey: "body")
            message.setValue(chat, forKey: "chat")
            try context.save()
            for store in container.persistentStoreCoordinator.persistentStores {
                try container.persistentStoreCoordinator.remove(store)
            }
        }

        let migrated = try loadStore(at: storeURL, model: current)
        let context = migrated.viewContext

        let messages = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "MessageEntity"))
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?.value(forKey: "body") as? String, "Hello from v1")
        XCTAssertNil(messages.first?.value(forKey: "metricsJson"))

        let metrics = MessageMetrics(providerType: "chatgpt", usage: TokenUsage(inputTokens: 3, outputTokens: 4))
        let messageEntity = try XCTUnwrap(messages.first as? MessageEntity)
        messageEntity.metrics = metrics
        XCTAssertEqual(messageEntity.metrics, metrics)

        let prompt = NSEntityDescription.insertNewObject(forEntityName: "PromptEntity", into: context)
        prompt.setValue(UUID(), forKey: "id")
        prompt.setValue("Summarize", forKey: "name")
        prompt.setValue("Summarize this:", forKey: "content")
        prompt.setValue(Date(), forKey: "createdDate")
        try context.save()

        XCTAssertEqual(try context.count(for: NSFetchRequest<NSManagedObject>(entityName: "PromptEntity")), 1)
        XCTAssertEqual((prompt as? PromptEntity)?.usageCount, 0)
    }
}
