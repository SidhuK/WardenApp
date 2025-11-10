# Warden Development Guide for AI Agents

**Warden** is a native macOS AI chat client built with SwiftUI. Creator: Karat Sidhu. Platform: macOS 13.0+.

## Build & Test Commands
- **Build**: Open `Warden.xcodeproj` in Xcode and press Cmd+R to build and run
- **Test All**: Cmd+U in Xcode to run all tests
- **Test Single**: Right-click on test method in `WardenTests/` or `WardenUITests/` → Run test
- **Format**: Use `.swift-format` config (120 char line length, 4-space indent)

## Architecture
- **MVVM Pattern**: SwiftUI views + ObservableObject ViewModels
- **Single Source of Truth**: All Core Data operations go through `Warden/Store/ChatStore.swift`
- **API Handlers**: All AI providers implement `Warden/Utilities/APIHandlers/APIProtocol.swift`, created via `APIServiceFactory.swift`
- **Core Data**: Schema in `Warden/Store/warenDataModel.xcdatamodeld` (Chat, Message, Project, Persona entities)
- **Project Structure**: `WardenApp.swift` (entry) → `UI/` (views) → `Models/` (data) → `Utilities/` (helpers)

## Code Style Guidelines
- **Naming**: Views end with `View`, ViewModels end with `ViewModel`/`Store`, Handlers end with `Handler`, all PascalCase
- **State**: Use `@StateObject` for VM lifecycle, `@ObservedObject` for passed VMs, `@EnvironmentObject` for ChatStore, `@AppStorage` for prefs
- **Imports**: SwiftUI, CoreData as needed. Check existing files for framework usage before adding new dependencies
- **Privacy First**: NEVER log API keys, implement zero telemetry, all data local-only
- **Async**: Use async/await with structured concurrency, proper task cancellation, background processing for heavy ops
- **Error Handling**: Graceful degradation with user-friendly messages, no suppressing compiler errors without user request
- **Security**: API keys in secure storage via Keychain, never expose in logs or code
