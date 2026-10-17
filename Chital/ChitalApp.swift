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
        }
        
        Settings {
            SettingsView()
        }
    }
}
