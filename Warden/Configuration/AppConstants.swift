

import Foundation

/// Defines application-wide constants and configurations.
///
/// This struct holds various static properties used throughout the application,
/// including API endpoints, default model names, context sizes, persona presets,
/// and other configuration values.
struct AppConstants {
    /// The default timeout interval for API requests in seconds.
    static let requestTimeout: TimeInterval = 180
    /// The API endpoint for chat completions using the OpenAI protocol.
    static let apiUrlChatCompletions: String = "https://api.openai.com/v1/chat/completions"
    /// The default model name for ChatGPT.
    static let chatGptDefaultModel = "gpt-4o"
    /// The default context size for ChatGPT.
    static let chatGptContextSize: Double = 10
    /// The default system message for ChatGPT.
    static let chatGptSystemMessage: String = ""
    /// The instruction used to generate a short chat name summary.
    static let chatGptGenerateChatInstruction: String =
        "Return a short chat name (max 10 words) as summary for this chat based on the previous message content and system message if it's not default. Don't answer to my message, just generate a name."
    /// The threshold for considering a string 'long' for potential summarization or handling.
    static let longStringCount = 1000
    /// The default role for messages in a conversation.
    static let defaultRole: String = "assistant"
    /// The interval for updating the UI during streamed responses.
    static let streamedResponseUpdateUIInterval: TimeInterval = 0.2
    /// The default name for a persona.
    static let defaultPersonaName = "Default ChatGPT Assistant"
    /// The default symbol for a persona.
    static let defaultPersonaSymbol = "person.circle"
    /// A flag to indicate if default personas have been added.
    static let defaultPersonasFlag = "defaultPersonasAdded"
    /// The default temperature setting for persona-based interactions.
    static let defaultPersonaTemperature: Float = 0.7
    /// The default temperature setting specifically for generating chat names.
    static let defaultTemperatureForChatNameGeneration: Float = 0.6
    /// The default temperature setting for general chat interactions.
    static let defaultTemperatureForChat: Float = 0.7
    /// A list of OpenAI models considered capable of reasoning.
    static let openAiReasoningModels: [String] = [
        "o1", "o1-preview", "o1-mini", "o3-mini", "o3-mini-high", "o3-mini-2025-01-31", "o1-preview-2024-09-12",
        "o1-mini-2024-09-12", "o1-2024-12-17",
    ]
    /// The name of the Fira Code font used in the application.
    static let firaCode = "FiraCodeRoman-Regular"
    /// The name of the PT Mono font used in the application.
    static let ptMono = "PTMono-Regular"

    /// Represents an AI persona with a name, symbol, system message, and temperature.
    struct Persona {
        let name: String
        let symbol: String
        let message: String
        let temperature: Float
    }

    /// Provides predefined persona configurations.
    struct PersonaPresets {
        static let defaultAssistant = Persona(
            name: "Default Assistant",
            symbol: "person.circle",
            message: "",
            temperature: 0.7
        )

        static let theWordsmith = Persona(
            name: "The Wordsmith",
            symbol: "pencil.and.outline",
            message: """
You are a personal writing coach and editor. You excel at refining text, improving grammar, enhancing clarity, adjusting tone (e.g., more formal, more friendly, persuasive), and expanding or condensing content. Your focus is on effective and professional communication.
""",
            temperature: 0.3
        )

        static let theIdeaSparker = Persona(
            name: "The Idea Sparker",
            symbol: "lightbulb",
            message: """
You are a creative brainstorming partner designed to help users overcome mental blocks and generate innovative ideas. You suggest diverse perspectives, offer unconventional solutions, and help expand on nascent concepts.
""",
            temperature: 0.8
        )

        static let theKnowledgeNavigator = Persona(
            name: "The Knowledge Navigator",
            symbol: "book.circle",
            message: """
You are a personal research assistant and information summarizer. You are adept at quickly processing large amounts of information, extracting key facts, summarizing lengthy documents or articles, and answering specific questions based on provided data or general knowledge.
""",
            temperature: 0.2
        )

        static let theEfficiencyExpert = Persona(
            name: "The Efficiency Expert",
            symbol: "chart.line.uptrend.xyaxis",
            message: """
You are a highly organized and analytical assistant focused on optimizing user workflows and productivity. You help break down large projects into manageable steps, suggest optimal task sequences, identify potential bottlenecks, and provide strategies for time management.
""",
            temperature: 0.4
        )

        static let theCriticalThinker = Persona(
            name: "The Critical Thinker",
            symbol: "brain.head.profile",
            message: """
You are an agent that challenges assumptions and helps evaluate arguments from multiple angles. You play \"devil's advocate,\" point out potential flaws in reasoning, identify biases, and encourage deeper analysis before decision-making.
""",
            temperature: 0.6
        )

        static let theSimplifier = Persona(
            name: "The Simplifier",
            symbol: "arrow.down.circle",
            message: """
You are the go-to for making complex topics understandable. You take jargon-filled explanations, technical manuals, or intricate concepts and re-explain them in plain language, using analogies, examples, and step-by-step breakdowns.
""",
            temperature: 0.3
        )

        static let theTechWhisperer = Persona(
            name: "The Tech Whisperer",
            symbol: "laptopcomputer",
            message: """
You are a specialized assistant for technical queries, coding assistance, and troubleshooting. You help debug code snippets, explain programming concepts, suggest optimal software configurations, and provide solutions to common technical issues.
""",
            temperature: 0.2
        )

        static let theGoalSetterMotivator = Persona(
            name: "The Goal Setter & Motivator",
            symbol: "target",
            message: """
You are a supportive and encouraging agent focused on helping users define clear goals, track progress, and stay motivated. You help break down long-term aspirations into actionable steps and offer positive reinforcement.
""",
            temperature: 0.7
        )

        static let allPersonas: [Persona] = [
            defaultAssistant, theWordsmith, theIdeaSparker, theKnowledgeNavigator,
            theEfficiencyExpert, theCriticalThinker, theSimplifier, theTechWhisperer,
            theGoalSetterMotivator,
        ]
    }

    /// The default API type to use.
    static let defaultApiType = "chatgpt"

    /// Represents the configuration for a specific API service.
    struct defaultApiConfiguration {
        let name: String
        let url: String
        let apiKeyRef: String
        let apiModelRef: String
        let defaultModel: String
        let models: [String]
        var maxTokens: Int? = nil
        var inherits: String? = nil
        var modelsFetching: Bool = true
        var imageUploadsSupported: Bool = false
    }

    /// A dictionary of default API configurations by type.
    static let defaultApiConfigurations = [
        "chatgpt": defaultApiConfiguration(
            name: "OpenAI",
            url: "https://api.openai.com/v1/chat/completions",
            apiKeyRef: "https://platform.openai.com/docs/api-reference/api-keys",
            apiModelRef: "https://platform.openai.com/docs/models",
            defaultModel: "gpt-4o-mini",
            models: [
                "o1-preview",
                "o1-mini",
                "gpt-4o",
                "chatgpt-4o-latest",
                "gpt-4o-mini",
                "gpt-4-turbo",
                "gpt-4",
                "gpt-3.5-turbo",
            ],
            imageUploadsSupported: true
        ),
        "ollama": defaultApiConfiguration(
            name: "Ollama",
            url: "http://localhost:11434/api/chat",
            apiKeyRef: "",
            apiModelRef: "https://ollama.com/library",
            defaultModel: "llama3.1",
            models: [
                "llama3.3",
                "llama3.2",
                "llama3.1",
                "llama3.1:70b",
                "llama3.1:400b",
                "qwen2.5:3b",
                "qwen2.5",
                "qwen2.5:14b",
                "qwen2.5:32b",
                "qwen2.5:72b",
                "qwen2.5-coder",
                "phi3",
                "gemma",
            ]
        ),
        "claude": defaultApiConfiguration(
            name: "Claude",
            url: "https://api.anthropic.com/v1/messages",
            apiKeyRef: "https://docs.anthropic.com/en/docs/initial-setup#prerequisites",
            apiModelRef: "https://docs.anthropic.com/en/docs/about-claude/models",
            defaultModel: "claude-3-5-sonnet-latest",
            models: [
                "claude-3-5-sonnet-latest",
                "claude-3-opus-latest",
                "claude-3-haiku-20240307",
            ],
            maxTokens: 4096
        ),
        "xai": defaultApiConfiguration(
            name: "xAI",
            url: "https://api.x.ai/v1/chat/completions",
            apiKeyRef: "https://console.x.ai/",
            apiModelRef: "https://docs.x.ai/docs#models",
            defaultModel: "grok-beta",
            models: ["grok-beta"],
            inherits: "chatgpt"
        ),
        "gemini": defaultApiConfiguration(
            name: "Google Gemini",
            url: "https://generativelanguage.googleapis.com/v1beta/chat/completions",
            apiKeyRef: "https://aistudio.google.com/app/apikey",
            apiModelRef: "https://ai.google.dev/gemini-api/docs/models/gemini#model-variations",
            defaultModel: "gemini-1.5-flash",
            models: [
                "gemini-2.0-flash-exp",
                "gemini-1.5-flash",
                "gemini-1.5-flash-8b",
                "gemini-1.5-pro",
            ],
            imageUploadsSupported: true
        ),
        "perplexity": defaultApiConfiguration(
            name: "Perplexity",
            url: "https://api.perplexity.ai/chat/completions",
            apiKeyRef: "https://www.perplexity.ai/settings/api",
            apiModelRef: "https://docs.perplexity.ai/guides/model-cards#supported-models",
            defaultModel: "llama-3.1-sonar-large-128k-online",
            models: [
                "sonar-reasoning-pro",
                "sonar-reasoning",
                "sonar-pro",
                "sonar",
                "llama-3.1-sonar-small-128k-online",
                "llama-3.1-sonar-large-128k-online",
                "llama-3.1-sonar-huge-128k-online",
            ],
            modelsFetching: false
        ),
        "deepseek": defaultApiConfiguration(
            name: "DeepSeek",
            url: "https://api.deepseek.com/chat/completions",
            apiKeyRef: "https://api-docs.deepseek.com/",
            apiModelRef: "https://api-docs.deepseek.com/quick_start/pricing",
            defaultModel: "deepseek-chat",
            models: [
                "deepseek-chat",
                "deepseek-reasoner",
            ]
        ),
        "openrouter": defaultApiConfiguration(
            name: "OpenRouter",
            url: "https://openrouter.ai/api/v1/chat/completions",
            apiKeyRef: "https://openrouter.ai/docs/api-reference/authentication#using-an-api-key",
            apiModelRef: "https://openrouter.ai/docs/overview/models",
            defaultModel: "deepseek/deepseek-r1:free",
            models: [
                "openai/gpt-4o",
                "deepseek/deepseek-r1:free",
            ]
        ),
        "groq": defaultApiConfiguration(
            name: "Groq",
            url: "https://api.groq.com/openai/v1/chat/completions",
            apiKeyRef: "https://console.groq.com/keys",
            apiModelRef: "https://console.groq.com/docs/models",
            defaultModel: "llama-3.3-70b-versatile",
            models: [
                "meta-llama/llama-4-scout-17b-16e-instruct",
                "meta-llama/llama-4-maverick-17b-128e-instruct",
                "llama-3.3-70b-versatile",
                "llama-3.1-8b-instant",
                "llama3-70b-8192",
                "llama3-8b-8192",
                "deepseek-r1-distill-llama-70b",
                "qwen-qwq-32b",
                "mistral-saba-24b",
                "gemma2-9b-it",
                "mixtral-8x7b-32768",
                "llama-guard-3-8b",
                "meta-llama/Llama-Guard-4-12B",
            ],
            inherits: "chatgpt"
        ),
        "mistral": defaultApiConfiguration(
            name: "Mistral",
            url: "https://api.mistral.ai/v1/chat/completions",
            apiKeyRef: "https://console.mistral.ai/api-keys/",
            apiModelRef: "https://docs.mistral.ai/models/",
            defaultModel: "mistral-large-latest",
            models: [
                "mistral-large-latest",
                "mistral-medium-latest",
                "mistral-small-latest",
                "mistral-tiny-latest",
                "open-mixtral-8x22b",
                "open-mixtral-8x7b",
                "open-mistral-7b"
            ],
            inherits: "chatgpt"
        ),
    ]

    /// A list of available API types.
    static let apiTypes = ["chatgpt", "ollama", "claude", "xai", "gemini", "perplexity", "deepseek", "openrouter", "groq", "mistral"]
    /// Notification name for indicating a new chat.
    static let newChatNotification = Notification.Name("newChatNotification")
    /// Notification name for opening inline settings.
    static let openInlineSettingsNotification = Notification.Name("openInlineSettingsNotification")
    /// The threshold for considering a message large based on the number of symbols.
    static let largeMessageSymbolsThreshold = 25000
    /// The default size for thumbnail images.
    static let thumbnailSize: CGFloat = 300
}

/// Returns the current date formatted as "yyyy-MM-dd".
func getCurrentFormattedDate() -> String {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"
    return dateFormatter.string(from: Date())
}
