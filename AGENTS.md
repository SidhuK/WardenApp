# Warden Development Guide for AI Agents

**Warden** is a native macOS AI chat client built with SwiftUI supporting 10+ AI providers. Creator: Karat Sidhu. Platform: macOS 13.0+. See `.cursor/rules/warden-development.mdc` for comprehensive development patterns.

## Build & Test
- **Build/Run**: Open `Warden.xcodeproj` in Xcode and press Cmd+R
- **Test All**: Cmd+U in Xcode
- **Test Single**: Right-click test method in `WardenTests/` or `WardenUITests/` → Run Test (or Cmd+U on selected test)
- **Code Style**: 120 char lines, 4-space indent, follow existing file patterns

## Architecture
- **MVVM**: SwiftUI views + @ObservableObject ViewModels; see `Warden/UI/` for feature-based structure
- **Core Data**: Single source of truth through `Warden/Store/ChatStore.swift`; schema in `warenDataModel.xcdatamodeld` (Chat, Message, Persona, APIService entities); use background contexts for heavy ops
- **AI Integration**: All providers implement `Warden/Utilities/APIHandlers/APIProtocol.swift`; created via `APIServiceFactory.swift`; supports streaming, vision, and reasoning models
- **Structure**: `WardenApp.swift` → `UI/` (views) → `Models/` (data) → `Utilities/` (helpers) → `Store/` (persistence)

## Code Style & Practices
- **Naming**: Views end `View`, ViewModels end `ViewModel`/`Store`, Handlers end `Handler`; all PascalCase; properties/methods camelCase
- **State**: `@StateObject` (lifecycle), `@ObservedObject` (passed), `@EnvironmentObject` (ChatStore), `@AppStorage` (prefs)
- **Privacy/Security**: NEVER log API keys; use Keychain for credentials; zero telemetry; all data local-only; graceful error handling with user alerts
- **Async**: Use async/await with structured concurrency, proper task cancellation, background queues for heavy operations
- **Imports**: SwiftUI, CoreData as needed; check existing files before adding dependencies; include SwiftUI previews with PreviewStateManager
