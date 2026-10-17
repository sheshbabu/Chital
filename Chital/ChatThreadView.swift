import SwiftUI
import SwiftData

struct ChatThreadView: View {
    @AppStorage("defaultModelName") private var defaultModelName = AppConstants.defaultModelName

    @Environment(\.modelContext) private var context
    @Environment(ChatStreamer.self) private var streamer
    @Bindable var thread: ChatThread
    
    // Whether the end of the conversation is on screen, so streaming only follows when the user hasn't scrolled up.
    @State private var isAtBottom = true

    let availableModels: [OllamaModelInfo]
    let onFirstMessage: () -> Void

    var body: some View {
        let messages = thread.chronologicalMessages
        let isStreaming = streamer.isStreaming(thread)

        VStack {
            messageList(messages, isStreaming: isStreaming)

            ChatInputView(
                isStreaming: isStreaming,
                onSubmit: insertChatMessage,
                onStop: { streamer.stop(thread) },
                selectedModel: Binding(
                    get: { thread.selectedModel ?? "" },
                    set: { thread.selectedModel = $0 }
                ),
                thinkLevel: $thread.thinkLevel,
                models: availableModels
            )
            // The input's own horizontal padding lines its edges up with the message column.
            .frame(maxWidth: AppConstants.chatColumnWidth + 32)
        }
        .padding()
        .onAppear(perform: ensureModelSelected)
        .onChange(of: availableModels) {
            ensureModelSelected()
        }
    }

    private func messageList(_ messages: [ChatMessage], isStreaming: Bool) -> some View {
        let lastText: Int = messages.last?.text.count ?? 0
        let lastThinking: Int = messages.last?.thinking?.count ?? 0
        let streamedLength = lastText + lastThinking

        return ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(messages) { message in
                        ChatBubbleView(
                            message: message,
                            isStreaming: isStreaming,
                            canRetry: !isStreaming && (!message.isUser || message.id == messages.last?.id)
                        ) {
                            retry(message)
                        }
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(bottomId)
                        // Lazy loading adds and removes the marker as it scrolls in and out of view.
                        .onAppear { isAtBottom = true }
                        .onDisappear { isAtBottom = false }
                }
                .frame(maxWidth: AppConstants.chatColumnWidth)
                .frame(maxWidth: .infinity)
                .padding([.horizontal, .top])
            }
            .frame(maxHeight: .infinity)
            .onAppear {
                proxy.scrollTo(bottomId, anchor: .bottom)
            }
            // Deferred so the new message is laid out before scrolling to it.
            .onChange(of: messages.count) {
                isAtBottom = true
                DispatchQueue.main.async {
                    proxy.scrollTo(bottomId, anchor: .bottom)
                }
            }
            .onChange(of: streamedLength) {
                if isAtBottom {
                    proxy.scrollTo(bottomId, anchor: .bottom)
                }
            }
        }
    }

    private let bottomId = "bottom"

    private var selectedModelInfo: OllamaModelInfo? {
        availableModels.first { $0.name == thread.selectedModel }
    }

    private func ensureModelSelected() {
        guard selectedModelInfo == nil else {
            return
        }
        let defaultModel = availableModels.first { $0.name == defaultModelName }
        thread.selectedModel = (defaultModel ?? availableModels.first)?.name
    }

    private func insertChatMessage(text: String, images: [Data]) {
        if thread.modelContext == nil {
            thread.createdAt = Date()
            context.insert(thread)
            onFirstMessage()
        }

        let newMessage = ChatMessage(
            text: text,
            isUser: true,
            timestamp: Date(),
            images: images.isEmpty ? nil : images
        )
        thread.messages.append(newMessage)
        // Autosave can lag behind, so save now to keep the message if the app quits mid-reply.
        try? context.save()

        streamer.send(thread, model: selectedModelInfo)
    }

    // A failed request leaves no reply, so retrying the last user message resends it.
    private func retry(_ message: ChatMessage) {
        let messages = thread.chronologicalMessages
        guard let index = messages.firstIndex(where: { $0.id == message.id }) else {
            return
        }

        let firstIndexToRemove = message.isUser ? index + 1 : index
        for messageToRemove in messages[firstIndexToRemove...] {
            thread.messages.removeAll { $0.id == messageToRemove.id }
            context.delete(messageToRemove)
        }

        streamer.send(thread, model: selectedModelInfo)
    }
}

