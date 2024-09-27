import SwiftUI

struct SettingsView: View {
    @AppStorage("ollamaBaseURL") private var ollamaBaseURL = AppConstants.ollamaDefaultBaseURL
    @AppStorage("titleSummaryPrompt") private var titleSummaryPrompt = AppConstants.titleSummaryPrompt
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Ollama Base URL")
                        .font(.headline)
                    
                    TextField("Enter Ollama Base URL", text: $ollamaBaseURL)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("Thread Title Summary Prompt")
                        .font(.headline)
                    
                    TextEditor(text: $titleSummaryPrompt)
                        .frame(minHeight: 100)
                }
                
                Button("Restore Defaults") {
                    ollamaBaseURL = AppConstants.ollamaDefaultBaseURL
                    titleSummaryPrompt = AppConstants.titleSummaryPrompt
                }
            }
            .padding()
        }
        .frame(minWidth: 300, minHeight: 300)
    }
}
