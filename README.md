# 🛡️ Warden - A Fully Native AI Chat App For macOS

<div align="center">

![](https://public-files.gumroad.com/m2461w4ne2wewazdslwflsjut8qp)

![macOS](https://img.shields.io/badge/macOS-000000?style=for-the-badge&logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-FA7343?style=for-the-badge&logo=swift&logoColor=white)
![SwiftUI](https://img.shields.io/badge/SwiftUI-0066CC?style=for-the-badge&logo=swift&logoColor=white)
![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg?style=for-the-badge)
![Open Source](https://img.shields.io/badge/Open%20Source-❤️-red?style=for-the-badge)

**A minimalist, beautiful, and truly native macOS AI chat app**  
**100% Open Source • 100% Private • 100% Native**

![](/assets/new_chat.png)

[![](https://img.shields.io/badge/Twitter-1DA1F2?style=for-the-badge&logo=twitter&logoColor=white)](https://x.com/karat_sidhu) [![](https://img.shields.io/badge/GitHub-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/SidhuK) [![](https://img.shields.io/badge/Gumroad-000000?style=for-the-badge&logo=gumroad&logoColor=white)](https://karatsidhu.gumroad.com/l/warden) [![](https://img.shields.io/badge/BuyMeACoffee-FFDD00?style=for-the-badge&logo=buy-me-a-coffee&logoColor=black)](https://www.buymeacoffee.com/karat)

[Download Latest Release](https://github.com/SidhuK/WardenApp/releases) • [Gumroad Page](https://karatsidhu.gumroad.com/l/warden) • [Report Issues](https://github.com/SidhuK/WardenApp/issues) • [View Source Code](https://github.com/SidhuK/WardenApp)

</div>

---

## ✨ What Makes Warden Special

Warden is a **completely native macOS AI chat app** built with SwiftUI that supports multiple AI providers. No Electron bloat, no web wrappers - just a proper, native Mac experience that feels like something Apple would create.

### 🎯 Core Philosophy

- **Native First**: Built entirely with SwiftUI for true macOS integration
- **Privacy Focused**: Zero telemetry, all data stays on your Mac
- **Open Source**: 100% open source under Apache 2.0 license
- **Lightweight**: Under 20MB app size, typically uses less than 150MB RAM
- **Beautiful**: Subtle animations and design choices that make daily use a joy

---

## 🚀 Features

### 🤖 AI Provider Support

- **OpenAI** (ChatGPT, including o1 reasoning models)
- **Anthropic** (Claude)
- **xAI** (Grok)
- **Google Gemini**
- **Perplexity**
- **Groq**
- **Mistral AI**
- **Ollama** (Local LLMs)
- **OpenRouter** (50+ models)
- **Deepseek**
- **Any OpenAI-compatible API**

### 🔥 New in v0.2: Multi-Agent Chat System

![](/assets/multi_agent.png)

- **🤖 Multiple Models Simultaneously**: Chat with multiple AI models at the same time for diverse perspectives and enhanced productivity
- **🎯 Default AI per Assistant**: Each AI persona now has a default model assignment, making it easier to work with specific use cases
- **🧠 Thinking Models Support**: Visual indicators show which models support reasoning/thinking capabilities (automatically detected)

### 💎 Enhanced User Experience

![](/assets/welcome_screen.png)

- ✅ **New Onboarding Experience** - Beautiful welcome screen for first-time users
- ✅ **ChatGPT-Style Centered Input** - New chat interface with centered input field and welcome message
- ✅ **Custom Chat Assistants** - Create assistants with custom system prompts and temperature
- ✅ **Context Control** - Manage context windows on a per-message basis
- ✅ **Syntax Highlighting** - Beautiful code blocks for most programming languages
- ✅ **Image Attachments** - Attach images to your prompts
- ✅ **Artifacts** - Run simple HTML/CSS code directly in the app
- ✅ **Light/Dark Mode** - Seamless theme switching with system accent color support
- ✅ **Swipe Gestures** - Intuitive navigation with smooth animations
- ✅ **Rephrase Button** - AI-powered button to improve and rephrase your questions before sending
- ✅ **Auto-updating Chat Titles** - Chat titles now update automatically based on conversation content
- ✅ **Chat Timestamps** - All chats display creation and last modified timestamps
- ✅ **Enhanced Export** - Export conversations in JSON, Markdown, and plain text formats

### 🎨 Advanced Model Management

![](/assets/model_selector.png)

- ⭐ **Favorite Models** - Mark your most-used models as favorites for quick access
- 🔍 **Searchable Model Selector** - Find models quickly with the new search functionality
- 🧠 **Thinking Models Filter** - Dedicated buttons to easily find and select reasoning-capable models
- 🎯 **Improved Model Selector UI** - Better positioning and enhanced user experience

### 🛠️ Enhanced Interface

![](/assets/new_chat.png)

- 🎨 **Advanced W Logo Animation** - Completely redesigned logo featuring floating motion, shimmer effects, breathing glow, and interactive hover responses
- 📱 **Sidebar Reorganization** - New chat and settings buttons moved to sidebar for better accessibility
- 💫 **Smooth Animations** - Enhanced animations throughout the app with sophisticated multi-layered effects
- 🔧 **Spotlight Integration** - Enhanced macOS Spotlight search integration
- 📝 **Feedback Integration** - Added "Send Feedback" buttons in top menu bar and preferences
- 🔗 **Source Code Access** - Added "View on GitHub" button in preferences

![](/assets/settings_screen.png)

### 🔒 Privacy & Performance

- 🛡️ **Zero Telemetry** - No data collection, everything stays local
- ⚡ **Fast Responses** - Optimized for quick chat responses across all APIs
- 🪶 **Lightweight** - Minimal resource usage compared to Electron alternatives
- 📱 **Native UI** - Follows macOS design language perfectly
- 🔍 **Spotlight Search** - Search your chats directly from macOS Spotlight

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

### Option 4: Homebrew (Coming Soon)

```bash
brew install --cask warden
```

### Having Installation Issues?

- Contact on [Twitter](https://x.com/karat_sidhu) or [GitHub Issues](https://github.com/SidhuK/WardenApp/issues)

---

## 🔄 Updates

Currently, the app doesn't auto-update. Check this GitHub repository for new releases:

**⭐ Star this repo to get notified of updates!**

---

## 📸 Screenshots Gallery

### Main Chat Interface

![Main chat interface showing conversation with AI](/assets/app_screen-1.png)

### Welcome Screen for New Users

![Beautiful onboarding experience](/assets/welcome_screen.png)

### Multi-Agent Chat System

![Chat with multiple AI models simultaneously](/assets/multi_agent.png)

### Advanced Model Selector

![Enhanced model selection with favorites and search](/assets/model_selector.png)

### New Chat Experience

![Centered input with welcome message](/assets/new_chat.png)

### Settings & Preferences

![Comprehensive settings panel](/assets/settings_screen.png)

---

## 🛣️ Roadmap

### Currently in Development

- 🍺 **Homebrew Distribution** - Official Homebrew cask support
- 🔌 **MCP Support** - Model Context Protocol integration

### Future Features Planned

- 🍎 **Apple Shortcuts Integration** - Siri and Shortcuts app support
- 🌐 **Web Search Capabilities** (currently available via Perplexity)
- 🎨 **Image Generation** - AI-powered image creation
- 📊 **Advanced Analytics** - Local conversation insights
- 📁 **Folder Support** - Organize your chats into folders

_Development varies based on available time and community feedback_

---

## 📋 What's New in v0.2

### 🔥 Major Features

- **Multi-Agent Chat System** - Chat with multiple AI models simultaneously
- **Mistral AI Integration** - Full support for Mistral AI API and models
- **Favorite Models** - Mark and quickly access your most-used models
- **Enhanced Model Selector** - Searchable interface with thinking models filter
- **Onboarding Experience** - Beautiful welcome screen for new users
- **ChatGPT-Style Interface** - Centered input with smooth transitions

### 🎨 UI/UX Improvements

- **Advanced Logo Animation** - Multi-layered effects with shimmer and glow
- **Sidebar Reorganization** - Better button layout and accessibility
- **Smooth Animations** - Enhanced transitions throughout the app
- **System Accent Color** - App adapts to your system accent color
- **Feedback Integration** - Easy access to GitHub issues and support

### 🔧 Technical Enhancements

- **Spotlight Integration** - Search chats from macOS Spotlight
- **Auto-updating Titles** - Conversation titles update based on content
- **Enhanced Export** - Multiple format support (JSON, Markdown, Text)
- **Timestamp Display** - Creation and modification dates for all chats

---

## 💝 Support Development

Warden is **completely free and open source** and always will be! However, if you'd like to support further development:

- ☕ [Buy Me A Coffee](https://www.buymeacoffee.com/karatsidhu)
- 💰 [Support on Gumroad](https://karatsidhu.gumroad.com/l/warden) (pay what you want)
- ⭐ Star this repository
- 🐛 Report bugs and suggest features
- 📢 Share with friends and colleagues
- 🛠️ **Contribute Code** - Submit pull requests and help improve Warden!

---

## 🤝 Contributing

Warden is **100% open source** and welcomes contributions! Here's how you can help:

### 🐛 Bug Reports & Feature Requests

- Check [existing issues](https://github.com/SidhuK/WardenApp/issues) first
- Create detailed bug reports with steps to reproduce
- Suggest new features with clear use cases

### 💻 Code Contributions

- Fork the repository
- Create a feature branch (`git checkout -b feature/amazing-feature`)
- Follow the existing code style and patterns
- Test your changes thoroughly
- Submit a pull request with a clear description

### 📝 Documentation

- Improve README documentation
- Add code comments and documentation
- Create tutorials and guides

### 🌍 Translations

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

- ✅ Commercial use allowed
- ✅ Modification allowed
- ✅ Distribution allowed
- ✅ Private use allowed
- ❗ Must include copyright notice
- ❗ Must include license text

---

<div align="center">

**Made with ❤️ by [Karat Sidhu](https://x.com/karat_sidhu)**  
**100% Open Source • Forever Free • Community Driven**

[⬆️ Back to Top](#️-warden---a-fully-native-ai-chat-app-for-macos)

</div>
