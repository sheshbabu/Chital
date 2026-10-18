import SwiftUI
import SwiftData

@main
struct ChitalApp: App {
    @State private var streamer = ChatStreamer()
    
    var container: ModelContainer = {
        let schema = Schema([
            ChatThread.self,
            ChatMessage.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(streamer)
        }
        .defaultSize(width: 1000, height: 700)
        .modelContainer(container)
        .commands {
            CommandGroup(replacing: .saveItem) {}
            ChatCommands()
        }
        
        Settings {
            SettingsView()
        }
    }
}

// Actions published by the focused window, so the menu bar acts on its current thread.
struct ThreadActions {
    let isStreaming: Bool
    let hasMessages: Bool
    let stop: () -> Void
    let focusInput: () -> Void
    let copyLastReply: () -> Void
    let export: () -> Void
}

struct SidebarActions {
    let previousThread: () -> Void
    let nextThread: () -> Void
}

extension FocusedValues {
    @Entry var threadActions: ThreadActions?
    @Entry var sidebarActions: SidebarActions?
}

struct ChatCommands: Commands {
    @FocusedValue(\.threadActions) private var thread
    @FocusedValue(\.sidebarActions) private var sidebar

    var body: some Commands {
        CommandMenu("Chat") {
            Button("Focus Message Field") { thread?.focusInput() }
                .keyboardShortcut("l", modifiers: .command)
                .disabled(thread == nil)
            Button("Stop Generating") { thread?.stop() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(thread?.isStreaming != true)
            Button("Copy Last Reply") { thread?.copyLastReply() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(thread?.hasMessages != true)
            Button("Export as Markdown...") { thread?.export() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(thread?.hasMessages != true)
            Divider()
            Button("Previous Thread") { sidebar?.previousThread() }
                .keyboardShortcut("[", modifiers: [.command, .shift])
                .disabled(sidebar == nil)
            Button("Next Thread") { sidebar?.nextThread() }
                .keyboardShortcut("]", modifiers: [.command, .shift])
                .disabled(sidebar == nil)
        }
    }
}
