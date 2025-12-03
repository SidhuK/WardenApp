# 🛡️ Warden - A Fully Native AI Chat App For macOS

<div align="center">

![](/assets/Logo.png)

![macOS](https://img.shields.io/badge/macOS-000000?style=for-the-badge&logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-FA7343?style=for-the-badge&logo=swift&logoColor=white)
![SwiftUI](https://img.shields.io/badge/SwiftUI-0066CC?style=for-the-badge&logo=swift&logoColor=white)
![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg?style=for-the-badge)
![Open Source](https://img.shields.io/badge/Open%20Source-❤️-red?style=for-the-badge)

**A fast, beautiful, feature-rich, and truly native macOS AI chat app**  
**100% Open Source • 100% Private • 100% Native**

![](/assets/Dark%20Mode.png)

[![](https://img.shields.io/badge/Twitter-1DA1F2?style=for-the-badge&logo=twitter&logoColor=white)](https://x.com/karat_sidhu) [![](https://img.shields.io/badge/GitHub-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/SidhuK) [![](https://img.shields.io/badge/Gumroad-000000?style=for-the-badge&logo=gumroad&logoColor=white)](https://karatsidhu.gumroad.com/l/warden) [![](https://img.shields.io/badge/BuyMeACoffee-FFDD00?style=for-the-badge&logo=buy-me-a-coffee&logoColor=black)](https://www.buymeacoffee.com/karatsidhu)

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
- **LM Studio** (Local model hosting) - **NEW**
- **Ollama** (Local LLMs)
- **OpenRouter** (50+ models)
- **Deepseek**
- **Any OpenAI-compatible API**

### Chat & Interaction Features

- **Web Search**: Search the web in real-time with Tavily integration; see clickable sources directly in responses
- **Code Running**: Use inbuilt SwiftUI code editor to run code
- **Stop Streaming/Stop Generating**: Cancel ongoing AI responses instantly with dynamic send/stop button functionality
- **Smooth Animations**: Subtle, delightful animations throughout with reduce-motion support
- **Searchable Model Selector**: Find models quickly with minimalist interface design
- **Project-Scoped New Chat**: Create new chats directly within specific projects

### Organization & UX Features

- **Native Swipe Actions**: Intuitive swipe gestures for quick delete, rename, and move operations
- **Model Visibility Control**: Choose exactly which models appear in your selector via multi-select interface
- **Optional Sidebar Icons**: Toggle AI provider logos on/off for a cleaner sidebar appearance
- **Subtle Visual Design**: Clean folder highlighting with only icons tinted for minimal distraction
- **Redesigned UI**: Modern, flat interface with cleaner spacing and better visual hierarchy
- **Streamlined Settings**: Easier preference navigation and configuration

### Projects & Organization

![](/assets/Projects.png)

- **Projects/Folders Support**: Organize your chats into logical groups for better workflow management
- **Project-Scoped New Chat**: Create new chats directly within specific projects
- **Subtle Visual Design**: Clean folder highlighting with only icons tinted for minimal distraction
- **Native Swipe Actions**: Intuitive swipe gestures for quick delete, rename, and move operations
- **Model Visibility Control**: Choose exactly which models appear in your selector via multi-select interface
- **Optional Sidebar Icons**: Toggle AI provider logos on/off for a cleaner sidebar appearance

### Enhanced Chat Management

- Powerful bulk chat actions & native macOS shortcuts.

### Multi-Agent Chat System

![](/assets/Multi%20Models.png)

- Chat with multiple AI models simultaneously for diverse perspectives.

### Great User Experience

![](/assets/Welcome%20Page.png)

- Beautiful onboarding, centered input, attachment support, and rich formatting.

### Advanced Model Management

![](/assets/Model%20Selector.png)

- Favorite, search, and filter models with an improved selector UI.


### Privacy & Performance

- Zero telemetry, lightweight, and blazing fast responses.

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
4. **Requirements**: macOS 13.0+, Xcode 14.3+ (v0.6+ supports macOS 26)

### Option 3: Gumroad (Pay What You Want)

- Visit [Gumroad Page](https://karatsidhu.gumroad.com/l/warden) for pay-what-you-want download

### Having Installation Issues?

- Contact on [Twitter](https://x.com/karat_sidhu) or [GitHub Issues](https://github.com/SidhuK/WardenApp/issues)

---

## 🔄 Updates

Currently, the app doesn't auto-update. Check this GitHub repository for new releases:

**⭐ Star this repo to get notified of updates!**

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

--

## 🙏 Credits

This project is forked and heavily inspired by the [MacAI app](https://github.com/Renset/macai) created by Renat. Huge props for making their source code open source and Apache-licensed!

**Created and maintained by [Karat Sidhu](https://x.com/karat_sidhu)**

## 📄 License

This project is **100% open source** and licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

<div align="center">

**Made with ❤️ by [Karat Sidhu](https://x.com/karat_sidhu)**  
**100% Open Source • Forever Free • Community Driven**

[⬆️ Back to Top](#️-warden---a-fully-native-ai-chat-app-for-macos)

</div>
