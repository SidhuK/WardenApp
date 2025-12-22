import Foundation
import SwiftUI
import AppKit

/// Defines application-wide constants and configurations.
struct AppConstants {
    // MARK: - API & Model Configuration
    static let requestTimeout: TimeInterval = 180
    static let apiUrlChatCompletions: String = "https://api.openai.com/v1/chat/completions"
    static let chatGptDefaultModel = "gpt-4o"
    static let chatGptContextSize: Double = 10
    static let chatGptSystemMessage: String = ""
    static let chatGptGenerateChatInstruction: String = "Return a short chat name (max 10 words) as summary for this chat based on the previous message content and system message if it's not default. Don't answer to my message, just generate a name."
    static let openAiReasoningModels: [String] = ["o1", "o1-preview", "o1-mini", "o3-mini", "o3-mini-high", "o3-mini-2025-01-31", "o1-preview-2024-09-12", "o1-mini-2024-09-12", "o1-2024-12-17"]
    
    // MARK: - Message & Content Configuration
    static let defaultRole: String = "assistant"
    static let longStringCount = 1000
    static let streamedResponseUpdateUIInterval: TimeInterval = 0.05
    static let useIncrementalParsing: Bool = true
    static let largeMessageSymbolsThreshold = 25000
    
    // MARK: - UI Configuration
    static let defaultPersonaName = "Default ChatGPT Assistant"
    static let defaultPersonaSymbol = "person.circle"
    static let firaCode = "FiraCodeRoman-Regular"
    static let ptMono = "PTMono-Regular"
    static let thumbnailSize: CGFloat = 300
    
    // MARK: - Preferences & Flags
    static let defaultPersonasFlag = "defaultPersonasAdded"
    static let defaultApiType = "chatgpt"
    
    // MARK: - Temperature Settings
    struct Temperature {
        static let persona: Float = 0.7
        static let chatNameGeneration: Float = 0.6
        static let chat: Float = 0.7
    }
    
    // Backward compatibility
    static let defaultPersonaTemperature: Float = Temperature.persona
    static let defaultTemperatureForChatNameGeneration: Float = Temperature.chatNameGeneration
    static let defaultTemperatureForChat: Float = Temperature.chat
    
    // MARK: - Fonts
    private static let fontCache: [String: String] = [:]
    
    // MARK: - Semantic Colors
    private static func controlColor() -> Color { Color(NSColor.controlBackgroundColor) }
    
    static var backgroundWindow: Color { Color(NSColor.windowBackgroundColor) }
    static var backgroundChrome: Color { controlColor() }
    static var backgroundElevated: Color { controlColor() }
    static var backgroundSubtle: Color { controlColor().opacity(0.6) }
    static var backgroundSidebar: Color { controlColor() }
    static var backgroundInput: Color { Color(NSColor.textBackgroundColor).opacity(0.96) }
    static var borderSubtle: Color { Color(NSColor.separatorColor).opacity(0.55) }
    static var borderStrong: Color { Color.primary.opacity(0.25) }
    static var textPrimary: Color { Color.primary }
    static var textSecondary: Color { Color.secondary }
    static var textTertiary: Color { Color.secondary.opacity(0.6) }
    static var destructive: Color { systemColor(.systemRed) }
    static var success: Color { systemColor(.systemGreen) }
    static var warning: Color { systemColor(.systemYellow) }
    
    private static func systemColor(_ color: NSColor) -> Color {
        if #available(macOS 11.0, *) {
            return Color(color)
        } else {
            switch color {
            case NSColor.systemRed: return Color.red
            case NSColor.systemGreen: return Color.green
            case NSColor.systemYellow: return Color.yellow
            default: return Color.primary
            }
        }
    }

    /// Represents an AI persona with a name, symbol, system message, and temperature.
    struct Persona {
        let name: String
        let symbol: String
        let message: String
        let temperature: Float
    }

    /// Provides predefined persona configurations.
    struct PersonaPresets {
        private static let personasData: [(name: String, symbol: String, message: String, temp: Float)] = [
            ("Default Assistant", "person.circle", "", 0.7),
            ("The Wordsmith", "pencil.and.outline", "You are a personal writing coach and editor. You excel at refining text, improving grammar, enhancing clarity, adjusting tone (e.g., more formal, more friendly, persuasive), and expanding or condensing content. Your focus is on effective and professional communication.", 0.3),
            ("The Idea Sparker", "lightbulb", "You are a creative brainstorming partner designed to help users overcome mental blocks and generate innovative ideas. You suggest diverse perspectives, offer unconventional solutions, and help expand on nascent concepts.", 0.8),
            ("The Knowledge Navigator", "book.circle", "You are a personal research assistant and information summarizer. You are adept at quickly processing large amounts of information, extracting key facts, summarizing lengthy documents or articles, and answering specific questions based on provided data or general knowledge.", 0.2),
            ("The Efficiency Expert", "chart.line.uptrend.xyaxis", "You are a highly organized and analytical assistant focused on optimizing user workflows and productivity. You help break down large projects into manageable steps, suggest optimal task sequences, identify potential bottlenecks, and provide strategies for time management.", 0.4),
            ("The Critical Thinker", "brain.head.profile", "You are an agent that challenges assumptions and helps evaluate arguments from multiple angles. You play \"devil's advocate,\" point out potential flaws in reasoning, identify biases, and encourage deeper analysis before decision-making.", 0.6),
            ("The Simplifier", "arrow.down.circle", "You are the go-to for making complex topics understandable. You take jargon-filled explanations, technical manuals, or intricate concepts and re-explain them in plain language, using analogies, examples, and step-by-step breakdowns.", 0.3),
            ("The Tech Whisperer", "laptopcomputer", "You are a specialized assistant for technical queries, coding assistance, and troubleshooting. You help debug code snippets, explain programming concepts, suggest optimal software configurations, and provide solutions to common technical issues.", 0.2),
            ("The Goal Setter & Motivator", "target", "You are a supportive and encouraging agent focused on helping users define clear goals, track progress, and stay motivated. You help break down long-term aspirations into actionable steps and offer positive reinforcement.", 0.7),
        ]
        
        static let defaultAssistant = Persona(name: "Default Assistant", symbol: "person.circle", message: "", temperature: 0.7)
        static let theWordsmith = Persona(name: "The Wordsmith", symbol: "pencil.and.outline", message: "You are a personal writing coach and editor. You excel at refining text, improving grammar, enhancing clarity, adjusting tone (e.g., more formal, more friendly, persuasive), and expanding or condensing content. Your focus is on effective and professional communication.", temperature: 0.3)
        static let theIdeaSparker = Persona(name: "The Idea Sparker", symbol: "lightbulb", message: "You are a creative brainstorming partner designed to help users overcome mental blocks and generate innovative ideas. You suggest diverse perspectives, offer unconventional solutions, and help expand on nascent concepts.", temperature: 0.8)
        static let theKnowledgeNavigator = Persona(name: "The Knowledge Navigator", symbol: "book.circle", message: "You are a personal research assistant and information summarizer. You are adept at quickly processing large amounts of information, extracting key facts, summarizing lengthy documents or articles, and answering specific questions based on provided data or general knowledge.", temperature: 0.2)
        static let theEfficiencyExpert = Persona(name: "The Efficiency Expert", symbol: "chart.line.uptrend.xyaxis", message: "You are a highly organized and analytical assistant focused on optimizing user workflows and productivity. You help break down large projects into manageable steps, suggest optimal task sequences, identify potential bottlenecks, and provide strategies for time management.", temperature: 0.4)
        static let theCriticalThinker = Persona(name: "The Critical Thinker", symbol: "brain.head.profile", message: "You are an agent that challenges assumptions and helps evaluate arguments from multiple angles. You play \"devil's advocate,\" point out potential flaws in reasoning, identify biases, and encourage deeper analysis before decision-making.", temperature: 0.6)
        static let theSimplifier = Persona(name: "The Simplifier", symbol: "arrow.down.circle", message: "You are the go-to for making complex topics understandable. You take jargon-filled explanations, technical manuals, or intricate concepts and re-explain them in plain language, using analogies, examples, and step-by-step breakdowns.", temperature: 0.3)
        static let theTechWhisperer = Persona(name: "The Tech Whisperer", symbol: "laptopcomputer", message: "You are a specialized assistant for technical queries, coding assistance, and troubleshooting. You help debug code snippets, explain programming concepts, suggest optimal software configurations, and provide solutions to common technical issues.", temperature: 0.2)
        static let theGoalSetterMotivator = Persona(name: "The Goal Setter & Motivator", symbol: "target", message: "You are a supportive and encouraging agent focused on helping users define clear goals, track progress, and stay motivated. You help break down long-term aspirations into actionable steps and offer positive reinforcement.", temperature: 0.7)
        
        static let allPersonas: [Persona] = [defaultAssistant, theWordsmith, theIdeaSparker, theKnowledgeNavigator, theEfficiencyExpert, theCriticalThinker, theSimplifier, theTechWhisperer, theGoalSetterMotivator]
    }

    /// Represents an advanced project template with comprehensive configuration.
    struct ProjectTemplate: Equatable {
        let id: String
        let name: String
        let category: ProjectTemplateCategory
        let description: String
        let detailedDescription: String
        let icon: String
        let colorCode: String
        let customInstructions: String
        let suggestedModels: [String]
        let summarizationStyle: SummarizationStyle
        let tags: [String]
        let estimatedUsage: UsageLevel
        
        static func == (lhs: ProjectTemplate, rhs: ProjectTemplate) -> Bool { lhs.id == rhs.id }
        
        enum ProjectTemplateCategory: String, CaseIterable {
            case professional = "Professional", educational = "Educational", creative = "Creative"
            case technical = "Technical", research = "Research", personal = "Personal"
            
            var icon: String {
                ["briefcase", "graduationcap", "paintbrush", "terminal", "magnifyingglass", "person"][abs(self.hashValue) % 6]
            }
        }
        
        enum SummarizationStyle: String, CaseIterable {
            case detailed = "detailed", concise = "concise", technical = "technical"
            case creative = "creative", analytical = "analytical"
            
            var description: String {
                switch self {
                case .detailed: return "Comprehensive summaries with full context"
                case .concise: return "Brief, focused summaries"
                case .technical: return "Technical summaries with code and specifications"
                case .creative: return "Creative summaries highlighting innovation"
                case .analytical: return "Data-driven analytical summaries"
                }
            }
        }
        
        enum UsageLevel: String, CaseIterable {
            case beginner = "beginner", intermediate = "intermediate", advanced = "advanced", expert = "expert"
        }
    }

    /// Provides advanced predefined project template configurations.
    struct ProjectTemplatePresets {
        // MARK: - Professional Templates
        
        static let codeReviewAndDevelopment = ProjectTemplate(
            id: "code-review-dev",
            name: "Code Review & Development",
            category: .technical,
            description: "For code reviews, debugging, and software development",
            detailedDescription: "Comprehensive software development project template optimized for code reviews, debugging sessions, architecture discussions, and collaborative development. Includes best practices for security, performance, and maintainability.",
            icon: "chevron.left.forwardslash.chevron.right",
            colorCode: "#007AFF",
            customInstructions: """
You are an expert software development assistant specializing in code review and development best practices. Your focus areas include:

**Code Review Excellence:**
- Analyze code for security vulnerabilities, performance issues, and maintainability
- Suggest improvements following industry best practices and design patterns
- Identify potential bugs and edge cases
- Recommend appropriate testing strategies

**Development Guidance:**
- Provide clear, actionable feedback with specific examples
- Suggest refactoring opportunities when beneficial
- Help with architecture decisions and technical debt management
- Ensure code follows established conventions and standards

**Communication Style:**
- Be constructive and educational in feedback
- Explain the reasoning behind suggestions
- Prioritize critical issues while noting minor improvements
- Offer alternative approaches when applicable

Always consider the broader context of the project, team dynamics, and long-term maintainability in your recommendations.
""",
            suggestedModels: ["gpt-4o", "claude-3-5-sonnet-latest", "deepseek-chat"],
            summarizationStyle: .technical,
            tags: ["development", "code-review", "best-practices", "architecture"],
            estimatedUsage: .intermediate
        )
        
        static let projectManagement = ProjectTemplate(
            id: "project-management",
            name: "Project Management & Planning",
            category: .professional,
            description: "For project planning, team coordination, and delivery management",
            detailedDescription: "Comprehensive project management template for planning, tracking, and delivering projects effectively. Includes methodologies, risk management, stakeholder communication, and team coordination strategies.",
            icon: "chart.line.uptrend.xyaxis.circle",
            colorCode: "#34C759",
            customInstructions: """
You are an experienced project management consultant with expertise in various methodologies including Agile, Scrum, Kanban, and traditional project management. Your role includes:

**Planning & Strategy:**
- Help break down complex projects into manageable phases and tasks
- Assist with timeline estimation, resource allocation, and risk assessment
- Develop project roadmaps and milestone tracking
- Create effective communication plans for stakeholders

**Team Coordination:**
- Facilitate effective team meetings and decision-making processes
- Help resolve conflicts and improve team dynamics
- Suggest tools and processes for better collaboration
- Support remote and hybrid team management

**Delivery Focus:**
- Monitor project progress and identify potential roadblocks
- Suggest course corrections and optimization strategies
- Help maintain quality standards while meeting deadlines
- Ensure proper documentation and knowledge transfer

Always consider the human element in project management, balancing efficiency with team well-being and sustainable practices.
""",
            suggestedModels: ["gpt-4o", "claude-3-5-sonnet-latest", "gemini-1.5-pro"],
            summarizationStyle: .analytical,
            tags: ["project-management", "planning", "agile", "coordination"],
            estimatedUsage: .intermediate
        )
        
        // MARK: - Educational Templates
        
        static let researchAndAnalysis = ProjectTemplate(
            id: "research-analysis",
            name: "Research & Academic Analysis",
            category: .research,
            description: "For academic research, data analysis, and scholarly work",
            detailedDescription: "Advanced research template designed for academic and professional research projects. Includes methodology guidance, data analysis support, literature review assistance, and publication preparation.",
            icon: "doc.text.magnifyingglass",
            colorCode: "#AF52DE",
            customInstructions: """
You are a research methodology expert and academic writing specialist. Your expertise covers:

**Research Design & Methodology:**
- Help develop robust research questions and hypotheses
- Suggest appropriate research methodologies (qualitative, quantitative, mixed-methods)
- Guide literature review processes and source evaluation
- Assist with data collection and sampling strategies

**Analysis & Interpretation:**
- Support statistical analysis and data interpretation
- Help identify patterns, trends, and significant findings
- Suggest visualization techniques for complex data
- Ensure proper citation and academic integrity

**Communication & Publication:**
- Assist with academic writing structure and clarity
- Help prepare manuscripts, reports, and presentations
- Guide peer review processes and revision strategies
- Support grant writing and research proposals

**Critical Thinking:**
- Challenge assumptions and help identify potential biases
- Suggest alternative interpretations and competing theories
- Encourage rigorous evaluation of evidence and sources
- Promote ethical research practices

Always maintain high standards of academic rigor while making complex concepts accessible and actionable.
""",
            suggestedModels: ["o1-preview", "claude-3-5-sonnet-latest", "gpt-4o"],
            summarizationStyle: .analytical,
            tags: ["research", "academic", "analysis", "methodology"],
            estimatedUsage: .advanced
        )
        
        static let learningAndEducation = ProjectTemplate(
            id: "learning-education",
            name: "Learning & Skill Development",
            category: .educational,
            description: "For personal learning, skill development, and educational content",
            detailedDescription: "Comprehensive learning template that adapts to different learning styles and subject areas. Includes personalized learning paths, skill assessment, and progressive difficulty adjustment.",
            icon: "graduationcap",
            colorCode: "#FF9500",
            customInstructions: """
You are a personalized learning companion and educational specialist. Your approach includes:

**Adaptive Learning:**
- Assess learner's current knowledge level and learning style
- Create personalized learning paths with appropriate pacing
- Break down complex topics into digestible, sequential lessons
- Provide multiple explanation approaches (visual, auditory, kinesthetic)

**Engagement & Motivation:**
- Use real-world examples and practical applications
- Encourage active learning through questions and exercises
- Celebrate progress and provide constructive feedback
- Maintain motivation through achievable goals and milestones

**Skill Development:**
- Focus on both theoretical understanding and practical application
- Provide hands-on exercises and project-based learning
- Encourage critical thinking and problem-solving skills
- Support knowledge transfer and retention techniques

**Supportive Environment:**
- Be patient and encouraging, especially with challenging concepts
- Adapt explanations based on learner feedback and comprehension
- Provide multiple practice opportunities with varying difficulty
- Encourage questions and curiosity-driven exploration

Remember that everyone learns differently, so be flexible in your teaching approach and always check for understanding.
""",
            suggestedModels: ["gpt-4o", "claude-3-5-sonnet-latest", "gemini-1.5-pro"],
            summarizationStyle: .detailed,
            tags: ["learning", "education", "skills", "development"],
            estimatedUsage: .beginner
        )
        
        // MARK: - Creative Templates
        
        static let creativeWriting = ProjectTemplate(
            id: "creative-writing",
            name: "Creative Writing & Storytelling",
            category: .creative,
            description: "For creative writing, storytelling, and content creation",
            detailedDescription: "Specialized template for creative writers, authors, and content creators. Includes character development, plot structure, world-building, and editing assistance for various creative formats.",
            icon: "pencil.and.outline",
            colorCode: "#FF2D92",
            customInstructions: """
You are a creative writing mentor and storytelling expert. Your specialties include:

**Story Development:**
- Help develop compelling characters with depth and motivation
- Assist with plot structure, pacing, and narrative arc development
- Support world-building for fiction and speculative genres
- Guide dialogue writing and voice development

**Creative Process:**
- Encourage creative exploration and experimentation
- Help overcome writer's block and creative obstacles
- Suggest writing exercises and prompts for inspiration
- Support different genres from literary fiction to genre writing

**Craft & Technique:**
- Provide feedback on prose style, voice, and tone
- Help with scene construction and narrative flow
- Assist with show vs. tell techniques and sensory details
- Support revision and editing processes

**Publishing & Sharing:**
- Guide manuscript preparation and submission processes
- Help with synopsis writing and query letter creation
- Support platform building and audience engagement
- Encourage community participation and feedback exchange

**Creative Support:**
- Maintain an encouraging and inspiring atmosphere
- Respect diverse voices and storytelling traditions
- Foster artistic growth while honoring personal style
- Balance creative freedom with constructive guidance

Remember that creativity flourishes in a supportive environment where experimentation is encouraged and every voice is valued.
""",
            suggestedModels: ["gpt-4o", "claude-3-5-sonnet-latest", "gemini-1.5-pro"],
            summarizationStyle: .creative,
            tags: ["writing", "storytelling", "creativity", "content"],
            estimatedUsage: .intermediate
        )
        
        static let designAndInnovation = ProjectTemplate(
            id: "design-innovation",
            name: "Design & Innovation Lab",
            category: .creative,
            description: "For design thinking, innovation processes, and creative problem-solving",
            detailedDescription: "Innovation-focused template for designers, product developers, and creative problem-solvers. Includes design thinking methodology, user-centered design, and breakthrough innovation techniques.",
            icon: "paintbrush",
            colorCode: "#5AC8FA",
            customInstructions: """
You are a design thinking facilitator and innovation catalyst. Your expertise encompasses:

**Design Thinking Process:**
- Guide through empathy-driven user research and persona development
- Facilitate problem definition and opportunity identification
- Support ideation sessions with diverse creative techniques
- Assist with rapid prototyping and iterative testing

**Innovation Methodology:**
- Help identify breakthrough opportunities and market gaps
- Encourage questioning assumptions and challenging conventions
- Support systems thinking and holistic solution development
- Guide risk assessment and innovation portfolio management

**Creative Problem-Solving:**
- Apply lateral thinking and alternative perspective techniques
- Encourage cross-pollination of ideas from different domains
- Support both incremental and disruptive innovation approaches
- Help balance creativity with practical implementation constraints

**User-Centered Focus:**
- Maintain focus on human needs and experiences
- Support accessibility and inclusive design principles
- Guide user testing and feedback integration
- Encourage empathy and user journey mapping

**Collaborative Innovation:**
- Facilitate diverse team collaboration and co-creation
- Support cross-functional innovation teams
- Encourage building on others' ideas and collective creativity
- Help manage innovation projects from concept to implementation

Foster an environment where wild ideas are welcomed, failure is a learning opportunity, and human-centered solutions are the ultimate goal.
""",
            suggestedModels: ["gpt-4o", "claude-3-5-sonnet-latest", "gemini-1.5-pro"],
            summarizationStyle: .creative,
            tags: ["design", "innovation", "creativity", "problem-solving"],
            estimatedUsage: .intermediate
        )
        
        // MARK: - Technical Templates
        
        static let dataScience = ProjectTemplate(
            id: "data-science",
            name: "Data Science & Analytics",
            category: .technical,
            description: "For data analysis, machine learning, and statistical modeling",
            detailedDescription: "Comprehensive data science template for analysts, researchers, and ML engineers. Includes statistical analysis, machine learning workflows, data visualization, and predictive modeling.",
            icon: "chart.bar.xaxis",
            colorCode: "#32D74B",
            customInstructions: """
You are a senior data scientist and analytics expert with deep knowledge in statistics, machine learning, and data engineering. Your expertise includes:

**Data Analysis & Statistics:**
- Guide exploratory data analysis and statistical inference
- Help with hypothesis testing and experimental design
- Support data cleaning, transformation, and feature engineering
- Assist with statistical modeling and assumption validation

**Machine Learning:**
- Recommend appropriate ML algorithms for specific problems
- Guide model selection, training, and hyperparameter tuning
- Support model evaluation, validation, and performance metrics
- Help with deployment strategies and model monitoring

**Data Visualization:**
- Create effective visualizations for data exploration and communication
- Guide dashboard design and interactive visualization tools
- Support storytelling with data and presentation techniques
- Help choose appropriate chart types and design principles

**Technical Implementation:**
- Assist with Python, R, SQL, and relevant data science tools
- Guide database design and query optimization
- Support cloud platform integration and scaling strategies
- Help with reproducible research and version control practices

**Business Context:**
- Translate business problems into analytical frameworks
- Help communicate technical findings to non-technical stakeholders
- Support ROI analysis and impact measurement
- Guide ethical AI practices and bias detection

Always emphasize data quality, reproducibility, and clear communication of uncertainty and limitations in analytical work.
""",
            suggestedModels: ["o1-preview", "deepseek-chat", "claude-3-5-sonnet-latest"],
            summarizationStyle: .technical,
            tags: ["data-science", "analytics", "machine-learning", "statistics"],
            estimatedUsage: .advanced
        )
        
        // MARK: - Personal Templates
        
        static let personalProductivity = ProjectTemplate(
            id: "personal-productivity",
            name: "Personal Productivity & Life Management",
            category: .personal,
            description: "For personal organization, goal setting, and life optimization",
            detailedDescription: "Holistic personal productivity template for life organization, goal achievement, and personal development. Includes time management, habit formation, and work-life balance strategies.",
            icon: "person.circle",
            colorCode: "#FFCC00",
            customInstructions: """
You are a personal productivity coach and life optimization specialist. Your approach focuses on:

**Goal Setting & Achievement:**
- Help clarify personal and professional goals using proven frameworks
- Break down long-term aspirations into actionable, measurable steps
- Create accountability systems and progress tracking mechanisms
- Support goal adjustment and iteration based on changing circumstances

**Time & Energy Management:**
- Assess current time usage patterns and identify optimization opportunities
- Recommend personalized productivity systems and tools
- Help establish sustainable routines and habit formation
- Support work-life balance and boundary setting

**Personal Development:**
- Guide self-reflection and personal growth activities
- Support skill development and learning goal achievement
- Help identify strengths and areas for improvement
- Encourage mindful decision-making and values alignment

**Life Organization:**
- Assist with organizational systems for both digital and physical spaces
- Help streamline recurring tasks and decision-making processes
- Support financial planning and resource management
- Guide relationship management and communication skills

**Wellness Integration:**
- Encourage sustainable productivity practices that support well-being
- Help integrate health and wellness goals with productivity systems
- Support stress management and burnout prevention
- Promote mindfulness and present-moment awareness

Remember that true productivity serves your overall life satisfaction and well-being, not just task completion.
""",
            suggestedModels: ["gpt-4o", "claude-3-5-sonnet-latest", "gemini-1.5-pro"],
            summarizationStyle: .detailed,
            tags: ["productivity", "goals", "organization", "personal-development"],
            estimatedUsage: .beginner
        )
        
        // MARK: - Template Collections
        
        static let allTemplates: [ProjectTemplate] = [
            codeReviewAndDevelopment,
            projectManagement,
            researchAndAnalysis,
            learningAndEducation,
            creativeWriting,
            designAndInnovation,
            dataScience,
            personalProductivity
        ]
        
        static let templatesByCategory: [ProjectTemplate.ProjectTemplateCategory: [ProjectTemplate]] = {
            var categoryMap: [ProjectTemplate.ProjectTemplateCategory: [ProjectTemplate]] = [:]
            for category in ProjectTemplate.ProjectTemplateCategory.allCases {
                categoryMap[category] = allTemplates.filter { $0.category == category }
            }
            return categoryMap
        }()
        
        static let featuredTemplates: [ProjectTemplate] = [
            codeReviewAndDevelopment,
            researchAndAnalysis,
            creativeWriting,
            dataScience
        ]
        
        static let beginnerFriendlyTemplates: [ProjectTemplate] = allTemplates.filter { 
            $0.estimatedUsage == .beginner || $0.estimatedUsage == .intermediate 
        }
    }

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
    static let defaultApiConfigurations: [String: defaultApiConfiguration] = [
        "chatgpt": defaultApiConfiguration(name: "OpenAI", url: "https://api.openai.com/v1/chat/completions", apiKeyRef: "https://platform.openai.com/docs/api-reference/api-keys", apiModelRef: "https://platform.openai.com/docs/models", defaultModel: "gpt-4o-mini", models: ["o1-preview", "o1-mini", "gpt-4o", "chatgpt-4o-latest", "gpt-4o-mini", "gpt-4-turbo", "gpt-4", "gpt-3.5-turbo"], imageUploadsSupported: true),
        "ollama": defaultApiConfiguration(name: "Ollama", url: "http://localhost:11434/api/chat", apiKeyRef: "", apiModelRef: "https://ollama.com/library", defaultModel: "llama3.1", models: ["llama3.3", "llama3.2", "llama3.1", "llama3.1:70b", "llama3.1:400b", "qwen2.5:3b", "qwen2.5", "qwen2.5:14b", "qwen2.5:32b", "qwen2.5:72b", "qwen2.5-coder", "phi3", "gemma"]),
        "claude": defaultApiConfiguration(name: "Claude", url: "https://api.anthropic.com/v1/messages", apiKeyRef: "https://docs.anthropic.com/en/docs/initial-setup#prerequisites", apiModelRef: "https://docs.anthropic.com/en/docs/about-claude/models", defaultModel: "claude-3-5-sonnet-latest", models: ["claude-3-5-sonnet-latest", "claude-3-opus-latest", "claude-3-haiku-20240307"], maxTokens: 4096),
        "xai": defaultApiConfiguration(name: "xAI", url: "https://api.x.ai/v1/chat/completions", apiKeyRef: "https://console.x.ai/", apiModelRef: "https://docs.x.ai/docs#models", defaultModel: "grok-beta", models: ["grok-beta"], inherits: "chatgpt"),
        "gemini": defaultApiConfiguration(name: "Google Gemini", url: "https://generativelanguage.googleapis.com/v1beta/chat/completions", apiKeyRef: "https://aistudio.google.com/app/apikey", apiModelRef: "https://ai.google.dev/gemini-api/docs/models/gemini#model-variations", defaultModel: "gemini-1.5-flash", models: ["gemini-2.0-flash-exp", "gemini-1.5-flash", "gemini-1.5-flash-8b", "gemini-1.5-pro"], imageUploadsSupported: true),
        "perplexity": defaultApiConfiguration(name: "Perplexity", url: "https://api.perplexity.ai/chat/completions", apiKeyRef: "https://www.perplexity.ai/settings/api", apiModelRef: "https://docs.perplexity.ai/guides/model-cards#supported-models", defaultModel: "llama-3.1-sonar-large-128k-online", models: ["sonar-reasoning-pro", "sonar-reasoning", "sonar-pro", "sonar", "llama-3.1-sonar-small-128k-online", "llama-3.1-sonar-large-128k-online", "llama-3.1-sonar-huge-128k-online"], modelsFetching: false),
        "deepseek": defaultApiConfiguration(name: "DeepSeek", url: "https://api.deepseek.com/chat/completions", apiKeyRef: "https://api-docs.deepseek.com/", apiModelRef: "https://api-docs.deepseek.com/quick_start/pricing", defaultModel: "deepseek-chat", models: ["deepseek-chat", "deepseek-reasoner"]),
        "openrouter": defaultApiConfiguration(name: "OpenRouter", url: "https://openrouter.ai/api/v1/chat/completions", apiKeyRef: "https://openrouter.ai/docs/api-reference/authentication#using-an-api-key", apiModelRef: "https://openrouter.ai/docs/overview/models", defaultModel: "deepseek/deepseek-r1:free", models: ["openai/gpt-4o", "deepseek/deepseek-r1:free"]),
        "groq": defaultApiConfiguration(name: "Groq", url: "https://api.groq.com/openai/v1/chat/completions", apiKeyRef: "https://console.groq.com/keys", apiModelRef: "https://console.groq.com/docs/models", defaultModel: "llama-3.3-70b-versatile", models: ["meta-llama/llama-4-scout-17b-16e-instruct", "meta-llama/llama-4-maverick-17b-128e-instruct", "llama-3.3-70b-versatile", "llama-3.1-8b-instant", "llama3-70b-8192", "llama3-8b-8192", "deepseek-r1-distill-llama-70b", "qwen-qwq-32b", "mistral-saba-24b", "gemma2-9b-it", "mixtral-8x7b-32768", "llama-guard-3-8b", "meta-llama/Llama-Guard-4-12B"], inherits: "chatgpt"),
        "mistral": defaultApiConfiguration(name: "Mistral", url: "https://api.mistral.ai/v1/chat/completions", apiKeyRef: "https://console.mistral.ai/api-keys/", apiModelRef: "https://docs.mistral.ai/models/", defaultModel: "mistral-large-latest", models: ["mistral-large-latest", "mistral-medium-latest", "mistral-small-latest", "mistral-tiny-latest", "open-mixtral-8x22b", "open-mixtral-8x7b", "open-mistral-7b"], inherits: "chatgpt"),
        "lmstudio": defaultApiConfiguration(name: "LM Studio", url: "http://localhost:1234/v1/chat/completions", apiKeyRef: "https://lmstudio.ai/docs/api/openai-api", apiModelRef: "https://lmstudio.ai/docs/local-server", defaultModel: "local-model", models: ["local-model"], inherits: "chatgpt"),
    ]

    /// A list of available API types.
    static let apiTypes = ["chatgpt", "ollama", "claude", "xai", "gemini", "perplexity", "deepseek", "openrouter", "groq", "mistral", "lmstudio"]
    
    // MARK: - Notifications
    static let newChatNotification = Notification.Name("newChatNotification")
    static let openInlineSettingsNotification = Notification.Name("openInlineSettingsNotification")
    static let openSettingsWindowNotification = Notification.Name("openSettingsWindowNotification")
    static let copyLastResponseNotification = Notification.Name("copyLastResponseNotification")
    static let copyChatNotification = Notification.Name("copyChatNotification")
    static let exportChatNotification = Notification.Name("exportChatNotification")
    static let copyLastUserMessageNotification = Notification.Name("copyLastUserMessageNotification")
    static let newChatHotkeyNotification = Notification.Name("newChatHotkeyNotification")
    static let toggleQuickChatNotification = Notification.Name("toggleQuickChatNotification")
    
    // MARK: - Hotkey Settings
    struct HotkeyKeys {
       static let copyLastResponse = "hotkey_copy_last_response", copyChat = "hotkey_copy_chat", exportChat = "hotkey_export_chat"
       static let copyLastUserMessage = "hotkey_copy_last_user_message", newChat = "hotkey_new_chat"
       static let quickChat = "hotkey_quick_chat"
    }
    
    struct DefaultHotkeys {
        static let copyLastResponse = "⌘⇧C", copyChat = "⌘⇧A", exportChat = "⌘⇧E"
        static let copyLastUserMessage = "⌘⇧U", newChat = "⌘N"
        static let quickChat = "⌘⇧Space"
    }
    
    // MARK: - Tavily Search Configuration
    struct TavilyConfig {
        static let baseURL = "https://api.tavily.com"
        static let defaultSearchDepth = "basic"
        static let defaultMaxResults = 5
        static let maxResultsLimit = 10
        static let searchCommandPrefix = "/search"
        static let searchCommandAliases = ["/search", "/web", "/google"]
        static let searchDepthKey = "tavilySearchDepth"
        static let maxResultsKey = "tavilyMaxResults"
        static let includeAnswerKey = "tavilyIncludeAnswer"
    }
    
    // Maintain backward compatibility
    static let tavilyBaseURL = TavilyConfig.baseURL
    static let tavilyDefaultSearchDepth = TavilyConfig.defaultSearchDepth
    static let tavilyDefaultMaxResults = TavilyConfig.defaultMaxResults
    static let tavilyMaxResultsLimit = TavilyConfig.maxResultsLimit
    static let searchCommandPrefix = TavilyConfig.searchCommandPrefix
    static let searchCommandAliases = TavilyConfig.searchCommandAliases
    static let tavilySearchDepthKey = TavilyConfig.searchDepthKey
    static let tavilyMaxResultsKey = TavilyConfig.maxResultsKey
    static let tavilyIncludeAnswerKey = TavilyConfig.includeAnswerKey
    
    // MARK: - HTML Preview Configuration
    static let viewportMeta = "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no\">"
    
    static func getModernCSS(isMobile: Bool, isTablet: Bool, isDark: Bool) -> String {
        let padding = isMobile ? "16px" : "20px"
        let bg = isDark ? "#1a1a1a" : "#ffffff"
        let color = isDark ? "#e4e4e7" : "#1f2937"
        let fontSize = isMobile ? "14px" : "16px"
        
        let h1Size = isMobile ? "1.8em" : "2.25em"
        let h1Color = isDark ? "#f9fafb" : "#111827"
        
        let h2Size = isMobile ? "1.5em" : "1.875em"
        let h2Color = isDark ? "#f3f4f6" : "#1f2937"
        
        let h3Size = isMobile ? "1.3em" : "1.5em"
        let h3Color = isDark ? "#e5e7eb" : "#374151"
        
        let linkColor = isDark ? "#60a5fa" : "#2563eb"
        let linkHoverColor = isDark ? "#93c5fd" : "#1d4ed8"
        
        let btnPadding = isMobile ? "12px 20px" : "10px 16px"
        let btnFontSize = isMobile ? "14px" : "16px"
        
        let inputPadding = isMobile ? "12px" : "10px"
        let inputBorder = isDark ? "#4b5563" : "#e5e7eb"
        let inputBg = isDark ? "#374151" : "#ffffff"
        let inputColor = isDark ? "#f9fafb" : "#1f2937"
        let inputFontSize = isMobile ? "16px" : "14px"
        
        let containerWidth = isMobile ? "100%" : (isTablet ? "90%" : "100%")
        
        let cardBg = isDark ? "#374151" : "#ffffff"
        let cardBorder = isDark ? "#4b5563" : "#e5e7eb"
        let cardPadding = isMobile ? "16px" : "20px"
        let cardMargin = isMobile ? "12px 0" : "16px 0"

        return """
        <style>
        * {
            box-sizing: border-box;
        }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, 'Fira Sans', 'Droid Sans', 'Helvetica Neue', sans-serif;
            line-height: 1.6;
            margin: 0;
            padding: \(padding);
            background: \(bg);
            color: \(color);
            font-size: \(fontSize);
        }
        
        h1, h2, h3, h4, h5, h6 {
            margin-top: 0;
            margin-bottom: 0.5em;
            font-weight: 600;
            line-height: 1.25;
        }
        
        h1 { font-size: \(h1Size); color: \(h1Color); }
        h2 { font-size: \(h2Size); color: \(h2Color); }
        h3 { font-size: \(h3Size); color: \(h3Color); }
        
        p { margin-bottom: 1em; }
        
        a {
            color: \(linkColor);
            text-decoration: none;
            transition: color 0.2s ease;
        }
        
        a:hover {
            color: \(linkHoverColor);
            text-decoration: underline;
        }
        
        button {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border: none;
            padding: \(btnPadding);
            border-radius: 8px;
            cursor: pointer;
            font-size: \(btnFontSize);
            font-weight: 500;
            transition: all 0.2s ease;
            box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
        }
        
        button:hover {
            transform: translateY(-1px);
            box-shadow: 0 4px 8px rgba(0, 0, 0, 0.15);
        }
        
        input, textarea, select {
            width: 100%;
            padding: \(inputPadding);
            border: 2px solid \(inputBorder);
            border-radius: 6px;
            background: \(inputBg);
            color: \(inputColor);
            font-size: \(inputFontSize);
            transition: border-color 0.2s ease;
        }
        
        input:focus, textarea:focus, select:focus {
            outline: none;
            border-color: #667eea;
            box-shadow: 0 0 0 3px rgba(102, 126, 234, 0.1);
        }
        
        .container {
            max-width: \(containerWidth);
            margin: 0 auto;
        }
        
        .card {
            background: \(cardBg);
            border: 1px solid \(cardBorder);
            border-radius: 8px;
            padding: \(cardPadding);
            margin: \(cardMargin);
            box-shadow: 0 1px 3px 0 rgba(0, 0, 0, 0.1);
        }
        </style>
        """
    }
}

/// Returns the current date formatted as "yyyy-MM-dd".
func getCurrentFormattedDate() -> String {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"
    return dateFormatter.string(from: Date())
}
