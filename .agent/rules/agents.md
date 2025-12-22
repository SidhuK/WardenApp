---
trigger: always_on
---

# Warden Development Guide

**Warden** is a native macOS AI chat client (SwiftUI, Core Data) supporting 10+ AI providers.

## Build & Test
- **Build**: `xcodebuild -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' build`
- **Test All**: `xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS'`
- **Single Test**: `xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' -only-testing:WardenTests/TestClassName/testMethodName`
- **Format**: Uses `.swift-format` (120 char lines, 4-space indent).

## Architecture
- **Structure**: `Warden/UI/` (Views) → `Models/` (Data) → `Utilities/` (Helpers) → `Store/` (Core Data).
- **Pattern**: MVVM. `ChatStore.swift` is single source of truth. `APIServiceFactory` creates handlers.
- **AI Handlers**: `Utilities/APIHandlers/` implements `APIProtocol` for each provider.
- **Data**: Local-only Core Data. Schema in `warenDataModel.xcdatamodeld`. Privacy first—NO telemetry.

## Code Style
- **Naming**: `*View`, `*ViewModel`, `*Handler`. PascalCase types, camelCase properties.
- **State**: `@StateObject` (owner), `@ObservedObject` (passed in), `@EnvironmentObject` (global).
- **Concurrency**: `async`/`await`. Heavy work on background queues.
- **Security**: NEVER log API keys. Use Keychain for secrets. NO analytics/tracking.
