import SwiftUI

struct ChatInputView: View {
    @Binding var currentInputMessage: String
    @FocusState var isTextFieldFocused: Bool
    let isThinking: Bool
    let onSubmit: () -> Void
    
    @Binding var selectedModel: String
    let modelOptions: [String]
    
    var body: some View {
        VStack {
            HStack {
                Spacer()
                Picker(selection: $selectedModel, label: EmptyView()) {
                    ForEach(modelOptions, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .onChange(of: selectedModel) { _, _ in isTextFieldFocused = true }
                .buttonStyle(.borderless)
                .fixedSize()
                .disabled(modelOptions.isEmpty)
            }
            .padding(.trailing)
            HStack {
                TextField(isThinking ? "Thinking..." : "How can I help you today?", text: $currentInputMessage)
                    .textFieldStyle(PlainTextFieldStyle())
                    .padding(.horizontal, 15)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(20)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
                    )
                    .onSubmit(onSubmit)
                    .disabled(isThinking || modelOptions.isEmpty)
                    .focused($isTextFieldFocused)
            }
            .padding(.horizontal)
        }
    }
}
