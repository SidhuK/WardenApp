import Foundation

extension Notification.Name {
    static let openChatByID = Notification.Name("OpenChatByID")
    static let resetQuickChat = Notification.Name("ResetQuickChat")
    static let recreateMessageManager = Notification.Name("RecreateMessageManager")
    static let retryMessage = Notification.Name("RetryMessage")
    static let ignoreError = Notification.Name("IgnoreError")
    static let selectChatFromProjectSummary = Notification.Name("SelectChatFromProjectSummary")
    static let openPreferences = Notification.Name("OpenPreferences")
    static let openInlineSettings = Notification.Name("OpenInlineSettings")
    static let codeBlockRendered = Notification.Name("CodeBlockRendered")
    static let showQuickSwitcher = Notification.Name("ShowQuickSwitcher")
    static let showModelSwitcher = Notification.Name("ShowModelSwitcher")
    static let newTemporaryChat = Notification.Name("NewTemporaryChat")
    static let selectChatAtIndex = Notification.Name("SelectChatAtIndex")
    static let cycleRecentChats = Notification.Name("CycleRecentChats")
}

