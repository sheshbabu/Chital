import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var selectedThread: ChatThread?
    // Kept out of the database until its first message, so empty chats never show up in the sidebar.
    @State private var draftThread = ChatThread(timestamp: Date(), title: "New Conversation")

    @State private var availableModels: [OllamaModelInfo] = []
    @State private var hasLoadedModels = false
    @State private var modelsErrorMessage: String?

    var body: some View {
        NavigationSplitView {
            ThreadSidebar(selection: $selectedThread, draftThread: $draftThread)
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
                let thread = selectedThread ?? draftThread

                ChatThreadView(
                    thread: thread,
                    availableModels: availableModels,
                    onFirstMessage: { selectedThread = thread },
                    onSelectThread: { selectedThread = $0 }
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

// Owns the threads query, which updates on every change to any model.
// Keeping it here means those updates re-run only the sidebar, not the whole window and the open thread.
struct ThreadSidebar: View {
    @Binding var selection: ChatThread?
    @Binding var draftThread: ChatThread

    @Environment(\.modelContext) private var context
    @Environment(ChatStreamer.self) private var streamer
    @Query private var storedThreads: [ChatThread]

    @State private var isShowingDeleteAllConfirmation = false
    @State private var searchText = ""
    // Matched in a task rather than in body, so a reply streaming in doesn't re-run the search on every update.
    @State private var searchMatches: Set<ChatThread.ID>?
    @State private var renamingThread: ChatThread?
    @State private var renameText = ""

    // Sorted in memory, since sorting the query by the optional updatedAt made it far slower while streaming.
    // Threads saved before activity was tracked have no updatedAt, so they sort after active ones by creation date.
    private var threads: [ChatThread] {
        storedThreads.sorted { ($0.updatedAt ?? .distantPast, $0.createdAt) > ($1.updatedAt ?? .distantPast, $1.createdAt) }
    }

    var body: some View {
        let threads = threads
        let visibleThreads = searchMatches.map { matches in threads.filter { matches.contains($0.id) } } ?? threads

        List(visibleThreads, selection: $selection) { thread in
            NavigationLink(value: thread) {
                ThreadRow(title: thread.title)
                    .contextMenu {
                        Button(action: { startRenaming(thread) }) {
                            Label("Rename...", systemImage: "pencil")
                        }
                        Button(action: { deleteThread(thread, in: threads) }) {
                            Label("Delete", systemImage: "trash")
                        }
                        Divider()
                        Button(action: { isShowingDeleteAllConfirmation = true }) {
                            Label("Delete All Threads...", systemImage: "trash.fill")
                        }
                    }
            }
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search")
        .task(id: searchText) {
            let query = searchText.trimmingCharacters(in: .whitespaces)
            guard !query.isEmpty else {
                searchMatches = nil
                return
            }
            // A short pause so typing doesn't search every message on each keystroke.
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else {
                return
            }
            let matches = storedThreads.filter { thread in
                thread.title.localizedStandardContains(query) || thread.messages.contains { $0.text.localizedStandardContains(query) }
            }
            searchMatches = Set(matches.map(\.id))
        }
        .overlay {
            if visibleThreads.isEmpty && !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 220)
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
            Button("Delete", role: .destructive) { deleteAllThreads(threads) }
        } message: {
            Text("Are you sure you want to delete all threads?")
        }
        .alert("Rename Thread", isPresented: Binding(
            get: { renamingThread != nil },
            set: { if !$0 { renamingThread = nil } }
        )) {
            TextField("Title", text: $renameText)
            Button("Cancel", role: .cancel) { }
            Button("Rename", action: finishRenaming)
        }
        .focusedSceneValue(\.sidebarActions, SidebarActions(
            previousThread: { selectAdjacentThread(in: visibleThreads, offset: -1) },
            nextThread: { selectAdjacentThread(in: visibleThreads, offset: 1) }
        ))
    }

    private func selectAdjacentThread(in list: [ChatThread], offset: Int) {
        guard !list.isEmpty else {
            return
        }
        // From a new unsent chat, either direction starts at the top.
        guard let index = list.firstIndex(where: { $0.id == selection?.id }) else {
            selection = list.first
            return
        }
        selection = list[min(max(index + offset, 0), list.count - 1)]
    }

    private func startRenaming(_ thread: ChatThread) {
        renameText = thread.title
        renamingThread = thread
    }

    private func finishRenaming() {
        let title = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let thread = renamingThread, !title.isEmpty {
            thread.title = title
            // Keeps a generated title from replacing the user's own.
            thread.hasReceivedFirstMessage = true
        }
        renamingThread = nil
    }

    private func startNewThread() {
        selection = nil
        if draftThread.modelContext != nil {
            draftThread = ChatThread(timestamp: Date(), title: "New Conversation")
        }
    }

    private func deleteThread(_ thread: ChatThread, in threads: [ChatThread]) {
        streamer.stop(thread)
        if selection?.id == thread.id {
            // Select the neighbouring thread, since the query won't reflect the deletion until the next update.
            let remaining = threads.filter { $0.id != thread.id }
            let index = threads.firstIndex(where: { $0.id == thread.id }) ?? 0
            selection = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)]
        }
        if thread.id == draftThread.id {
            draftThread = ChatThread(timestamp: Date(), title: "New Conversation")
        }
        context.delete(thread)
    }

    private func deleteAllThreads(_ threads: [ChatThread]) {
        streamer.stopAll()
        selection = nil
        draftThread = ChatThread(timestamp: Date(), title: "New Conversation")
        for thread in threads {
            context.delete(thread)
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
