import SwiftUI
import MarkdownUI

struct ChatBubbleView: View {
    let message: ChatMessage
    let isThinking: Bool
    let onRetry: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(message.isUser ? "User" : "Assistant")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 2)
            }
            
            ZStack(alignment: .bottom) {
                Markdown(message.text != "" ? message.text : "..." )
                    .padding(12)
                    .textSelection(.enabled)
                    .background(message.isUser ? Color.accentColor.opacity(0.2) : Color(NSColor.textBackgroundColor))
                    .cornerRadius(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                if (message.text != "") {
                    HStack() {
                        HStack() {
                            ChatBubbleButton(title: "Copy", systemImage: "doc.on.doc", action: copyText)
                            if shouldShowRetryButton {
                                ChatBubbleButton(title: "Retry", systemImage: "arrow.counterclockwise", action: onRetry)
                            }
                        }
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .padding(.trailing, -4)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color(NSColor.textBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
                        )
                        .offset(y: 15)
                        .opacity(isHovering ? 1 : 0)
                        .animation(.easeInOut(duration: 0.2), value: isHovering)
                        
                        Spacer()
                    }
                }
            }
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }
    
    private var shouldShowRetryButton: Bool {
        return !message.isUser && !isThinking
    }
    
    private func copyText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.text, forType: .string)
    }
}

struct ChatBubbleButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
        }
        .buttonStyle(PlainButtonStyle())
        .help(title)
        .font(.caption)
        .padding(.trailing, 4)
    }
}

#Preview {
    VStack(spacing: 20) {
        ChatBubbleView(
            message: ChatMessage(
                text: "Hello!",
                isUser: true,
                timestamp: Date()
            ),
            isThinking: false,
            onRetry: {}
        )
        
        ChatBubbleView(
            message: ChatMessage(
                text: "Hello! How can I assist you today?",
                isUser: false,
                timestamp: Date()
            ),
            isThinking: false,
            onRetry: {}
        )
    }
    .padding()
    .frame(width: 400)
}
