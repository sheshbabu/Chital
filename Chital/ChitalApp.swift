import SwiftUI
import SwiftData

@main
struct ChitalApp: App {
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
        }
        .modelContainer(container)
        
        Settings {
            SettingsView()
        }
    }
}
