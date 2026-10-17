import SwiftUI

struct SettingsView: View {
    @AppStorage("ollamaBaseURL") private var ollamaBaseURL = AppConstants.ollamaDefaultBaseURL
    @AppStorage("titleSummaryPrompt") private var titleSummaryPrompt = AppConstants.titleSummaryPrompt

    @AppStorage("contextLength") private var contextLength = AppConstants.contextLength
    @State private var contextLengthString: String = ""

    @AppStorage("defaultModelName") private var defaultModelName = AppConstants.defaultModelName
    @State private var availableModels: [String] = []
    @State private var modelsErrorMessage: String?

    @AppStorage("fontSize") private var fontSize = AppConstants.defaultFontSize

    var body: some View {
        Form {
            Section {
                TextField("Server URL", text: $ollamaBaseURL, prompt: Text(AppConstants.ollamaDefaultBaseURL))

                Picker("Default model", selection: $defaultModelName) {
                    Text("First available").tag("")
                    ForEach(availableModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }

                TextField("Context length", text: $contextLengthString, prompt: Text("Ollama default"))
                    .onAppear {
                        contextLengthString = contextLength > 0 ? "\(contextLength)" : ""
                    }
            } header: {
                Text("Ollama")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if let modelsErrorMessage {
                        Label(modelsErrorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                    Text("Context length is in tokens. Leave it empty to let Ollama choose based on available memory.")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Lines up with the section headers rather than the box edge.
                .padding(.leading, 12)
            }

            Section("Appearance") {
                Slider(value: $fontSize, in: 10...24, step: 1) {
                    Text("Font size")
                } minimumValueLabel: {
                    Text("A").font(.system(size: 10))
                } maximumValueLabel: {
                    Text("A").font(.system(size: 16))
                }

                Text("The quick brown fox jumps over the lazy dog.")
                    .font(.system(size: fontSize))
                    .foregroundStyle(.secondary)
            }

            Section {
                TextEditor(text: $titleSummaryPrompt)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 140)
            } header: {
                Text("Thread titles")
            } footer: {
                Text("Sent to the model after the first reply to name the thread.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Lines up with the section headers rather than the box edge.
                    .padding(.leading, 12)
            }

            Section {
                HStack {
                    Spacer()
                    Button("Restore Defaults") {
                        ollamaBaseURL = AppConstants.ollamaDefaultBaseURL
                        titleSummaryPrompt = AppConstants.titleSummaryPrompt
                        contextLength = AppConstants.contextLength
                        contextLengthString = ""
                        defaultModelName = AppConstants.defaultModelName
                        fontSize = AppConstants.defaultFontSize
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: contextLengthString) { oldValue, newValue in
            let value = Int(newValue.trimmingCharacters(in: .whitespaces)) ?? 0
            contextLength = max(value, 0)
        }
        // Refetches when the URL changes, after a short pause so typing doesn't send a request per keystroke.
        .task(id: ollamaBaseURL) {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else {
                return
            }
            await fetchAvailableModels()
        }
        .frame(minWidth: 500, maxWidth: 700, minHeight: 500, maxHeight: 800)
    }

    private func fetchAvailableModels() async {
        do {
            availableModels = try await OllamaService().fetchModels().map { $0.name }
            modelsErrorMessage = nil
        } catch {
            availableModels = []
            modelsErrorMessage = ollamaErrorMessage(error)
        }
    }
}

#Preview {
    SettingsView()
}
