import Foundation
import SwiftData

@Model
final class ChatThread: Identifiable {
    var id: UUID
    var createdAt: Date
    var title: String
    var hasReceivedFirstMessage: Bool
    var selectedModel: String?
    // Nil means the model's default thinking behaviour.
    var thinkLevel: String?
    @Relationship(deleteRule: .cascade) var messages: [ChatMessage] = []

    init(timestamp: Date, title: String = "", hasReceivedFirstMessage: Bool = false, selectedModel: String? = nil) {
        self.id = UUID()
        self.createdAt = timestamp
        self.title = title
        self.hasReceivedFirstMessage = hasReceivedFirstMessage
        self.selectedModel = selectedModel
    }

    var chronologicalMessages: [ChatMessage] {
        messages.sorted { $0.createdAt < $1.createdAt }
    }
}

@Model
final class ChatMessage: Identifiable {
    var id: UUID
    var text: String
    var thinking: String?
    var isUser: Bool
    var createdAt: Date
    @Attribute(.externalStorage) var images: [Data]?

    init(text: String, isUser: Bool, timestamp: Date, images: [Data]? = nil) {
        self.id = UUID()
        self.text = text
        self.isUser = isUser
        self.createdAt = timestamp
        self.images = images
    }
}
