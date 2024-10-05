import SwiftUI
import SwiftData

struct ChatThreadView: View {
    @AppStorage("titleSummaryPrompt") private var titleSummaryPrompt = AppConstants.titleSummaryPrompt
    
    @Environment(\.modelContext) private var context
    @Bindable var thread: ChatThread
    @Binding var isDraft: Bool
    
    @FocusState private var isTextFieldFocused: Bool
    @State private var currentInputMessage: String = ""
    
    @State private var errorMessage: String?
    @State private var shouldShowErrorAlert = false
    
    @State private var scrollProxy: ScrollViewProxy?
    
    let availableModels: [String]
    
    var body: some View {
        VStack {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(chronologicalMessages) { message in
                            ChatBubbleView(message: message)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .frame(maxHeight: .infinity)
                .onChange(of: thread.messages.count) { oldValue, newValue in
                    scrollToBottom(proxy: proxy)
                }
                .onAppear {
                    scrollProxy = proxy
                    scrollToBottom(proxy: proxy)
                }
            }
            
            ChatInputView(
                currentInputMessage: $currentInputMessage,
                isTextFieldFocused: _isTextFieldFocused,
                isThinking: thread.isThinking,
                onSubmit: sendMessageStream,
                selectedModel: Binding(
                    get: { thread.selectedModel ?? "" },
                    set: { thread.selectedModel = $0 }
                ),
                modelOptions: availableModels
            )
        }
        .padding()
        .onAppear {
            focusTextField()
            ensureModelSelected()
        }
        .onChange(of: thread.id) { _, _ in
            focusTextField()
        }
        .alert("Error", isPresented: $shouldShowErrorAlert, actions: {
            Button("OK") {
                errorMessage = nil
            }
        }, message: {
            Text(errorMessage ?? "An unknown error occurred.")
        })
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let lastMessage = chronologicalMessages.last {
            withAnimation {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }
    
    private func focusTextField() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isTextFieldFocused = true
        }
    }
    
    private func ensureModelSelected() {
        if thread.selectedModel == nil || !availableModels.contains(thread.selectedModel!) {
            thread.selectedModel = availableModels.first
        }
    }
    
    private func sendMessageStream() {
        if currentInputMessage.isEmpty {
            return
        }
        
        if isDraft {
            convertDraftToRegularThread()
        }
        
        insertChatMessage(currentInputMessage, isUser: true)
        currentInputMessage = ""
        thread.isThinking = true
        
        Task {
            do {
                ensureModelSelected()
                guard let selectedModel = thread.selectedModel, !selectedModel.isEmpty else {
                    throw NSError(domain: "ChatView", code: 1, userInfo: [NSLocalizedDescriptionKey: "No model selected"])
                }
                
                let ollamaService = OllamaService()
                let ollamaMessages = chronologicalMessages.map { OllamaChatMessage(role: $0.isUser ? "user" : "assistant", content: $0.text) }
                let stream = ollamaService.streamConversation(model: selectedModel, messages: ollamaMessages)
                let assistantMessage = ChatMessage(text: "", isUser: false, timestamp: Date())
                
                await MainActor.run {
                    thread.messages.append(assistantMessage)
                    context.insert(assistantMessage)
                }
                
                for try await partialResponse in stream {
                    await MainActor.run {
                        assistantMessage.text += partialResponse
                        scrollProxy?.scrollTo(assistantMessage.id, anchor: .bottom)
                    }
                }
                
                await MainActor.run {
                    thread.isThinking = false
                    if !thread.hasReceivedFirstMessage {
                        thread.hasReceivedFirstMessage = true
                        setThreadTitle()
                    }
                    focusTextField()
                }
            } catch {
                await handleError(error)
            }
        }
    }
    
    private func convertDraftToRegularThread() {
        isDraft = false
        thread.createdAt = Date()
        context.insert(thread)
    }
    
    private func insertChatMessage(_ text: String, isUser: Bool) {
        let newMessage = ChatMessage(text: text, isUser: isUser, timestamp: Date())
        thread.messages.append(newMessage)
        context.insert(newMessage)
    }
    
    private func handleError(_ error: Error) async {
        await MainActor.run {
            shouldShowErrorAlert = true
            thread.isThinking = false
            
            let networkError = error as? URLError
            let defaultErrorMessage = "An unexpected error occurred while communicating with the Ollama API: \(error.localizedDescription)"
            
            if networkError == nil {
                errorMessage = defaultErrorMessage
            } else {
                switch networkError?.code {
                case .cannotConnectToHost:
                    errorMessage = "Unable to connect to the Ollama API. Please ensure that the Ollama server is running."
                case .timedOut:
                    errorMessage = "The request to Ollama API timed out. Please try again later."
                default:
                    errorMessage = defaultErrorMessage
                }
            }
        }
    }
    
    private func setThreadTitle() {
        Task {
            do {
                guard let selectedModel = thread.selectedModel, !selectedModel.isEmpty else {
                    throw NSError(domain: "ChatView", code: 1, userInfo: [NSLocalizedDescriptionKey: "No model selected"])
                }
                
                var ollamaMessages = chronologicalMessages.map { OllamaChatMessage(role: $0.isUser ? "user" : "assistant", content: $0.text) }
                ollamaMessages.append(OllamaChatMessage(role: "user", content: titleSummaryPrompt))
                
                let ollamaService = OllamaService()
                let summaryResponse = try await ollamaService.sendSingleMessage(model: selectedModel, messages: ollamaMessages)
                
                await MainActor.run {
                    setThreadTitle(summaryResponse)
                }
            } catch {
                print("Error summarizing thread: \(error.localizedDescription)")
            }
        }
    }
    
    private func setThreadTitle(_ summary: String) {
        thread.title = summary
        context.insert(thread)
    }
    
    private var chronologicalMessages: [ChatMessage] {
        thread.messages.sorted { $0.createdAt < $1.createdAt }
    }
}
