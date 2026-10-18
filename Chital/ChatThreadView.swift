import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ChatThreadView: View {
    @AppStorage("defaultModelName") private var defaultModelName = AppConstants.defaultModelName

    @Environment(\.modelContext) private var context
    @Environment(ChatStreamer.self) private var streamer
    @Bindable var thread: ChatThread

    // Whether the end of the conversation is on screen, so streaming only follows when the user hasn't scrolled up.
    @State private var isAtBottom = true
    @State private var exportDocument: MarkdownDocument?
    // Only recent messages are laid out until asked, since the eager list lays out every message on each update.
    @State private var showsAllMessages = false
    @State private var droppedItems: [NSItemProvider] = []
    @State private var isDropTargeted = false
    // Kept here while typing, since writing it to the thread on every keystroke would invalidate every SwiftData view.
    @State private var draft: String
    @FocusState private var isInputFocused: Bool

    let availableModels: [OllamaModelInfo]
    let onFirstMessage: () -> Void
    let onSelectThread: (ChatThread) -> Void

    init(thread: ChatThread, availableModels: [OllamaModelInfo], onFirstMessage: @escaping () -> Void, onSelectThread: @escaping (ChatThread) -> Void) {
        self.thread = thread
        self.availableModels = availableModels
        self.onFirstMessage = onFirstMessage
        self.onSelectThread = onSelectThread
        _draft = State(initialValue: thread.draft ?? "")
    }

    var body: some View {
        let messages = thread.chronologicalMessages
        let isStreaming = streamer.isStreaming(thread)

        VStack {
            messageList(messages, isStreaming: isStreaming)

            ChatInputView(
                isStreaming: isStreaming,
                onSubmit: insertChatMessage,
                onStop: { streamer.stop(thread) },
                text: $draft,
                selectedModel: Binding(
                    get: { thread.selectedModel ?? "" },
                    set: { thread.selectedModel = $0 }
                ),
                thinkLevel: $thread.thinkLevel,
                isFocused: $isInputFocused,
                models: availableModels,
                droppedItems: $droppedItems
            )
            // The input's own horizontal padding lines its edges up with the message column.
            .frame(maxWidth: AppConstants.chatColumnWidth + 32)
        }
        .padding()
        // Covers the input too once it shows, so a drop over the text field lands here instead of typing in the file's path.
        .overlay {
            if isDropTargeted {
                DropOverlay()
            }
        }
        .onDrop(of: [.image, .fileURL], isTargeted: $isDropTargeted) { providers in
            droppedItems = providers
            return true
        }
        .onAppear(perform: ensureModelSelected)
        .onChange(of: availableModels) {
            ensureModelSelected()
        }
        // The view is replaced on thread switch, and the other two cover leaving the app and quitting it.
        .onDisappear(perform: saveDraft)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            saveDraft()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            saveDraft()
            try? context.save()
        }
        .focusedSceneValue(\.threadActions, ThreadActions(
            isStreaming: isStreaming,
            hasMessages: !messages.isEmpty,
            stop: { streamer.stop(thread) },
            focusInput: { isInputFocused = true },
            copyLastReply: copyLastReply,
            export: { exportDocument = MarkdownDocument(text: markdownTranscript()) }
        ))
        .fileExporter(
            isPresented: Binding(
                get: { exportDocument != nil },
                set: { if !$0 { exportDocument = nil } }
            ),
            document: exportDocument,
            contentType: MarkdownDocument.markdown,
            defaultFilename: exportFilename
        ) { result in
            if case .failure(let error) = result {
                print("Failed to export thread: \(error)")
            }
        }
    }

    private func messageList(_ messages: [ChatMessage], isStreaming: Bool) -> some View {
        let shownMessages = showsAllMessages ? messages : Array(messages.suffix(recentMessageLimit))

        return ScrollViewReader { proxy in
            ScrollView(.vertical) {
                // Eager rather than lazy, since lazy rows get estimated heights and scrollTo can then loop forever on replies taller than the window.
                VStack(alignment: .leading, spacing: 12) {
                    if let firstShown = shownMessages.first, shownMessages.count < messages.count {
                        Button("Show \(messages.count - shownMessages.count) Earlier Messages") {
                            showsAllMessages = true
                            // The earlier messages appear above, so this keeps the view in place instead of jumping to the start.
                            Task { @MainActor in
                                proxy.scrollTo(firstShown.id, anchor: .top)
                            }
                        }
                        .buttonStyle(.link)
                        .frame(maxWidth: .infinity)
                    }
                    ForEach(shownMessages) { message in
                        let isLast = message.id == messages.last?.id
                        ChatBubbleView(
                            message: message,
                            live: streamer.liveReply(for: message),
                            isStreaming: isStreaming && isLast,
                            canRetry: !isStreaming && isLast,
                            canEdit: !isStreaming && message.isUser,
                            onRetry: { retry(message) },
                            onEdit: { edit(message, text: $0) },
                            onFork: { fork(at: message) }
                        )
                        .id(message.id)
                    }
                    if let error = streamer.error(for: thread) {
                        ErrorRow(message: error) {
                            if let last = messages.last {
                                retry(last)
                            }
                        }
                    }
                    StreamFollower(reply: messages.last.flatMap(streamer.liveReply(for:)), isFollowing: isAtBottom) {
                        proxy.scrollTo(bottomId, anchor: nil)
                    }
                    .id(bottomId)
                    .onGeometryChange(for: Bool.self) { geometry in
                        guard let viewport = geometry.bounds(of: .named(scrollSpace)) else {
                            return true
                        }
                        // A little slack so being a few points short of the end still counts.
                        return geometry.frame(in: .named(scrollSpace)).minY <= viewport.height + 40
                    } action: { isVisible in
                        isAtBottom = isVisible
                    }
                }
                .frame(maxWidth: AppConstants.chatColumnWidth)
                .frame(maxWidth: .infinity)
                .padding([.horizontal, .top])
            }
            .coordinateSpace(.named(scrollSpace))
            .frame(maxHeight: .infinity)
            // Stays pinned to the end when the input grows, for example when images are attached or the window is resized.
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { _ in
                if isAtBottom {
                    proxy.scrollTo(bottomId, anchor: nil)
                }
            }
            .overlay {
                if messages.isEmpty {
                    Text("How can I help you today?")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .overlay(alignment: .bottom) {
                if !isAtBottom {
                    Button {
                        isAtBottom = true
                        proxy.scrollTo(bottomId, anchor: nil)
                    } label: {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 28, height: 28)
                            .background(.regularMaterial, in: Circle())
                            .overlay(Circle().stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .help("Scroll to bottom")
                    .padding(.bottom, 8)
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: isAtBottom)
            .onAppear {
                proxy.scrollTo(bottomId, anchor: nil)
            }
            // Deferred so the new message is laid out before scrolling to it.
            .onChange(of: messages.count) {
                isAtBottom = true
                Task { @MainActor in
                    proxy.scrollTo(bottomId, anchor: nil)
                }
            }
        }
    }

    private let recentMessageLimit = 10
    private let bottomId = "bottom"
    private let scrollSpace = "chatScroll"

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

    private func saveDraft() {
        let value = draft.isEmpty ? nil : draft
        if thread.draft != value {
            thread.draft = value
        }
    }

    private func insertChatMessage(text: String, images: [Data]) {
        if thread.modelContext == nil {
            thread.createdAt = Date()
            // A provisional title until the generated one arrives.
            let firstLine = text.components(separatedBy: .newlines).first ?? ""
            thread.title = firstLine.isEmpty ? "Image" : String(firstLine.prefix(60))
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
        thread.draft = nil
        // Autosave can lag behind, so save now to keep the message if the app quits mid-reply.
        try? context.save()

        streamer.send(thread, model: selectedModelInfo)
    }

    // Removes everything after the message, and the message itself if it's a reply, then asks again.
    private func retry(_ message: ChatMessage) {
        // Without a model the send fails, so keep the reply rather than deleting it for nothing.
        guard selectedModelInfo != nil else {
            streamer.send(thread, model: nil)
            return
        }
        removeMessages(after: message, including: !message.isUser)
        streamer.send(thread, model: selectedModelInfo)
    }

    private func edit(_ message: ChatMessage, text: String) {
        message.text = text
        removeMessages(after: message, including: false)
        try? context.save()
        streamer.send(thread, model: selectedModelInfo)
    }

    private func removeMessages(after message: ChatMessage, including: Bool) {
        let messages = thread.chronologicalMessages
        guard let index = messages.firstIndex(where: { $0.id == message.id }) else {
            return
        }
        for messageToRemove in messages[(including ? index : index + 1)...] {
            thread.messages.removeAll { $0.id == messageToRemove.id }
            context.delete(messageToRemove)
        }
    }

    // Copies the conversation up to and including the message into a new thread, to try a different direction.
    private func fork(at message: ChatMessage) {
        let messages = thread.chronologicalMessages
        guard let index = messages.firstIndex(where: { $0.id == message.id }) else {
            return
        }
        let newThread = ChatThread(timestamp: Date(), title: thread.title, hasReceivedFirstMessage: true, selectedModel: thread.selectedModel)
        newThread.thinkLevel = thread.thinkLevel
        newThread.updatedAt = Date()
        context.insert(newThread)
        for original in messages[...index] {
            let copy = ChatMessage(text: original.text, isUser: original.isUser, timestamp: original.createdAt, images: original.images)
            copy.thinking = original.thinking
            copy.tokensPerSecond = original.tokensPerSecond
            copy.contextUsage = original.contextUsage
            copy.thinkingSeconds = original.thinkingSeconds
            newThread.messages.append(copy)
        }
        try? context.save()
        onSelectThread(newThread)
    }

    private func copyLastReply() {
        guard let reply = thread.chronologicalMessages.last(where: { !$0.isUser && !$0.text.isEmpty }) else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(reply.text, forType: .string)
    }

    private var exportFilename: String {
        let name = thread.title.components(separatedBy: CharacterSet(charactersIn: "/:")).joined(separator: "-")
        return name.isEmpty ? "Chat" : name
    }

    private func markdownTranscript() -> String {
        var parts = ["# \(thread.title)"]
        for message in thread.chronologicalMessages {
            let imageNote = (message.images?.isEmpty ?? true) ? "" : "\n\n_\(message.images!.count) image(s) attached_"
            parts.append("## \(message.isUser ? "You" : "Assistant")\n\n\(message.text)\(imageNote)")
        }
        return parts.joined(separator: "\n\n")
    }
}

// Follows a streaming reply to the bottom, in its own view so the per-token text changes only re-render this, not the whole thread.
private struct StreamFollower: View {
    let reply: LiveReply?
    let isFollowing: Bool
    let scrollToBottom: () -> Void

    var body: some View {
        // UTF-8 counts are constant time, unlike counting characters.
        let length = (reply?.text.utf8.count ?? 0) + (reply?.thinking.utf8.count ?? 0)
        Color.clear
            .frame(height: 1)
            .onChange(of: length) {
                if isFollowing {
                    scrollToBottom()
                }
            }
    }
}

private struct DropOverlay: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6]))
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                Label("Drop images or text files", systemImage: "doc.badge.plus")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(8)
    }
}

private struct ErrorRow: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Retry", action: onRetry)
        }
        .padding(10)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct MarkdownDocument: FileDocument {
    static let markdown = UTType(filenameExtension: "md", conformingTo: .plainText) ?? .plainText
    static var readableContentTypes: [UTType] { [markdown] }

    let text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
