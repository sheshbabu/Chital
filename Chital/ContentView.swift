import SwiftUI
import SwiftData

struct ContentView: View {
    @AppStorage("defaultModelName") private var defaultModelName = AppConstants.defaultModelName

    @Environment(\.modelContext) private var context
    @Environment(ChatStreamer.self) private var streamer
    @Query(sort: \ChatThread.createdAt, order: .reverse) private var threads: [ChatThread]

    @State private var selectedThreadId: ChatThread.ID?
    // Kept out of the database until its first message, so empty chats never show up in the sidebar.
    @State private var draftThread = ChatThread(timestamp: Date(), title: "New Conversation")

    @State private var availableModels: [OllamaModelInfo] = []
    @State private var hasLoadedModels = false
    @State private var modelsErrorMessage: String?

    @State private var isShowingDeleteAllConfirmation = false

    var body: some View {
        // Read here rather than inside the alert's closures so SwiftUI observes changes to it.
        let errorMessage = streamer.errorMessage
        
        NavigationSplitView {
            List(threads, selection: $selectedThreadId) { thread in
                NavigationLink(value: thread.id) {
                    ThreadRow(title: thread.title)
                        .contextMenu {
                            Button(action: { deleteThread(thread) }) {
                                Label("Delete", systemImage: "trash")
                            }
                            Divider()
                            Button(action: { isShowingDeleteAllConfirmation = true }) {
                                Label("Delete All Threads...", systemImage: "trash.fill")
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
            .alert("Delete All Threads", isPresented: $isShowingDeleteAllConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive, action: deleteAllThreads)
            } message: {
                Text("Are you sure you want to delete all threads?")
            }
        } detail: {
            if let modelsErrorMessage, !hasLoadedModels {
                ContentUnavailableView {
                    Label("Can't Load Models", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(modelsErrorMessage)
                } actions: {
                    Button("Retry") {
                        Task { await fetchAvailableModels() }
                    }
                }
            } else if !hasLoadedModels {
                ProgressView("Loading models...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let thread = threads.first(where: { $0.id == selectedThreadId }) ?? draftThread

                ChatThreadView(
                    thread: thread,
                    availableModels: availableModels,
                    onFirstMessage: { selectedThreadId = thread.id }
                )
                .id(thread.id)
                .navigationTitle(Text(thread.title))
            }
        }
        .task {
            await fetchAvailableModels()
        }
        // Picks up models pulled or removed while the app was in the background.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await fetchAvailableModels() }
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { streamer.errorMessage = nil } }
        ), actions: {
            Button("OK") {
                streamer.errorMessage = nil
            }
        }, message: {
            Text(errorMessage ?? "An unknown error occurred.")
        })
    }

    private func startNewThread() {
        selectedThreadId = nil
        if draftThread.modelContext != nil {
            draftThread = ChatThread(timestamp: Date(), title: "New Conversation")
        }
    }

    private func deleteThread(_ thread: ChatThread) {
        streamer.stop(thread)
        if selectedThreadId == thread.id {
            // Select the neighbouring thread, since the query won't reflect the deletion until the next update.
            let remaining = threads.filter { $0.id != thread.id }
            let index = threads.firstIndex(where: { $0.id == thread.id }) ?? 0
            selectedThreadId = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id
        }
        if thread.id == draftThread.id {
            draftThread = ChatThread(timestamp: Date(), title: "New Conversation")
        }
        context.delete(thread)
    }

    private func deleteAllThreads() {
        streamer.stopAll()
        selectedThreadId = nil
        draftThread = ChatThread(timestamp: Date(), title: "New Conversation")
        for thread in threads {
            context.delete(thread)
        }
    }

    private func fetchAvailableModels() async {
        do {
            availableModels = try await OllamaService().fetchModels()
            hasLoadedModels = true
            modelsErrorMessage = nil
        } catch {
            // After a successful load, keep the last known models so a brief outage doesn't blank the window.
            if !hasLoadedModels {
                modelsErrorMessage = ollamaErrorMessage(error)
            }
        }
    }
}

// Shows a title's leading emoji in a fixed icon column so titles line up, with a placeholder icon when there is none.
struct ThreadRow: View {
    let title: String
    
    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let emoji = leadingEmoji {
                    Text(emoji)
                } else {
                    Image(systemName: "bubble.left")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 20)
            
            Text(leadingEmoji.map { String(title.dropFirst($0.count)).trimmingCharacters(in: .whitespaces) } ?? title)
                .lineLimit(1)
        }
    }
    
    private var leadingEmoji: String? {
        guard let first = title.first, let scalar = first.unicodeScalars.first else {
            return nil
        }
        // Digits and symbols like # count as emoji scalars, so require emoji presentation or a multi-scalar emoji.
        let isEmoji = scalar.properties.isEmojiPresentation || (scalar.properties.isEmoji && first.unicodeScalars.count > 1)
        return isEmoji ? String(first) : nil
    }
}
