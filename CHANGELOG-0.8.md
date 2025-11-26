# 🎉 Warden v0.8 Changelog

> *Your AI chat companion just got a whole lot smarter!* ✨

---

## 🤖 Model Context Protocol (MCP) — The Star of the Show!

We've added full **MCP agent support**, bringing powerful tool-calling capabilities to Warden!

### 🔌 MCP Agent Management
- **✨ New Preferences Panel** — Add, configure, and manage your MCP agents right from settings
- **🎯 Agent Selection in Chat** — Pick which MCP agent to use directly from your chat window
- **🔗 Auto-Connect on Launch** — Your MCP servers connect automatically when you open Warden (with a gentle delay to keep things smooth)
- **🧪 Connection Testing** — Test your MCP agent connections and see their status at a glance

### 🛠️ Tool Calling Magic
- **📊 Tool Call Progress View** — Watch your tools work in real-time with a beautiful progress UI
- **🔧 Tool Management UI** — See and manage all available tools from your connected MCP servers
- **💾 Persistent Status** — Tool call statuses are now saved and restored properly
- **📝 Result Handling** — Tool results are displayed clearly so you always know what's happening

---

## 🌿 Conversation Branching

Ever wanted to explore a different direction mid-conversation? Now you can!

- **🔀 Branch from Any Message** — Click the Branch button on any message to fork your conversation
- **🤖 Pick Your AI** — Choose which AI model to use for your new branch right from the inline selector
- **⚡ Instant Responses** — Branch from your message and get an immediate AI response with your chosen model
- **🏷️ Visual Indicators** — Branched chats show a badge in the sidebar so you always know which conversations are forks
- **📜 Full History** — Branches keep all the context from the original conversation up to your branch point
- **💾 Persistent** — Your branches and their messages are saved automatically

---

## 🔍 Web Search & Citations Overhaul

The web search experience just got a major upgrade!

- **💾 Persistent Search Results** — Search sources are now saved with messages and persist when switching chats
- **🎯 Beautiful Citation Display** — Sources appear below AI responses with collapsible details
- **📊 Source Pills** — Compact, clickable source indicators show at a glance which sources were used
- **🔗 Improved Inline Citations** — Superscript-style numbered citations that link directly to sources
- **✨ Polished Search UI** — Redesigned search results preview with macOS-native styling
- **📱 Better Source Cards** — Relevance indicators, domain extraction, and hover actions for each source
- **🖱️ Quick Actions** — Copy URLs or open sources in browser with one click

---

## 🎨 Fresh UI Vibes

We gave several parts of Warden a visual makeover!

- **💬 Message Cells** — Cleaner, more polished message bubbles
- **⚙️ Settings Tabs** — Revamped General, Hotkeys, Tavily Search, and Danger Zone tabs
- **📝 Input Views** — Better spacing, font sizes, and layout across the board
- **🧹 Cleaner Toolbar** — Removed clutter for a more streamlined experience
- **🎛️ Model Selection** — Smarter logic that knows the difference between "no selection" and "empty selection"

---

## ⚡ Under the Hood

Some technical goodies that make everything run better:

- **🔄 Refactored API Handlers** — Default protocol implementations with proper tool calling support
- **🚀 Streaming Improvements** — Tools parameter support in API message streaming
- **🛡️ Better Error Handling** — Robust connection and process checks in MCP communications
- **🔧 Process Management** — Full stdio communication with proper logging
- **🐛 Crash Prevention** — Handling SIGPIPE signals to keep things stable

---

## 🙏 Thank You!

Thanks for using Warden! We hope these updates make your AI conversations even more powerful and delightful.

*Happy chatting!* 💬✨

---

*Built with ❤️ for the macOS community*
