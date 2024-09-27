import Foundation
import SwiftData

@Model
final class ChatThread: Identifiable {
    let id: UUID
    var createdAt: Date
    var title: String
    var hasReceivedFirstMessage: Bool
    var isThinking: Bool
    var selectedModel: String?
    @Relationship(deleteRule: .cascade) var messages: [ChatMessage] = []
    
    init(timestamp: Date, title: String = "", hasReceivedFirstMessage: Bool = false, isThinking: Bool = false, selectedModel: String? = nil) {
        self.id = UUID()
        self.createdAt = timestamp
        self.title = title
        self.hasReceivedFirstMessage = hasReceivedFirstMessage
        self.isThinking = isThinking
        self.selectedModel = selectedModel
    }
}

@Model
final class ChatMessage: Identifiable {
    let id: UUID
    var text: String
    var isUser: Bool
    var createdAt: Date
    
    init(text: String, isUser: Bool, timestamp: Date) {
        self.id = UUID()
        self.text = text
        self.isUser = isUser
        self.createdAt = timestamp
    }
}
