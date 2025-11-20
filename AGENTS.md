# Warden Development Guide

**Warden** is a native macOS AI chat client (SwiftUI, Core Data) supporting 10+ AI providers.
**Rules**: See `.cursor/rules/warden-development.mdc` for comprehensive patterns.

## Build & Test
- **Run**: Open `Warden.xcodeproj` in Xcode, press Cmd+R.
- **Test**: Press Cmd+U in Xcode.
- **CLI Test**: `xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS'`
- **Style**: 120 char lines, 4-space indent. Follow existing patterns.

## Architecture
- **Structure**: `UI/` (Views) → `Models/` (Data) → `Utilities/` (Helpers) → `Store/` (Persistence).
- **Pattern**: MVVM. `ChatStore.swift` is the single source of truth (Core Data).
- **AI**: `Utilities/APIHandlers/` implements `APIProtocol`. Handlers created via `APIServiceFactory`.
- **Data**: Local-only (Privacy First). Schema in `warenDataModel.xcdatamodeld`.

## Code Style & Conventions
- **Naming**: `*View`, `*ViewModel`, `*Handler`. PascalCase types, camelCase properties.
- **State**: Use `@StateObject` (lifecycle), `@ObservedObject` (passed), `@EnvironmentObject` (global).
- **Concurrency**: Use `async`/`await`. Perform heavy ops on background queues.
- **Security**: NEVER log API keys. Use Keychain. NO telemetry/analytics.
