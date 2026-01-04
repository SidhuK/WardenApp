<div align="center">

<img src="./assets/Logo.png" width="128" />

# Warden
### The Native AI Chat Experience for macOS

![macOS](https://img.shields.io/badge/macOS-000000?style=for-the-badge&logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-FA7343?style=for-the-badge&logo=swift&logoColor=white)
![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg?style=for-the-badge)

<a href="https://findly.tools/wardenapp?utm_source=wardenapp" target="_blank">
  <img 
    src="https://findly.tools/badges/findly-tools-badge-light.svg" 
    alt="Featured on findly.tools" 
    width="150" 
  />
</a>

<br/>

Warden is a fast, beautiful, and privacy-focused AI client built purely in SwiftUI.
No Electron, no web wrappers—just a premium native experience.

[Download for macOS](https://github.com/SidhuK/WardenApp/releases) • [View Website](https://karatsidhu.gumroad.com/l/warden)

<br/>

![Warden Dark Mode](./assets/Dark%20Mode.png)

</div>


```bash
brew install --cask SidhuK/warden/warden
```


## ✨ Why Warden?

Most AI apps today are just websites wrapped in a window (Electron). They feel heavy, drain battery, and don't integrate well with macOS.

Warden is different. It's built with 100% native code, making it:
- **Blazing Fast**: Launches instantly, uses minimal RAM (<150MB).
- **Battery Friendly**: Optimized for Apple Silicon efficiency.
- **Truly Private**: Your data never leaves your device (except to your chosen AI provider).

## 🚀 Features

- **Multi-Model Support**: Use OpenAI, Anthropic (Claude), Gemini, Perplexity,Oenrouter and more using your own API key.
- **Local AI**: Full support for Ollama and LM Studio.
- **Search Capabilities**: Real-time web search integration with citation support.
- **Developer Tools**: Native code execution and syntax highlighting.
- **Fluid Design**: Animations and interactions that feel right at home on your Mac, including liquid glass support for MacOS 26.

## 📥 Installation

### Homebrew (Recommended)

```bash
brew install --cask SidhuK/warden/warden
```

> **Note:** On first launch, right-click → Open (app is not notarized).

### Manual Download

<div align="center">

| **Typical User** | **Developer** |
| :---: | :---: |
| [**Download Installer**](https://github.com/SidhuK/WardenApp/releases)<br>Simply drag to Applications | [**Build from Source**](#build-from-source)<br>Clone and run in Xcode |

</div>

<br>

### Build from Source

```bash
git clone https://github.com/SidhuK/WardenApp.git
cd WardenApp
open Warden.xcodeproj
# Press Cmd+R to run
```
### Automatic Updates: 

Users who have downloaded the app version 0.9 or lower, please download the latest version from the [releases page](https://github.com/SidhuK/WardenApp/releases) to get automatic updates. Earlier versions will not receive updates.

## ❤️ Support

Warden is open source and free. If you enjoy using it, you can support development:

- [Star this repo](https://github.com/SidhuK/WardenApp) 🌟
- [Buy Me a Coffee](https://www.buymeacoffee.com/karatsidhu) ☕️

---

<div align="center">

Created by [Karat Sidhu](https://x.com/karat_sidhu)
Licensed under Apache 2.0

</div>
