import SwiftUI

struct SettingsView: View {
    @AppStorage("ollamaBaseURL") private var ollamaBaseURL = AppConstants.ollamaDefaultBaseURL
    @AppStorage("titleSummaryPrompt") private var titleSummaryPrompt = AppConstants.titleSummaryPrompt
    @AppStorage("contextWindowLength") private var contextWindowLength = AppConstants.contextWindowLength
    @State private var contextWindowLengthString: String = ""
    
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
                    Text("Context Window Length")
                        .font(.headline)
                    
                    HStack {
                        TextField("Enter value", text: $contextWindowLengthString)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 100)
                            .onAppear {
                                contextWindowLengthString = "\(contextWindowLength)"
                            }
                        
                        Text("tokens")
                    }
                }
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("Thread Title Summary Prompt")
                        .font(.headline)
                    
                    ZStack {
                        TextEditor(text: $titleSummaryPrompt)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 6)
                            .lineSpacing(5)
                            .frame(minHeight: 100)
                    }
                    .scrollContentBackground(.hidden)
                    .background(Color.white)
                    .cornerRadius(6)
                }
                
                Button("Restore Defaults") {
                    ollamaBaseURL = AppConstants.ollamaDefaultBaseURL
                    titleSummaryPrompt = AppConstants.titleSummaryPrompt
                    contextWindowLength = AppConstants.contextWindowLength
                    contextWindowLengthString = "\(AppConstants.contextWindowLength)"
                }
            }
            .padding()
        }
        .onChange(of: contextWindowLengthString) { oldValue, newValue in
            if let value = Int(newValue) {
                contextWindowLength = value
            }
        }
        .frame(minWidth: 300, minHeight: 300)
    }
}

#Preview {
    SettingsView()
}
