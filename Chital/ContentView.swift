import SwiftUI
import SwiftData

struct ContentView: View {
    @AppStorage("defaultModelName") private var defaultModelName = AppConstants.defaultModelName
    
    @Environment(\.modelContext) private var context
    @Query(sort: \ChatThread.createdAt, order: .reverse) private var threads: [ChatThread]
    
    @State private var selectedThreadId: ChatThread.ID?
    @State private var draftThread: ChatThread?
    
    @State private var availableModels: [String] = []
    @State private var isLoadingModels = true
    
    @State private var errorMessage: String?
    @State private var shouldShowErrorAlert = false
    
    var body: some View {
        NavigationSplitView {
            List(threads, selection: $selectedThreadId) { thread in
                NavigationLink(value: thread.id) {
                    Text(thread.title)
                        .contextMenu {
                            Button(action: { deleteThread(thread) }) {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            .toolbar {
                ToolbarItem {
                    Button(action: startNewThread) {
                        Label("New Thread", systemImage: "plus")
                    }
                    .keyboardShortcut("n", modifiers: .command)
                }
            }
        } detail: {
            if isLoadingModels {
                ProgressView("Loading models...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let selectedThread = threads.first(where: { $0.id == selectedThreadId })
                let threadToDisplay = selectedThread ?? draftThread ?? createNewThread()
                let isDraft = selectedThread == nil
                
                ChatThreadView(
                    thread: threadToDisplay,
                    isDraft: .constant(isDraft),
                    availableModels: availableModels
                )
                .navigationTitle(Text(threadToDisplay.title))
            }
        }
        .task {
            await fetchAvailableModels()
            if draftThread == nil {
                draftThread = createNewThread()
            }
        }
        .alert("Error", isPresented: $shouldShowErrorAlert, actions: {
            Button("OK") {
                errorMessage = nil
            }
        }, message: {
            Text(errorMessage ?? "An unknown error occurred.")
        })
    }
    
    private func createNewThread() -> ChatThread {
        let selectedModel = defaultModelName == "" ? availableModels.first : defaultModelName
        return ChatThread(timestamp: Date(), title: "New Conversation", selectedModel: selectedModel)
    }
    
    private func startNewThread() {
        let newThread = createNewThread()
        context.insert(newThread)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            selectedThreadId = newThread.id
        }
    }
    
    private func deleteThread(_ thread: ChatThread) {
        context.delete(thread)
        if selectedThreadId == thread.id {
            selectedThreadId = threads.first?.id
        }
    }
    
    private func fetchAvailableModels() async {
        let ollamaService = OllamaService()
        
        do {
            let modelNames = try await ollamaService.fetchModelList()
            await MainActor.run {
                availableModels = modelNames
                isLoadingModels = false
            }
        } catch {
            await handleError(error)
        }
    }
    
    private func handleError(_ error: Error) async {
        await MainActor.run {
            shouldShowErrorAlert = true
            
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
}
