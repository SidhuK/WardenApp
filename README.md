# 🛡️ Warden - A Fully Native AI Chat App For macOS

<div align="center">

![](/assets/256-mac.png)

![macOS](https://img.shields.io/badge/macOS-000000?style=for-the-badge&logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-FA7343?style=for-the-badge&logo=swift&logoColor=white)
![SwiftUI](https://img.shields.io/badge/SwiftUI-0066CC?style=for-the-badge&logo=swift&logoColor=white)
![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg?style=for-the-badge)
![Open Source](https://img.shields.io/badge/Open%20Source-❤️-red?style=for-the-badge)

**A minimalist, beautiful, and truly native macOS AI chat app**  
**100% Open Source • 100% Private • 100% Native**

![](/assets/New%20Chat.png)

[![](https://img.shields.io/badge/Twitter-1DA1F2?style=for-the-badge&logo=twitter&logoColor=white)](https://x.com/karat_sidhu) [![](https://img.shields.io/badge/GitHub-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/SidhuK) [![](https://img.shields.io/badge/Gumroad-000000?style=for-the-badge&logo=gumroad&logoColor=white)](https://karatsidhu.gumroad.com/l/warden) [![](https://img.shields.io/badge/BuyMeACoffee-FFDD00?style=for-the-badge&logo=buy-me-a-coffee&logoColor=black)](https://www.buymeacoffee.com/karat)

[Download Latest Release](https://github.com/SidhuK/WardenApp/releases) • [Gumroad Page](https://karatsidhu.gumroad.com/l/warden) • [Report Issues](https://github.com/SidhuK/WardenApp/issues) • [View Source Code](https://github.com/SidhuK/WardenApp)

</div>

---

## ✨ What Makes Warden Special

Warden is a **completely native macOS AI chat app** built with SwiftUI that supports multiple AI providers. No Electron bloat, no web wrappers - just a proper, native Mac experience that feels like something Apple would create.

### Core Philosophy

- **Native First**: Built entirely with SwiftUI for true macOS integration
- **Privacy Focused**: Zero telemetry, all data stays on your Mac
- **Open Source**: 100% open source under Apache 2.0 license
- **Lightweight**: Under 20MB app size, typically uses less than 150MB RAM
- **Beautiful**: Subtle animations and design choices that make daily use a joy

---

## 🚀 Features

### AI Provider Support

- **OpenAI** (ChatGPT, including o1 reasoning models)
- **Anthropic** (Claude)
- **xAI** (Grok)
- **Google Gemini**
- **Perplexity**
- **Groq**
- **Mistral AI**
- **LM Studio** (Local model hosting)
- **Ollama** (Local LLMs)
- **OpenRouter** (50+ models)
- **Deepseek**
- **Any OpenAI-compatible API**

### New in v0.4: Enhanced User Experience

![](/assets/New%20in%20v0.3%20Projects.png)

- **Stop Streaming/Stop Generating**: Cancel ongoing AI responses instantly with dynamic send/stop button functionality
- **Enhanced Model Selector**: Moved to the top of chat interface as a faster popover for better accessibility
- **Searchable Model Selector**: Find models quickly with the new search functionality in API settings
- **LM Studio Integration**: Full support for LM Studio as a local AI provider
- **Tabbed Settings UI**: Complete redesign of settings interface with organized tabs for better navigation
- **Improved Visual Design**: Big Sur glassy look with ultraThinMaterial effects and smooth transitions

### Projects & Organization

![](/assets/Project%20View.png)

- **Projects/Folders Support**: Organize your chats into logical groups for better workflow management
- **Project-Scoped New Chat**: Create new chats directly within specific projects
- **Subtle Visual Design**: Clean folder highlighting with only icons tinted for minimal distraction
- **Native Swipe Actions**: Intuitive swipe gestures for quick delete, rename, and move operations
- **Model Visibility Control**: Choose exactly which models appear in your selector via multi-select interface
- **Optional Sidebar Icons**: Toggle AI provider logos on/off for a cleaner sidebar appearance

### Enhanced Chat Management

- **Bulk Chat Operations**: Select and delete multiple chats with native macOS selection patterns (⌘+Click, ⇧+Click)
- **Smart Selection Toolbar**: Auto-appearing controls with Select All/None, Delete, and Clear actions
- **Keyboard Shortcuts**: Full keyboard support including ⌘+Delete for bulk operations
- **Individual Chat Controls**: Delete, edit, regenerate, and rename actions available within projects

### Multi-Agent Chat System

![](/assets/multi_agent.png)

- **Multiple Models Simultaneously**: Chat with multiple AI models at the same time for diverse perspectives and enhanced productivity
- **Default AI per Assistant**: Each AI persona now has a default model assignment, making it easier to work with specific use cases
- **Thinking Models Support**: Visual indicators show which models support reasoning/thinking capabilities (automatically detected)

### Enhanced User Experience

![](/assets/Welcome%20Page.png)

- **Beautiful Onboarding**: Clean welcome screen with Warden logo branding
- **ChatGPT-Style Centered Input**: New chat interface with centered input field and welcome message
- **Custom Chat Assistants**: Create assistants with custom system prompts and temperature
- **Context Control**: Manage context windows on a per-message basis
- **Syntax Highlighting**: Beautiful code blocks for most programming languages
- **Image Attachments**: Attach images to your prompts
- **Artifacts**: Run simple HTML/CSS code directly in the app
- **Light/Dark Mode**: Seamless theme switching with system accent color support
- **Rephrase Button**: AI-powered button to improve and rephrase your questions before sending
- **Auto-updating Chat Titles**: Chat titles now update automatically based on conversation content
- **Chat Timestamps**: All chats display creation and last modified timestamps
- **Enhanced Export**: Export conversations in JSON, Markdown, and plain text formats

### Advanced Model Management

![](/assets/New%20in%200.3%20select%20models.png)

- **Favorite Models**: Mark your most-used models as favorites for quick access
- **Searchable Model Selector**: Find models quickly with the new search functionality
- **Thinking Models Filter**: Dedicated buttons to easily find and select reasoning-capable models
- **Model Visibility Picker**: Choose exactly which models appear in the selector via multi-select interface
- **Improved Model Selector UI**: Better positioning and enhanced user experience

### Enhanced Interface

![](/assets/New%20Chat.png)

- **Simplified Logo Animation**: Clean, performance-optimized animations with essential hover interactions
- **Reorganized Sidebar**: New chat button above search bar, settings moved to bottom for better accessibility
- **Native Selection Patterns**: Follows standard macOS conventions used in Finder and system apps
- **Enhanced Spotlight Integration**: Improved macOS Spotlight search with proper index cleanup
- **Feedback Integration**: Added "Send Feedback" buttons in top menu bar and preferences
- **Source Code Access**: Added "View on GitHub" button in preferences

![](/assets/settings_screen.png)

### Privacy & Performance

- **Zero Telemetry**: No data collection, everything stays local
- **Fast Responses**: Optimized for quick chat responses across all APIs
- **Lightweight**: Minimal resource usage compared to Electron alternatives
- **Native UI**: Follows macOS design language perfectly
- **Spotlight Search**: Search your chats directly from macOS Spotlight

---

## 📥 Installation

### Option 1: Download from GitHub (Recommended)

1. **Download** the latest release from [GitHub Releases](https://github.com/SidhuK/WardenApp/releases)
2. **Enable installation from unknown developers**:
   - Go to **System Preferences** → **Privacy & Security**
   - Enable **"Allow applications downloaded from: App Store and identified/known developers"**
   - Or run: `sudo spctl --master-disable` in Terminal (not recommended, just use the option above)
3. **Install** by dragging Warden to your Applications folder
4. **First Launch**: You may need to right-click and select "Open" on first launch

### Option 2: Build from Source (Open Source)

1. **Clone the repository**:
   ```bash
   git clone https://github.com/SidhuK/WardenApp.git
   cd WardenApp
   ```
2. **Open in Xcode**: Open `Warden.xcodeproj` in Xcode 14.3 or later
3. **Build and Run**: Press Cmd+R to build and run the app
4. **Requirements**: macOS 13.0+, Xcode 14.3+

### Option 3: Gumroad (Pay What You Want)

- Visit [Gumroad Page](https://karatsidhu.gumroad.com/l/warden) for pay-what-you-want download

### Having Installation Issues?

- Contact on [Twitter](https://x.com/karat_sidhu) or [GitHub Issues](https://github.com/SidhuK/WardenApp/issues)

---

## 🔄 Updates

Currently, the app doesn't auto-update. Check this GitHub repository for new releases:

**⭐ Star this repo to get notified of updates!**

---

## 📸 Screenshots Gallery

### Projects & Organization

![Organize chats into logical projects](/assets/New%20in%20v0.3%20Projects.png)

### Project Creation Interface

![Create and manage projects easily](/assets/Create%20New%20projects.png)

### Enhanced Project View

![Detailed project management interface](/assets/Project%20View.png)

### Main Chat Interface

![Main chat interface showing conversation with AI](/assets/New%20Chat.png)

### Beautiful Welcome Screen

![Clean onboarding experience with Warden branding](/assets/Welcome%20Page.png)

### Multi-Agent Chat System

![Chat with multiple AI models simultaneously](/assets/multi_agent.png)

### Advanced Model Selector

![Enhanced model selection with visibility controls](/assets/New%20in%200.3%20select%20models.png)

### Dark Mode Support

![Beautiful dark mode interface](/assets/Dark%20Mode.png)

### Settings & Preferences

![Comprehensive settings panel](/assets/settings_screen.png)

---

## 🛣️ Roadmap

### Future Features Planned

#### High Priority

- **Private Chat**: Enhanced privacy mode for sensitive conversations, chats marked as private will not be indexed by Spotlight or saved to disk
- **Model Context Protocol (MCP)**: Extended protocol support for enhanced AI capabilities
- **Homebrew Distribution**: Official Homebrew cask support for easier installation

#### Usage Analytics & Cost Tracking

- **Per-Generation Cost Tracking**: Display approximate cost for each AI response
- **Token Usage Statistics**: Track total tokens used per chat and across all conversations
- **API Cost Breakdown**: Detailed cost analysis per AI provider with running totals
- **Chat-Level Cost Display**: Show estimated cost next to time, retry, copy, delete actions

#### Enhanced Functionality

- **Extended Attachment Support**: Support for additional file types beyond images, csv, pdf, etc.
- **Sparkle Framework Integration**: Ability to automatically update the app
- **Apple Shortcuts Integration**: Siri and Shortcuts app support
- **Web Search Capabilities** (currently available via Perplexity)
- **Image Generation**: AI-powered image creation
- **Advanced Analytics**: Local conversation insights

#### Completed Features

- **Projects/Folders Support**: Organize your chats into folders (Completed in v0.3)
- **Stop Streaming/Stop Generating**: Cancel ongoing AI responses (Completed in v0.4)
- **LM Studio Integration**: Local model hosting support (Completed in v0.4)

_Development varies based on available time and community feedback, this is a free weekends project for me, so please be patient with me._

---

## 📋 What's New in v0.4

### Major Features

- **LM Studio Integration**: Added support for LM Studio as a new AI provider for local model hosting
- **Stop Streaming/Stop Generating Button**: Users can now cancel ongoing AI responses instantly with dynamic send/stop button functionality
  - Task Management: Streaming tasks are now tracked for both single and multi-agent chats
  - Cancellation Support: New `stopStreaming()` methods in message managers with proper state cleanup
  - Input Control: Text input is disabled during streaming to prevent conflicts
  - Visual Feedback: UI responds instantly to streaming state changes
  - Uses Swift's structured concurrency (`Task`, `Task.checkCancellation()`) for reliable cancellation

### Enhanced Interface

- **Enhanced Model Selector**: Moved model selector to the top of chat interface as a faster popover
- **Searchable Model Selector**: Model selector in API settings is now searchable by model names
- **Select All/None Controls**: Improved model selection interface in settings with bulk selection options
- **Tabbed Settings UI**: Complete redesign of settings interface with organized tabs for better navigation

### UI Layout Improvements

- Moved model selector to top of interface for better accessibility
- Repositioned "Add assistants" button outside message input area
- Moved Send button outside input box for cleaner layout
- Redesigned message input box for improved visual appeal
- Increased size and weight of "How can I help?" text (SF Pro Display Semibold)
- Added subtle gray microcopy below main help text for better guidance
- Added extra padding between model selector, input box, and quick action buttons

### Visual Effects

- Applied Big Sur glassy look to New Thread button with minimal gradient
- Added subtle pulse animation to input cursor and "How can I help?" text when idle
- Implemented ultraThinMaterial (SwiftUI) for input fields and buttons
- Added smooth transitions with matchedGeometryEffect for expanding input on focus

### Bug Fixes

- **API Error Handling**: Improved crash error handling for more robust API interactions
- **Projects Sidebar**: Fixed padding issues affecting sidebar layout and chat alignment
- **UI Responsiveness**: Enhanced overall UI responsiveness and interaction feedback

## 📋 What's New in v0.3

### Major Features: Projects & Organization

- **Projects/Folders Support**: Organize chats into logical groups with custom instructions and context
- **Project-Scoped New Chat**: Create new chats directly within specific projects with inherited settings
- **Subtle Visual Design**: Clean folder highlighting with only folder icons tinted for minimal distraction
- **Native Swipe Actions**: Intuitive swipe gestures for projects and chats (delete, rename, move)

### Enhanced Model Management

- **Model Visibility Picker**: Choose exactly which models appear in the selector via multi-select interface
- **Optional Sidebar Icons**: Toggle AI provider logos on/off for a cleaner sidebar appearance
- **Warden Logo Branding**: New chat welcome screen features Warden logo instead of AI provider logos

### Improved Chat Management

- **Per-Chat Actions in Projects**: Full chat management (delete, edit, regenerate, rename) within project views
- **Bulk Selection Improvements**: Consistent selection state when switching between projects
- **Enhanced Navigation**: New chat button moved above search bar, settings relocated to sidebar bottom

### Bug Fixes & Polish

- **Fixed Project Selection**: Creating or editing projects no longer auto-selects the first project
- **Consistent Edit Behavior**: Project editing reliably pre-selects the correct project
- **Chat Operation Logic**: Fixed selection state for regenerate, rename, and delete operations
- **UI Polish**: Removed empty details pane in project creation for cleaner layout

## 📋 What's New in v0.2.1

### Bulk Chat Management

- **Bulk Delete Chats**: Select multiple chats and delete them at once with native macOS selection patterns
- **Smart Selection Toolbar**: Auto-appearing toolbar with Select All/None, Delete, and Clear actions
- **Keyboard Shortcuts**: Support for ⌘+Click (toggle), ⇧+Click (range), and ⌘+Delete (bulk delete)

### Performance & UX Improvements

- **Simplified Animations**: Removed complex floating, pulse, shimmer effects for better performance
- **Native Selection Patterns**: Follows standard macOS conventions used in Finder and system apps
- **Enhanced Spotlight Support**: Proper cleanup of search indexes when chats are deleted
- **Accessibility Improvements**: Better VoiceOver support and keyboard navigation

---

## 💝 Support Development

Warden is **completely free and open source** and always will be! However, if you'd like to support further development:

- [Buy Me A Coffee](https://www.buymeacoffee.com/karatsidhu)
- [Support on Gumroad](https://karatsidhu.gumroad.com/l/warden) (pay what you want)
- Star this repository
- Report bugs and suggest features
- Share with friends and colleagues
- **Contribute Code**: Submit pull requests and help improve Warden!

---

## 🤝 Contributing

Warden is **100% open source** and welcomes contributions! Here's how you can help:

### Bug Reports & Feature Requests

- Check [existing issues](https://github.com/SidhuK/WardenApp/issues) first
- Create detailed bug reports with steps to reproduce
- Suggest new features with clear use cases

### Code Contributions

- Fork the repository
- Create a feature branch (`git checkout -b feature/amazing-feature`)
- Follow the existing code style and patterns
- Test your changes thoroughly
- Submit a pull request with a clear description

### Documentation

- Improve README documentation
- Add code comments and documentation
- Create tutorials and guides

### Translations

- Help translate Warden into other languages
- Improve existing translations

---

## 🙏 Credits

This project is forked and heavily inspired by the [MacAI app](https://github.com/Renset/macai) created by Renat. Huge props for making their source code open source and Apache-licensed!

**Created and maintained by [Karat Sidhu](https://x.com/karat_sidhu)**

---

## ⚠️ Disclaimer

This is my first Swift app, so please bear with me as I continue to work on bug fixes and improvements. I bear no responsibility for any data loss - please backup important conversations.

---

## 📄 License

This project is **100% open source** and licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

**Key License Points:**

- Commercial use allowed
- Modification allowed
- Distribution allowed
- Private use allowed
- Must include copyright notice
- Must include license text

---

<div align="center">

**Made with ❤️ by [Karat Sidhu](https://x.com/karat_sidhu)**  
**100% Open Source • Forever Free • Community Driven**

[⬆️ Back to Top](#️-warden---a-fully-native-ai-chat-app-for-macos)

</div>
