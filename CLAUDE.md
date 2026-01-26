# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Warden is a native macOS AI chat client built with SwiftUI and Core Data. It supports 12+ AI providers (OpenAI, Anthropic, Gemini, Google, Deepseek, Mistral, Perplexity, OpenRouter, Ollama, LM Studio, Groq, xAI) with a privacy-first approach—no telemetry, local-only data storage.

## Build & Test Commands

```bash
# Build
xcodebuild -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' build

# Run all tests
xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS'

# Run single test
xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' -only-testing:WardenTests/TestClassName/testMethodName

# Run in Xcode
open Warden.xcodeproj  # then Cmd+R
```

## Code Formatting

Uses `swift-format` with config at `Warden/.swift-format`: 120 char lines, 4-space indent.

## Architecture

**Pattern**: MVVM with `ChatStore.swift` as single source of truth.

**Key flow**: `UI/` (Views) → `Models/` (Data) → `Utilities/` (Services) → `Store/` (Core Data)

**Directory Structure**:
- `Warden/Configuration/` - App constants and global config (`AppConstants.swift`)
- `Warden/Models/` - Core data models (`MessageContent`, `FileAttachment`, `ImageAttachment`, `ReasoningEffort`, `TavilyModels`)
- `Warden/Store/` - `ChatStore.swift` (single source of truth) and Core Data model (`wardenDataModel.xcdatamodeld`)
- `Warden/UI/Chat/` - Main chat interface with modular subdirectories:
  - `BottomContainer/` - Message input and persona selector
  - `BubbleView/` - Chat bubbles, math rendering, tables
  - `ChatParameters/` - Chat-specific configurations
  - `CodeView`, `ThinkingProcessView`, `MultiAgentResponseView`
- `Warden/UI/ChatList/` - Sidebar and list management, `ProjectListView`
- `Warden/UI/Components/` - Reusable UI (`MarkdownView`, `SubmitTextEditor`, `ToastNotification`, `HTMLPreviewView`, `ZoomableImageView`, `SkeletonLoaderView`)
- `Warden/UI/Modifiers/` - SwiftUI modifiers (`GlassEffectModifiers`)
- `Warden/UI/Preferences/` - Settings tabs including MCP, API service config, personas, and tools
- `Warden/UI/WelcomeScreen/` - Onboarding (`WelcomeScreen`, `InteractiveOnboardingView`)
- `Warden/Utilities/` - Services, managers, and API handlers

**AI Provider System**:
- `Utilities/APIHandlers/` contains provider implementations (ChatGPT, Claude, Gemini, Deepseek, Mistral, Perplexity, Ollama, LMStudio, OpenRouter)
- All handlers implement `APIService` protocol and extend `BaseAPIHandler`
- `APIServiceFactory` creates the appropriate handler (Groq/xAI use OpenAI-compatible ChatGPTHandler)
- `APIServiceManager` and `SelectedModelsManager` manage active AI configurations
- `FavoriteModelsManager` manages user-favorited models
- `ModelMetadataFetcher` and `ModelMetadataCache` handle model capabilities and caching

**Key Features**:
- **Multi-Agent**: `MultiAgentMessageManager` enables parallel requests to multiple providers
- **Chat Branching**: `ChatBranchingManager` handles non-linear chat history
- **AI Personas**: `TabAIPersonasView` and `PersonaSelectorView` for custom AI personas
- **Reasoning Control**: `ReasoningEffort` and `ReasoningEffortMenu` for models with reasoning capabilities (o1/o3, DeepSeek R1)
- **Attachments**: `AttachmentResolver`, `FileAttachment`, `ImageAttachment` for file/image handling
- **Projects**: Chats can be organized into projects (`ProjectListView`, `MoveToProjectView`)
- **Chat Sharing**: `ChatSharingService` for exporting/sharing chats
- **Rephrase**: `RephraseService` for message rephrasing
- **Global Hotkeys**: `GlobalHotkeyHandler` manages system-wide shortcuts
- **Floating Panel**: `FloatingPanelManager` handles quick chat overlay windows
- **Menu Bar**: `MenuBarManager` for macOS menu bar integration
- **Updates**: Sparkle integration for auto-updates (`UpdaterManager`, `scripts/` for signing)

**MCP Integration**: `Core/MCP/` contains `MCPManager` and `MCPServerConfig` for Model Context Protocol.

**Search**: `TavilySearchService` + `TavilyModels` for web search integration.

## Code Conventions

- **Naming**: `*View`, `*ViewModel`, `*Handler`, `*Manager`, `*Service`
- **State management**: `@StateObject` (owner), `@ObservedObject` (passed in), `@EnvironmentObject` (global)
- **Concurrency**: `async`/`await`, heavy work on background queues, `StreamingTaskController` for cancellable streams
- **Logging**: Use `WardenLog` static loggers (e.g., `WardenLog.app.debug("message")`, `WardenLog.coreData.error("message")`) instead of `print`. Available loggers: `.app`, `.streaming`, `.rendering`, `.coreData`
- **Security**: Never log API keys, use Keychain for secrets
- **Previews**: Use `PreviewStateManager` for SwiftUI Preview mock data
