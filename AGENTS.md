# Warden Development Guide

**Warden** is a native macOS AI chat client (SwiftUI, Core Data) supporting 10+ AI providers.

## Build & Test
- **Build**: `xcodebuild -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' build`
- **Test All**: `xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS'`
- **Single Test**: `xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' -only-testing:WardenTests/TestClassName/testMethodName`
- **Format**: Uses `.swift-format` (120 char lines, 4-space indent). Config at `Warden/.swift-format`.

## Architecture
- **Structure**: `UI/` (Views) → `Models/` (Data) → `Utilities/` (Services) → `Store/` (Core Data) → `Core/` (MCP) → `Configuration/` (Constants).
- **Pattern**: MVVM. `ChatStore.swift` is single source of truth. `APIServiceFactory` creates handlers.
- **AI Handlers**: `Utilities/APIHandlers/` implements `APIProtocol`. Each provider (Claude, GPT, Gemini, etc.) extends `BaseAPIHandler`.
- **MCP**: `Core/MCP/` contains `MCPManager` and `MCPServerConfig` for Model Context Protocol integration.
- **Search**: `TavilySearchService` + `TavilyModels` for web search. `MultiAgentMessageManager` for multi-agent workflows.
- **Data**: Local-only Core Data (`warenDataModel.xcdatamodeld`). Privacy first—NO telemetry.

## Code Style
- **Naming**: `*View`, `*ViewModel`, `*Handler`, `*Manager`, `*Service`. PascalCase types, camelCase properties.
- **State**: `@StateObject` (owner), `@ObservedObject` (passed in), `@EnvironmentObject` (global).
- **Concurrency**: `async`/`await`. Heavy work on background queues. Use `StreamingTaskController` for cancellable streams.
- **Security**: NEVER log API keys. Use Keychain for secrets. NO analytics/tracking.
