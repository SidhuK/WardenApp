# Bug Fix Implementation Plan

This document outlines the step-by-step plan to fix 7 critical bugs discovered in the Warden app. Bugs are organized by priority, with the most critical issues addressed first.

---

## Priority Classification

- **🔴 CRITICAL**: Security, data loss, crashes, or severe performance issues
- **🟡 HIGH**: Functionality broken or significantly impaired
- **🟢 MEDIUM**: UX improvements or minor functionality issues

---

## 🔴 CRITICAL BUG #1: Core Data Threading Violation

### Impact
- **Severity**: CRITICAL - Will cause random crashes and data corruption
- **Affected Files**: 
  - `Warden/Utilities/APIHandlers/ChatGPTHandler.swift`
  - `Warden/Utilities/APIHandlers/LMStudioHandler.swift`

### Problem
The `prepareRequest` method loads images and files from Core Data using `viewContext` (main thread context) but is executed on background threads during URL request preparation. This violates Core Data's threading rules: "A managed object context must only be accessed from the thread it was created on."

### Root Cause Analysis
```swift
// Called from background thread in sendMessageStream/sendMessage
internal func prepareRequest(...) -> URLRequest {
    // ...
    if let imageData = self.loadImageFromCoreData(uuid: uuid) { // ⚠️ Thread violation!
        // ...
    }
}

private func loadImageFromCoreData(uuid: UUID) -> Data? {
    let viewContext = PersistenceController.shared.container.viewContext  // Main thread context!
    let fetchRequest: NSFetchRequest<ImageEntity> = ImageEntity.fetchRequest()
    // ... fetch on wrong thread
}
```

### Solution Steps

#### Step 1: Create a background-safe data loading utility
```swift
// Create new file: Warden/Utilities/CoreDataHelpers/BackgroundDataLoader.swift

import CoreData

class BackgroundDataLoader {
    private let persistenceController: PersistenceController
    
    init(persistenceController: PersistenceController = .shared) {
        self.persistenceController = persistenceController
    }
    
    /// Safely load image data from Core Data on any thread
    func loadImageData(uuid: UUID) -> Data? {
        let backgroundContext = persistenceController.container.newBackgroundContext()
        var result: Data? = nil
        
        backgroundContext.performAndWait {
            let fetchRequest: NSFetchRequest<ImageEntity> = ImageEntity.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
            fetchRequest.fetchLimit = 1
            
            do {
                let results = try backgroundContext.fetch(fetchRequest)
                result = results.first?.image
            } catch {
                print("Error fetching image from CoreData: \(error)")
            }
        }
        
        return result
    }
    
    /// Safely load file content from Core Data on any thread
    func loadFileContent(uuid: UUID) -> String? {
        let backgroundContext = persistenceController.container.newBackgroundContext()
        var result: String? = nil
        
        backgroundContext.performAndWait {
            let fetchRequest: NSFetchRequest<FileEntity> = FileEntity.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
            fetchRequest.fetchLimit = 1
            
            do {
                let results = try backgroundContext.fetch(fetchRequest)
                if let fileEntity = results.first {
                    let fileName = fileEntity.fileName ?? "Unknown File"
                    let fileSize = fileEntity.fileSize
                    let fileType = fileEntity.fileType ?? "unknown"
                    let textContent = fileEntity.textContent ?? ""
                    
                    result = """
                    File: \(fileName) (\(fileType.uppercased()) file)
                    Size: \(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))
                    
                    Content:
                    \(textContent)
                    """
                }
            } catch {
                print("Error fetching file from CoreData: \(error)")
            }
        }
        
        return result
    }
}
```

#### Step 2: Update ChatGPTHandler to use the safe loader
```swift
// In ChatGPTHandler.swift

class ChatGPTHandler: APIService {
    // ... existing properties
    private let dataLoader = BackgroundDataLoader()
    
    internal func prepareRequest(...) -> URLRequest {
        // ... existing code until image/file processing
        
        // Replace:
        // if let imageData = self.loadImageFromCoreData(uuid: uuid)
        
        // With:
        if let imageData = self.dataLoader.loadImageData(uuid: uuid)
        
        // Same for files:
        if let fileContent = self.dataLoader.loadFileContent(uuid: uuid)
    }
    
    // REMOVE these methods (no longer needed):
    // - private func loadImageFromCoreData(uuid: UUID) -> Data?
    // - private func loadFileContentFromCoreData(uuid: UUID) -> String?
}
```

#### Step 3: Update LMStudioHandler to use the safe loader
```swift
// In LMStudioHandler.swift

class LMStudioHandler: ChatGPTHandler {
    override internal func prepareRequest(...) -> URLRequest {
        // ... existing code
        
        // Replace:
        // if let imageData = self.loadImageFromCoreData(uuid: uuid)
        
        // With:
        if let imageData = self.dataLoader.loadImageData(uuid: uuid)
    }
    
    // REMOVE:
    // - private func loadImageFromCoreData(uuid: UUID) -> Data?
}
```

#### Step 4: Testing
1. Test image uploads in chat with background processing
2. Test file attachments in chat with background processing
3. Verify no crashes occur during concurrent API requests
4. Run Thread Sanitizer in Xcode to verify no threading violations

### Alternative Solution (If Performance Is Concern)
If `performAndWait` blocks too long, consider pre-loading attachment data before calling `prepareRequest`:
1. Load all attachment data on the main thread before sending message
2. Pass the data directly to `prepareRequest` as parameters
3. Avoid Core Data access entirely in background thread

---

## 🔴 CRITICAL BUG #2: Core Data Model Name Typo

### Impact
- **Severity**: CRITICAL - Data loss for existing users
- **Affected Files**: `Warden/WardenApp.swift`

### Problem
The persistent container is initialized with "warenDataModel" (missing 'd') instead of "wardenDataModel". For existing users, fixing this directly would create a new empty database, making all their data appear lost.

### Current Code
```swift
// Line 11 in WardenApp.swift
container = NSPersistentContainer(name: "warenDataModel")
```

### Solution Steps

#### Step 1: Verify the actual data model file name
```bash
# Check what the .xcdatamodeld file is actually named
find . -name "*.xcdatamodeld"
```

#### Step 2A: If file is named "warenDataModel.xcdatamodeld"
Simply rename the file to match the correct spelling:
1. In Xcode, select the `warenDataModel.xcdatamodeld` file
2. Rename it to `wardenDataModel.xcdatamodeld`
3. Update the code:
```swift
container = NSPersistentContainer(name: "wardenDataModel")
```
4. Test with a fresh install
5. No migration needed - the file name matches the code

#### Step 2B: If file is named "wardenDataModel.xcdatamodeld"
We need to implement a migration strategy to handle existing users:

```swift
// Updated PersistenceController init method

init(inMemory: Bool = false) {
    // Try to load with correct name first
    container = NSPersistentContainer(name: "wardenDataModel")
    
    if inMemory {
        container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
    }
    
    // Configure merge policy
    container.viewContext.automaticallyMergesChangesFromParent = true
    container.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
    
    // Enable persistent history tracking
    let description = container.persistentStoreDescriptions.first
    description?.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
    description?.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
    
    // Try to migrate from old typo'd store if it exists
    if !inMemory {
        migrateFromTypoStoreIfNeeded()
    }
    
    container.loadPersistentStores(completionHandler: { (storeDescription, error) in
        // ... existing error handling
    })
}

private func migrateFromTypoStoreIfNeeded() {
    let fileManager = FileManager.default
    
    // Get application support directory
    guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
        return
    }
    
    // Check if old typo'd database exists
    let oldStoreURL = appSupportURL.appendingPathComponent("warenDataModel.sqlite")
    let newStoreURL = appSupportURL.appendingPathComponent("wardenDataModel.sqlite")
    
    // Only migrate if old store exists and new store doesn't
    guard fileManager.fileExists(atPath: oldStoreURL.path),
          !fileManager.fileExists(atPath: newStoreURL.path) else {
        return
    }
    
    print("📦 Migrating database from 'warenDataModel' to 'wardenDataModel'...")
    
    do {
        // Copy the SQLite file
        try fileManager.copyItem(at: oldStoreURL, to: newStoreURL)
        
        // Copy associated files (-shm and -wal)
        let oldShmURL = appSupportURL.appendingPathComponent("warenDataModel.sqlite-shm")
        let newShmURL = appSupportURL.appendingPathComponent("wardenDataModel.sqlite-shm")
        if fileManager.fileExists(atPath: oldShmURL.path) {
            try? fileManager.copyItem(at: oldShmURL, to: newShmURL)
        }
        
        let oldWalURL = appSupportURL.appendingPathComponent("warenDataModel.sqlite-wal")
        let newWalURL = appSupportURL.appendingPathComponent("wardenDataModel.sqlite-wal")
        if fileManager.fileExists(atPath: oldWalURL.path) {
            try? fileManager.copyItem(at: oldWalURL, to: newWalURL)
        }
        
        print("✅ Database migration successful!")
        
        // Optionally: Keep old files as backup for one more release
        // or delete them after successful migration
        
    } catch {
        print("❌ Database migration failed: \(error)")
        // User can still use the app; they just won't see old data
        // Show a user-friendly dialog explaining the situation
    }
}
```

#### Step 3: Update TODO comment
Remove the TODO comment since the issue is resolved:
```swift
// Remove lines 8-10:
// TODO: Model name has typo "warenDataModel" should be "wardenDataModel"
// Requires careful migration to avoid breaking existing user databases
// See bugs.md Bug #2 for migration strategy
```

#### Step 4: Testing
1. Test fresh install (should work normally)
2. Test existing user scenario:
   - Install old version with typo
   - Create test data
   - Install new version
   - Verify all data is preserved
3. Test multiple launches (migration should only happen once)

---

## 🔴 CRITICAL BUG #3: Chat Search Performance

### Impact
- **Severity**: CRITICAL - UI freeze/lag with large chat histories
- **Affected Files**: `Warden/UI/ChatList/ChatListView.swift`

### Problem
The `filteredChats` computed property performs full-text search across ALL messages in ALL chats on the main thread whenever search text changes. This is O(n*m) complexity where n = number of chats and m = average messages per chat.

### Current Code (Lines 87-111)
```swift
private var filteredChats: [ChatEntity] {
    guard !searchText.isEmpty else { return Array(chats) }

    let searchQuery = searchText.lowercased()
    return chats.filter { chat in
        // ... searches through all messages synchronously on main thread
        if let messages = chat.messages.array as? [MessageEntity],
            messages.contains(where: { $0.body.lowercased().contains(searchQuery) })
        {
            return true
        }
        // ...
    }
}
```

### Solution Steps

#### Step 1: Create a debounced search system
```swift
// Add to ChatListView

@State private var debouncedSearchText = ""
@State private var searchTask: Task<Void, Never>?

// Replace direct searchText binding with debounced version
private var filteredChats: [ChatEntity] {
    guard !debouncedSearchText.isEmpty else { return Array(chats) }
    // ... use debouncedSearchText instead of searchText
}
```

#### Step 2: Implement background search with async/await
```swift
// Add to ChatListView

@State private var searchResults: Set<UUID> = []
@State private var isSearching = false

private func performSearch(_ query: String) {
    // Cancel any existing search
    searchTask?.cancel()
    
    guard !query.isEmpty else {
        debouncedSearchText = ""
        searchResults.removeAll()
        return
    }
    
    isSearching = true
    
    searchTask = Task.detached(priority: .userInitiated) {
        let searchQuery = query.lowercased()
        var matchingChatIDs: Set<UUID> = []
        
        // Perform search in background context
        let backgroundContext = PersistenceController.shared.container.newBackgroundContext()
        
        await backgroundContext.perform {
            let fetchRequest = ChatEntity.fetchRequest()
            
            do {
                let allChats = try backgroundContext.fetch(fetchRequest)
                
                for chat in allChats {
                    // Check cancellation periodically
                    if Task.isCancelled { return }
                    
                    // Search in chat name
                    if (chat.name ?? "").lowercased().contains(searchQuery) {
                        matchingChatIDs.insert(chat.id)
                        continue
                    }
                    
                    // Search in system message
                    if chat.systemMessage.lowercased().contains(searchQuery) {
                        matchingChatIDs.insert(chat.id)
                        continue
                    }
                    
                    // Search in persona name
                    if let personaName = chat.persona?.name?.lowercased(),
                       personaName.contains(searchQuery) {
                        matchingChatIDs.insert(chat.id)
                        continue
                    }
                    
                    // Search in messages (batch load)
                    if let messages = chat.messages?.allObjects as? [MessageEntity] {
                        for message in messages {
                            if Task.isCancelled { return }
                            if message.body.lowercased().contains(searchQuery) {
                                matchingChatIDs.insert(chat.id)
                                break
                            }
                        }
                    }
                }
            } catch {
                print("Search error: \(error)")
            }
        }
        
        // Update UI on main thread
        await MainActor.run {
            if !Task.isCancelled {
                self.searchResults = matchingChatIDs
                self.debouncedSearchText = query
                self.isSearching = false
            }
        }
    }
}

// Updated filteredChats to use search results
private var filteredChats: [ChatEntity] {
    guard !debouncedSearchText.isEmpty else { return Array(chats) }
    
    return chats.filter { chat in
        searchResults.contains(chat.id)
    }
}
```

#### Step 3: Add debouncing to search field
```swift
// In searchBarSection
TextField("Search chats...", text: $searchText)
    .textFieldStyle(PlainTextFieldStyle())
    .font(.system(.body))
    .focused($isSearchFocused)
    .onChange(of: searchText) { oldValue, newValue in
        // Debounce search by 300ms
        searchTask?.cancel()
        
        if newValue.isEmpty {
            debouncedSearchText = ""
            searchResults.removeAll()
            isSearching = false
        } else {
            isSearching = true
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
                if !Task.isCancelled {
                    await performSearch(newValue)
                }
            }
        }
    }
```

#### Step 4: Add loading indicator
```swift
// In searchBarSection, add after magnifying glass icon:
if isSearching {
    ProgressView()
        .scaleEffect(0.7)
        .frame(width: 16, height: 16)
} else {
    Image(systemName: "magnifyingglass")
        .foregroundColor(.gray)
}
```

#### Step 5: Optimization - Use Core Data predicates
For even better performance, use Core Data's built-in search:

```swift
// Alternative approach using NSFetchRequest with predicates
private func performSearchWithPredicate(_ query: String) {
    searchTask?.cancel()
    
    guard !query.isEmpty else {
        debouncedSearchText = ""
        searchResults.removeAll()
        return
    }
    
    isSearching = true
    
    searchTask = Task.detached(priority: .userInitiated) {
        let backgroundContext = PersistenceController.shared.container.newBackgroundContext()
        var matchingChatIDs: Set<UUID> = []
        
        await backgroundContext.perform {
            let fetchRequest = ChatEntity.fetchRequest()
            
            // Build compound predicate for efficient searching
            let namePredicate = NSPredicate(format: "name CONTAINS[cd] %@", query)
            let systemMessagePredicate = NSPredicate(format: "systemMessage CONTAINS[cd] %@", query)
            let personaPredicate = NSPredicate(format: "persona.name CONTAINS[cd] %@", query)
            
            // Note: Searching in messages requires a different approach
            // We'll use SUBQUERY for message content
            let messagePredicate = NSPredicate(
                format: "SUBQUERY(messages, $message, $message.body CONTAINS[cd] %@).@count > 0",
                query
            )
            
            let compoundPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
                namePredicate,
                systemMessagePredicate,
                personaPredicate,
                messagePredicate
            ])
            
            fetchRequest.predicate = compoundPredicate
            
            do {
                let matchingChats = try backgroundContext.fetch(fetchRequest)
                matchingChatIDs = Set(matchingChats.map { $0.id })
            } catch {
                print("Search error: \(error)")
            }
        }
        
        await MainActor.run {
            if !Task.isCancelled {
                self.searchResults = matchingChatIDs
                self.debouncedSearchText = query
                self.isSearching = false
            }
        }
    }
}
```

#### Step 6: Testing
1. Test with small chat history (< 10 chats)
2. Test with large chat history (> 100 chats with many messages)
3. Verify UI remains responsive during search
4. Test rapid typing (debouncing should cancel previous searches)
5. Test search cancellation (clear button, empty search)
6. Profile with Instruments to verify no main thread blocking

---

## 🟡 HIGH BUG #4: Broken Chat Title Regeneration

### Impact
- **Severity**: HIGH - Feature is completely broken
- **Affected Files**: `Warden/Store/ChatStore.swift`

### Problem
The `regenerateChatTitlesInProject` function creates an API config with an empty API key (`apiKey: ""`), causing all title generation requests to fail with authentication errors.

### Current Code (Lines 362-367)
```swift
let apiConfig = APIServiceConfig(
    name: apiServiceEntity.name ?? "default",
    apiUrl: apiUrl,
    apiKey: "", // ❌ Empty! Will fail authentication
    model: apiServiceEntity.model ?? AppConstants.chatGptDefaultModel
)
```

### Solution Steps

#### Step 1: Retrieve the actual API key from TokenManager
```swift
// In ChatStore.swift, update regenerateChatTitlesInProject method:

func regenerateChatTitlesInProject(_ project: ProjectEntity) {
    guard let chats = project.chats?.allObjects as? [ChatEntity], !chats.isEmpty else { return }
    
    // Find a suitable API service for title generation
    let apiServiceFetch = NSFetchRequest<APIServiceEntity>(entityName: "APIServiceEntity")
    apiServiceFetch.fetchLimit = 1
    
    do {
        guard let apiServiceEntity = try viewContext.fetch(apiServiceFetch).first else {
            print("No API service available for title regeneration")
            showError(message: "No API service configured. Please add an API service in Settings.")
            return
        }
        
        // Validate API service has required fields
        guard let apiUrl = apiServiceEntity.url else {
            print("API service URL is missing")
            showError(message: "API service configuration is incomplete (missing URL).")
            return
        }
        
        // Retrieve the actual API key from secure storage
        guard let serviceIDString = apiServiceEntity.id?.uuidString else {
            print("API service ID is missing")
            showError(message: "API service configuration is corrupted (missing ID).")
            return
        }
        
        let apiKey: String
        do {
            apiKey = try TokenManager.getToken(for: serviceIDString) ?? ""
            if apiKey.isEmpty {
                print("API key is empty for service: \(apiServiceEntity.name ?? "unknown")")
                showError(message: "API key not found. Please configure your API service in Settings.")
                return
            }
        } catch {
            print("Failed to retrieve API key: \(error)")
            showError(message: "Failed to retrieve API key: \(error.localizedDescription)")
            return
        }
        
        // Create API service configuration with actual API key
        let apiConfig = APIServiceConfig(
            name: apiServiceEntity.name ?? "default",
            apiUrl: apiUrl,
            apiKey: apiKey,  // ✅ Use actual API key
            model: apiServiceEntity.model ?? AppConstants.chatGptDefaultModel
        )
        
        // Create API service from config
        let apiService = APIServiceFactory.createAPIService(config: apiConfig)
        
        // Create a message manager for title generation
        let messageManager = MessageManager(
            apiService: apiService,
            viewContext: viewContext
        )
        
        // Regenerate titles for each chat
        for chat in chats {
            if !chat.messagesArray.isEmpty {
                messageManager.generateChatNameIfNeeded(chat: chat, force: true)
            }
        }
        
        print("✅ Started title regeneration for \(chats.count) chats")
        
    } catch {
        print("Error fetching API service for title regeneration: \(error)")
        showError(message: "Failed to regenerate titles: \(error.localizedDescription)")
    }
}

// Add helper method to show errors to user
private func showError(message: String) {
    DispatchQueue.main.async {
        let alert = NSAlert()
        alert.messageText = "Title Regeneration Failed"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
```

#### Step 2: Improve API service selection
Consider allowing the user to choose which API service to use, or use the project's preferred service:

```swift
// Enhanced version with service selection

func regenerateChatTitlesInProject(_ project: ProjectEntity, usingService: APIServiceEntity? = nil) {
    guard let chats = project.chats?.allObjects as? [ChatEntity], !chats.isEmpty else { return }
    
    let apiServiceEntity: APIServiceEntity
    
    // Use provided service, or find a suitable one
    if let providedService = usingService {
        apiServiceEntity = providedService
    } else {
        // Try to get the default API service
        if let defaultServiceIDString = UserDefaults.standard.string(forKey: "defaultApiService"),
           let url = URL(string: defaultServiceIDString),
           let objectID = viewContext.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: url),
           let defaultService = try? viewContext.existingObject(with: objectID) as? APIServiceEntity {
            apiServiceEntity = defaultService
        } else {
            // Fall back to first available service
            let apiServiceFetch = NSFetchRequest<APIServiceEntity>(entityName: "APIServiceEntity")
            apiServiceFetch.fetchLimit = 1
            
            guard let firstService = try? viewContext.fetch(apiServiceFetch).first else {
                print("No API service available for title regeneration")
                showError(message: "No API service configured. Please add an API service in Settings.")
                return
            }
            
            apiServiceEntity = firstService
        }
    }
    
    // ... rest of the method using apiServiceEntity
}
```

#### Step 3: Add progress tracking and error handling
```swift
// Enhanced with progress tracking

@Published var titleRegenerationProgress: Progress?

func regenerateChatTitlesInProject(_ project: ProjectEntity, usingService: APIServiceEntity? = nil) {
    guard let chats = project.chats?.allObjects as? [ChatEntity], !chats.isEmpty else { return }
    
    // Create progress tracker
    let progress = Progress(totalUnitCount: Int64(chats.count))
    self.titleRegenerationProgress = progress
    
    // ... setup API service as before
    
    var successCount = 0
    var failureCount = 0
    
    // Regenerate titles for each chat with progress tracking
    for (index, chat) in chats.enumerated() {
        guard !chat.messagesArray.isEmpty else {
            progress.completedUnitCount += 1
            continue
        }
        
        // Add completion handler to track success/failure
        messageManager.generateChatName(for: chat, force: true) { result in
            switch result {
            case .success:
                successCount += 1
            case .failure(let error):
                failureCount += 1
                print("Failed to regenerate title for chat \(chat.id): \(error)")
            }
            
            progress.completedUnitCount += 1
            
            // Show summary when complete
            if progress.completedUnitCount == progress.totalUnitCount {
                DispatchQueue.main.async {
                    self.showRegenerationSummary(
                        total: chats.count,
                        success: successCount,
                        failure: failureCount
                    )
                    self.titleRegenerationProgress = nil
                }
            }
        }
    }
}

private func showRegenerationSummary(total: Int, success: Int, failure: Int) {
    let alert = NSAlert()
    alert.messageText = "Title Regeneration Complete"
    alert.informativeText = """
    Successfully regenerated: \(success) of \(total) chats
    \(failure > 0 ? "Failed: \(failure)" : "")
    """
    alert.alertStyle = .informational
    alert.addButton(withTitle: "OK")
    alert.runModal()
}
```

#### Step 4: Update MessageManager to support completion handlers
```swift
// In MessageManager.swift, update generateChatNameIfNeeded:

func generateChatNameIfNeeded(
    chat: ChatEntity,
    force: Bool = false,
    completion: ((Result<Void, Error>) -> Void)? = nil
) {
    guard force || chat.name == "" || chat.name == "New Chat", chat.messages.count > 0 else {
        completion?(.success(()))
        return
    }

    let requestMessages = prepareRequestMessages(
        userMessage: AppConstants.chatGptGenerateChatInstruction,
        chat: chat,
        contextSize: 3
    )
    
    apiService.sendMessage(
        requestMessages,
        temperature: AppConstants.defaultTemperatureForChatNameGeneration
    ) { [weak self] result in
        guard let self = self else { return }

        switch result {
        case .success(let messageBody):
            let chatName = self.sanitizeChatName(messageBody)
            chat.name = chatName
            self.viewContext.saveWithRetry(attempts: 3)
            completion?(.success(()))
            
        case .failure(let error):
            print("Error generating chat name: \(error)")
            completion?(.failure(error))
        }
    }
}
```

#### Step 5: Testing
1. Test with valid API service and key
2. Test with missing API service (should show error)
3. Test with invalid/empty API key (should show error)
4. Test with multiple chats in project
5. Verify titles are actually regenerated
6. Test progress tracking UI

---

## 🟡 HIGH BUG #5: Incomplete Context on Streaming Cancellation

### Impact
- **Severity**: HIGH - Breaks conversation continuity
- **Affected Files**: `Warden/Utilities/MessageManager.swift`

### Problem
When a streaming AI response is cancelled, the partial message is displayed in the UI via `updateLastMessage` but is never saved to `requestMessages` array. The next AI turn won't have context of the partial response, leading to disjointed conversations.

### Current Code (Lines 189-234)
```swift
currentStreamingTask = Task { @MainActor in
    do {
        // ... streaming loop
        for try await chunk in stream {
            accumulatedResponse += chunk
            // ... updates UI
        }
        
        // Only saves to requestMessages if stream completes successfully
        if !Task.isCancelled {
            updateLastMessage(...)
            addNewMessageToRequestMessages(chat: chat, content: accumulatedResponse, role: AppConstants.defaultRole)
            completion(.success(()))
        }
    }
    catch is CancellationError {
        print("Streaming cancelled by user")
        chat.waitingForResponse = false
        // ❌ Partial response NOT saved to requestMessages!
        completion(.failure(CancellationError()))
    }
}
```

### Solution Steps

#### Step 1: Save partial responses on cancellation
```swift
// Update sendMessageStream method in MessageManager.swift

@MainActor
func sendMessageStream(
    _ message: String,
    in chat: ChatEntity,
    contextSize: Int,
    searchUrls: [String]? = nil,
    completion: @escaping (Result<Void, Error>) -> Void
) {
    stopStreaming()
    
    let requestMessages = prepareRequestMessages(userMessage: message, chat: chat, contextSize: contextSize)
    let temperature = (chat.persona?.temperature ?? AppConstants.defaultTemperatureForChat).roundedToOneDecimal()

    currentStreamingTask = Task { @MainActor in
        var accumulatedResponse = ""
        var wasStreamingCancelled = false
        
        do {
            let stream = try await apiService.sendMessageStream(requestMessages, temperature: temperature)
            chat.waitingForResponse = true

            for try await chunk in stream {
                try Task.checkCancellation()
                guard !Task.isCancelled else {
                    wasStreamingCancelled = true
                    break
                }
                
                accumulatedResponse += chunk
                
                guard !Task.isCancelled else {
                    wasStreamingCancelled = true
                    break
                }
                
                if let lastMessage = chat.lastMessage {
                    if lastMessage.own {
                        self.addMessageToChat(chat: chat, message: accumulatedResponse, searchUrls: searchUrls)
                    } else {
                        let now = Date()
                        if now.timeIntervalSince(lastUpdateTime) >= updateInterval {
                            updateLastMessage(
                                chat: chat,
                                lastMessage: lastMessage,
                                accumulatedResponse: accumulatedResponse,
                                searchUrls: searchUrls
                            )
                            lastUpdateTime = now
                        }
                    }
                }
            }
            
            // Handle cancellation: save partial response
            if wasStreamingCancelled || Task.isCancelled {
                print("⚠️ Streaming was cancelled - saving partial response to context")
                
                // Ensure the partial message is in the UI
                if let lastMessage = chat.lastMessage, !lastMessage.own {
                    updateLastMessage(
                        chat: chat,
                        lastMessage: lastMessage,
                        accumulatedResponse: accumulatedResponse,
                        searchUrls: searchUrls,
                        appendCitations: true
                    )
                    
                    // ✅ SAVE PARTIAL RESPONSE TO CONTEXT
                    if !accumulatedResponse.isEmpty {
                        addNewMessageToRequestMessages(
                            chat: chat,
                            content: accumulatedResponse,
                            role: AppConstants.defaultRole
                        )
                        print("✅ Partial response saved to context (\(accumulatedResponse.count) chars)")
                    }
                } else {
                    // No last message yet - create one with partial content
                    if !accumulatedResponse.isEmpty {
                        addMessageToChat(chat: chat, message: accumulatedResponse, searchUrls: searchUrls)
                        addNewMessageToRequestMessages(
                            chat: chat,
                            content: accumulatedResponse,
                            role: AppConstants.defaultRole
                        )
                    }
                }
                
                chat.waitingForResponse = false
                completion(.failure(CancellationError()))
                return
            }
            
            // Normal completion path
            guard let lastMessage = chat.lastMessage else {
                print("⚠️ Warning: No last message found after streaming, creating new message")
                addMessageToChat(chat: chat, message: accumulatedResponse, searchUrls: searchUrls)
                addNewMessageToRequestMessages(chat: chat, content: accumulatedResponse, role: AppConstants.defaultRole)
                completion(.success(()))
                return
            }
            
            updateLastMessage(
                chat: chat,
                lastMessage: lastMessage,
                accumulatedResponse: accumulatedResponse,
                searchUrls: searchUrls,
                appendCitations: true
            )
            addNewMessageToRequestMessages(chat: chat, content: accumulatedResponse, role: AppConstants.defaultRole)
            completion(.success(()))
        }
        catch is CancellationError {
            print("⚠️ Streaming cancelled via exception")
            
            // Save partial response even when cancelled via exception
            if !accumulatedResponse.isEmpty {
                if let lastMessage = chat.lastMessage, !lastMessage.own {
                    updateLastMessage(
                        chat: chat,
                        lastMessage: lastMessage,
                        accumulatedResponse: accumulatedResponse,
                        searchUrls: searchUrls,
                        appendCitations: true
                    )
                    addNewMessageToRequestMessages(
                        chat: chat,
                        content: accumulatedResponse,
                        role: AppConstants.defaultRole
                    )
                } else {
                    addMessageToChat(chat: chat, message: accumulatedResponse, searchUrls: searchUrls)
                    addNewMessageToRequestMessages(
                        chat: chat,
                        content: accumulatedResponse,
                        role: AppConstants.defaultRole
                    )
                }
                print("✅ Partial response saved after cancellation exception")
            }
            
            chat.waitingForResponse = false
            completion(.failure(CancellationError()))
        }
        catch {
            print("Streaming error: \(error)")
            chat.waitingForResponse = false
            completion(.failure(error))
        }
    }
}
```

#### Step 2: Add user indicator for partial responses
Optionally, mark partial responses so users know the AI was interrupted:

```swift
// Update updateLastMessage to add an indicator

private func updateLastMessage(
    chat: ChatEntity,
    lastMessage: MessageEntity,
    accumulatedResponse: String,
    searchUrls: [String]? = nil,
    appendCitations: Bool = false,
    wasInterrupted: Bool = false  // New parameter
) {
    var finalMessage = accumulatedResponse
    
    // Add interruption indicator if needed
    if wasInterrupted && !finalMessage.isEmpty {
        finalMessage += "\n\n*[Response was interrupted]*"
    }
    
    // Convert citations if applicable
    if appendCitations, let urls = searchUrls, !urls.isEmpty {
        finalMessage = convertCitationsToLinks(finalMessage, urls: urls)
    }
    
    chat.waitingForResponse = false
    lastMessage.body = finalMessage
    lastMessage.timestamp = Date()
    lastMessage.waitingForResponse = false

    chat.objectWillChange.send()

    Task {
        await MainActor.run {
            self.viewContext.saveWithRetry(attempts: 1)
        }
    }
}
```

#### Step 3: Test the fix
1. Start a conversation
2. Send a message that will have a long response
3. Cancel the response mid-stream (press Cancel/Escape)
4. Verify the partial response is visible in UI
5. Send a follow-up message referencing the partial response
6. Verify the AI responds with appropriate context
7. Check Core Data to ensure requestMessages contains the partial response

---

## 🟢 MEDIUM BUG #6: Flawed System Prompt Construction

### Impact
- **Severity**: MEDIUM - May degrade AI response quality
- **Affected Files**: `Warden/Utilities/MessageManager.swift`

### Problem
The `buildSystemMessageWithProjectContext` function simply concatenates system messages from chat, persona, and project with newlines. While section headers exist, the delineation between different instruction sets could be clearer for the AI.

### Current Code (Lines 301-338)
```swift
private func buildSystemMessageWithProjectContext(for chat: ChatEntity) -> String {
    var systemMessageComponents: [String] = []
    
    let baseSystemMessage = chat.persona?.systemMessage ?? chat.systemMessage
    if !baseSystemMessage.isEmpty {
        systemMessageComponents.append(baseSystemMessage)
    }
    
    if let project = chat.project {
        let projectInfo = """
        
        PROJECT CONTEXT:
        You are working within the "\(project.name ?? "Untitled Project")" project.
        """
        // ... appends more
    }
    
    return systemMessageComponents.joined(separator: "\n")
}
```

### Solution Steps

#### Step 1: Implement structured prompt formatting
Use clear delimiters and hierarchy:

```swift
// Replace buildSystemMessageWithProjectContext method

private func buildSystemMessageWithProjectContext(for chat: ChatEntity) -> String {
    var sections: [String] = []
    
    // Section 1: Base System Instructions (highest priority)
    let baseSystemMessage = chat.persona?.systemMessage ?? chat.systemMessage
    if !baseSystemMessage.isEmpty {
        sections.append("""
        === BASE INSTRUCTIONS ===
        \(baseSystemMessage)
        ========================
        """)
    }
    
    // Section 2: Project Context (if applicable)
    if let project = chat.project {
        var projectSection = """
        
        === PROJECT CONTEXT ===
        You are working within the "\(project.name ?? "Untitled Project")" project.
        """
        
        if let description = project.projectDescription, !description.isEmpty {
            projectSection += "\n\nProject Description:\n\(description)"
        }
        
        projectSection += "\n======================="
        sections.append(projectSection)
        
        // Section 3: Project-Specific Instructions (overrides base for this project)
        if let customInstructions = project.customInstructions, !customInstructions.isEmpty {
            sections.append("""
            
            === PROJECT-SPECIFIC INSTRUCTIONS ===
            The following instructions are specific to this project and should take precedence when relevant:
            
            \(customInstructions)
            =====================================
            """)
        }
    }
    
    // Add instruction priority note if multiple sections exist
    if sections.count > 1 {
        sections.append("""
        
        === INSTRUCTION PRIORITY ===
        When instructions conflict:
        1. Project-specific instructions take highest priority
        2. Project context provides domain knowledge
        3. Base instructions provide general behavior guidelines
        ============================
        """)
    }
    
    return sections.joined(separator: "\n")
}
```

#### Step 2: Add validation and length management
Prevent system prompts from becoming too long:

```swift
// Enhanced version with length management

private func buildSystemMessageWithProjectContext(for chat: ChatEntity) -> String {
    let maxSystemPromptLength = 4000 // Adjust based on model limits
    
    var sections: [String] = []
    
    // Build sections as before...
    // [same code as Step 1]
    
    let fullPrompt = sections.joined(separator: "\n")
    
    // Validate length
    if fullPrompt.count > maxSystemPromptLength {
        print("⚠️ System prompt exceeds recommended length: \(fullPrompt.count) chars")
        
        // Option 1: Truncate with warning
        let truncated = String(fullPrompt.prefix(maxSystemPromptLength))
        return truncated + "\n\n[Note: System prompt was truncated due to length]"
        
        // Option 2: Prioritize sections (uncomment to use)
        // return buildTruncatedSystemPrompt(chat: chat, maxLength: maxSystemPromptLength)
    }
    
    return fullPrompt
}

// Helper method to intelligently truncate
private func buildTruncatedSystemPrompt(chat: ChatEntity, maxLength: Int) -> String {
    // Priority: Project instructions > Project context > Base instructions
    var result = ""
    var remainingLength = maxLength
    
    // Always include project-specific instructions first (highest priority)
    if let project = chat.project,
       let customInstructions = project.customInstructions,
       !customInstructions.isEmpty {
        let section = """
        === PROJECT-SPECIFIC INSTRUCTIONS ===
        \(customInstructions)
        =====================================
        """
        if section.count < remainingLength {
            result += section
            remainingLength -= section.count
        } else {
            return String(section.prefix(maxLength))
        }
    }
    
    // Then add base instructions if space allows
    let baseSystemMessage = chat.persona?.systemMessage ?? chat.systemMessage
    if !baseSystemMessage.isEmpty && remainingLength > 200 {
        let section = """
        
        === BASE INSTRUCTIONS ===
        \(baseSystemMessage)
        ========================
        """
        if section.count < remainingLength {
            result += section
            remainingLength -= section.count
        } else {
            result += String(section.prefix(remainingLength))
        }
    }
    
    return result
}
```

#### Step 3: Add XML-style formatting option (for Claude/modern models)
Some models like Claude prefer XML-structured prompts:

```swift
// Alternative formatting for models that prefer XML

private func buildSystemMessageWithProjectContext(
    for chat: ChatEntity,
    useXMLFormatting: Bool = false
) -> String {
    if useXMLFormatting {
        return buildXMLFormattedSystemPrompt(for: chat)
    }
    
    // Use existing formatting
    return buildStructuredSystemPrompt(for: chat)
}

private func buildXMLFormattedSystemPrompt(for chat: ChatEntity) -> String {
    var xml = "<system_instructions>\n"
    
    // Base instructions
    let baseSystemMessage = chat.persona?.systemMessage ?? chat.systemMessage
    if !baseSystemMessage.isEmpty {
        xml += "  <base_instructions>\n"
        xml += "    \(baseSystemMessage.replacingOccurrences(of: "\n", with: "\n    "))\n"
        xml += "  </base_instructions>\n"
    }
    
    // Project context
    if let project = chat.project {
        xml += "  <project_context>\n"
        xml += "    <name>\(project.name ?? "Untitled Project")</name>\n"
        
        if let description = project.projectDescription, !description.isEmpty {
            xml += "    <description>\n"
            xml += "      \(description.replacingOccurrences(of: "\n", with: "\n      "))\n"
            xml += "    </description>\n"
        }
        
        if let customInstructions = project.customInstructions, !customInstructions.isEmpty {
            xml += "    <custom_instructions priority=\"high\">\n"
            xml += "      \(customInstructions.replacingOccurrences(of: "\n", with: "\n      "))\n"
            xml += "    </custom_instructions>\n"
        }
        
        xml += "  </project_context>\n"
    }
    
    xml += "</system_instructions>"
    
    return xml
}
```

#### Step 4: Add configuration option
Let users choose formatting style:

```swift
// In AppConstants.swift, add:
static let systemPromptFormattingStyle = "systemPromptFormattingStyle" // UserDefaults key
enum SystemPromptStyle: String {
    case simple = "simple"           // Current basic formatting
    case structured = "structured"   // With clear delimiters
    case xml = "xml"                 // XML-formatted (for Claude)
}

// In MessageManager.swift, read preference:
private func buildSystemMessageWithProjectContext(for chat: ChatEntity) -> String {
    let styleRaw = UserDefaults.standard.string(forKey: AppConstants.systemPromptFormattingStyle) ?? "structured"
    let style = SystemPromptStyle(rawValue: styleRaw) ?? .structured
    
    switch style {
    case .simple:
        return buildSimpleSystemPrompt(for: chat)
    case .structured:
        return buildStructuredSystemPrompt(for: chat)
    case .xml:
        return buildXMLFormattedSystemPrompt(for: chat)
    }
}
```

#### Step 5: Testing
1. Test with chat only (no project, no persona)
2. Test with persona only
3. Test with project context only
4. Test with project + persona + chat system message
5. Test with very long system prompts (verify truncation)
6. Test with conflicting instructions (verify priority works)
7. Compare AI response quality before/after changes

---

## 🟢 MEDIUM BUG #7: Silent API Model Fetch Failure

### Impact
- **Severity**: MEDIUM - User confusion, may select wrong model
- **Affected Files**: `Warden/UI/Preferences/TabAPIServices/APIServiceDetailViewModel.swift`

### Problem
When fetching available models fails, the app silently falls back to a hardcoded list without notifying the user. The `modelFetchError` property is set but never displayed in the UI.

### Current Code (Lines 107-114)
```swift
catch {
    DispatchQueue.main.async {
        self.modelFetchError = error.localizedDescription  // Set but not shown
        self.isLoadingModels = false
        self.fetchedModels = []
    }
}
```

### Solution Steps

#### Step 1: Find the view that uses APIServiceDetailViewModel
```bash
# Search for views that use this ViewModel
rg "APIServiceDetailViewModel" --type swift
```

#### Step 2: Add error alert display
Assuming the view is `APIServiceDetailView.swift`, add error handling:

```swift
// In APIServiceDetailView.swift (or wherever the ViewModel is used)

struct APIServiceDetailView: View {
    @ObservedObject var viewModel: APIServiceDetailViewModel
    @State private var showingModelFetchError = false
    
    var body: some View {
        Form {
            // ... existing form fields
            
            // Models section
            Section(header: Text("Model")) {
                if viewModel.isLoadingModels {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Fetching available models...")
                            .foregroundColor(.secondary)
                    }
                } else {
                    Picker("Model", selection: $viewModel.selectedModel) {
                        ForEach(viewModel.availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                        Text("Custom...").tag("custom")
                    }
                    
                    // Show warning if using fallback models
                    if viewModel.modelFetchError != nil {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Could not fetch models from API")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Button("Details") {
                                showingModelFetchError = true
                            }
                            .font(.caption)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(6)
                    }
                }
            }
            
            // ... rest of form
        }
        .alert("Model Fetch Failed", isPresented: $showingModelFetchError) {
            Button("OK", role: .cancel) {}
            Button("Retry") {
                viewModel.onUpdateModelsList()
            }
        } message: {
            if let error = viewModel.modelFetchError {
                Text("Failed to fetch available models from the API:\n\n\(error)\n\nShowing fallback list. Verify your API URL and key are correct.")
            }
        }
    }
}
```

#### Step 3: Add inline notification in ViewModel
```swift
// In APIServiceDetailViewModel.swift

// Add a published property for user-facing messages
@Published var userNotification: UserNotification?

struct UserNotification: Identifiable {
    let id = UUID()
    let type: NotificationType
    let message: String
    
    enum NotificationType {
        case info
        case warning
        case error
        case success
    }
}

// Update fetchModelsForService method
private func fetchModelsForService() {
    guard type.lowercased() == "ollama" || !apiKey.isEmpty else {
        fetchedModels = []
        // Notify user if API key is missing
        if type.lowercased() != "ollama" {
            userNotification = UserNotification(
                type: .warning,
                message: "API key required to fetch models. Using default model list."
            )
        }
        return
    }
    
    guard let apiUrl = URL(string: url) else {
        fetchedModels = []
        userNotification = UserNotification(
            type: .error,
            message: "Invalid API URL. Using default model list."
        )
        return
    }

    isLoadingModels = true
    modelFetchError = nil
    userNotification = nil // Clear previous notifications

    let config = APIServiceConfig(
        name: type,
        apiUrl: apiUrl,
        apiKey: apiKey,
        model: ""
    )

    let apiService = APIServiceFactory.createAPIService(config: config)

    Task {
        do {
            let models = try await apiService.fetchModels()
            DispatchQueue.main.async {
                self.fetchedModels = models
                self.isLoadingModels = false

                if !models.contains(where: { $0.id == self.selectedModel })
                    && !self.availableModels.contains(where: { $0 == self.selectedModel })
                {
                    self.selectedModel = "custom"
                    self.isCustomModel = true
                }
                
                // Success notification
                self.userNotification = UserNotification(
                    type: .success,
                    message: "Fetched \(models.count) models from API"
                )
                
                // Auto-dismiss success notification after 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    if case .success = self.userNotification?.type {
                        self.userNotification = nil
                    }
                }
            }
        }
        catch {
            DispatchQueue.main.async {
                self.modelFetchError = error.localizedDescription
                self.isLoadingModels = false
                self.fetchedModels = []
                
                // User-facing error notification
                self.userNotification = UserNotification(
                    type: .error,
                    message: "Failed to fetch models: \(self.getUserFriendlyErrorMessage(error))"
                )
            }
        }
    }
}

// Helper to create user-friendly error messages
private func getUserFriendlyErrorMessage(_ error: Error) -> String {
    if let apiError = error as? APIError {
        switch apiError {
        case .unauthorized:
            return "Invalid API key"
        case .serverError(let message):
            return "Server error: \(message)"
        case .rateLimited:
            return "Rate limited - try again later"
        case .invalidResponse:
            return "Invalid response from server"
        case .requestFailed:
            return "Network request failed - check your internet connection"
        default:
            return apiError.localizedDescription
        }
    }
    return error.localizedDescription
}
```

#### Step 4: Add notification banner to UI
```swift
// In APIServiceDetailView.swift, add notification display

var body: some View {
    VStack(spacing: 0) {
        // Notification banner (if present)
        if let notification = viewModel.userNotification {
            NotificationBanner(notification: notification) {
                viewModel.userNotification = nil
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
        
        // Main form content
        Form {
            // ... existing form
        }
    }
    .animation(.easeInOut, value: viewModel.userNotification)
}

// Notification banner component
struct NotificationBanner: View {
    let notification: APIServiceDetailViewModel.UserNotification
    let onDismiss: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .foregroundColor(iconColor)
            
            Text(notification.message)
                .font(.subheadline)
                .foregroundColor(.primary)
            
            Spacer()
            
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding()
        .background(backgroundColor)
        .cornerRadius(8)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    
    private var iconName: String {
        switch notification.type {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        case .success: return "checkmark.circle.fill"
        }
    }
    
    private var iconColor: Color {
        switch notification.type {
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        case .success: return .green
        }
    }
    
    private var backgroundColor: Color {
        switch notification.type {
        case .info: return Color.blue.opacity(0.1)
        case .warning: return Color.orange.opacity(0.1)
        case .error: return Color.red.opacity(0.1)
        case .success: return Color.green.opacity(0.1)
        }
    }
}
```

#### Step 5: Add retry button
```swift
// In the model picker section, add a retry button when fetch fails

if viewModel.modelFetchError != nil {
    HStack {
        Text("Using fallback model list")
            .font(.caption)
            .foregroundColor(.secondary)
        
        Spacer()
        
        Button("Retry Fetch") {
            viewModel.onUpdateModelsList()
        }
        .font(.caption)
        .buttonStyle(.bordered)
    }
}
```

#### Step 6: Add logging/telemetry
```swift
// In APIServiceDetailViewModel.swift, enhance error tracking

catch {
    DispatchQueue.main.async {
        let errorMessage = error.localizedDescription
        self.modelFetchError = errorMessage
        self.isLoadingModels = false
        self.fetchedModels = []
        
        // Log detailed error for debugging
        print("""
        ❌ Model fetch failed for API service
        Service Type: \(self.type)
        Service Name: \(self.name)
        API URL: \(self.url)
        Error: \(errorMessage)
        """)
        
        // Show user notification
        self.userNotification = UserNotification(
            type: .error,
            message: "Failed to fetch models: \(self.getUserFriendlyErrorMessage(error))"
        )
        
        // Optional: Track failure for analytics/monitoring
        // Analytics.track("model_fetch_failed", properties: [
        //     "service_type": self.type,
        //     "error": errorMessage
        // ])
    }
}
```

#### Step 7: Testing
1. Test with valid API service (should fetch and show success)
2. Test with invalid API key (should show auth error)
3. Test with invalid URL (should show error)
4. Test with network disconnected (should show network error)
5. Test retry button functionality
6. Verify fallback model list is used when fetch fails
7. Test notification auto-dismiss for success messages

---

## Implementation Order

When ready to implement, follow this sequence:

1. **Bug #2** (Threading Violation) - Prevents crashes
2. **Bug #3** (Search Performance) - Improves UX significantly  
3. **Bug #1** (Database Typo) - Requires careful testing but prevents data loss
4. **Bug #4** (Chat Title) - Restores broken functionality
5. **Bug #5** (Streaming Context) - Improves conversation quality
6. **Bug #7** (Model Fetch) - Better error handling
7. **Bug #6** (System Prompt) - Polish/optimization

---

## Testing Strategy

### Unit Tests
Create unit tests for:
- `BackgroundDataLoader` (Bug #2)
- Database migration logic (Bug #1)
- Search debouncing (Bug #3)
- Partial response saving (Bug #5)
- System prompt formatting (Bug #6)

### Integration Tests
- Test Core Data threading with Thread Sanitizer enabled
- Test database migration with real user data
- Test search with large datasets (1000+ chats)
- Test streaming cancellation scenarios
- Test API error scenarios

### Manual Testing Checklist
- [ ] Image uploads don't crash with concurrent requests
- [ ] Database migration preserves all user data
- [ ] Search remains responsive with 100+ chats
- [ ] Chat titles regenerate successfully
- [ ] Cancelled responses maintain conversation context
- [ ] AI understands complex system prompts
- [ ] Model fetch errors are clearly communicated

---

## Notes

- All fixes should be thoroughly tested before merging to main
- Consider creating feature flags for testing new implementations
- Document any API changes in commit messages
- Update user-facing documentation if behavior changes
- Consider backward compatibility for database changes

---

**Document Version**: 1.0  
**Created**: 2025-10-30  
**Last Updated**: 2025-10-30
