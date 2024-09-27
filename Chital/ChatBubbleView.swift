import SwiftUI
import MarkdownUI

struct ChatBubbleView: View {
    let message: ChatMessage
    @State private var isHovering = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(message.isUser ? "User" : "Assistant")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 2)
                
                Button(action: copyText) {
                    Image(systemName: "doc.on.doc")
                }
                .help("Copy")
                .buttonStyle(PlainButtonStyle())
                .font(.caption)
                .foregroundColor(.secondary)
                .opacity(isHovering ? 1 : 0)
                .offset(x: isHovering ? 0 : -10)
                .animation(.easeInOut(duration: 0.2), value: isHovering)
                
            }
            
            Markdown(message.text)
                .padding(12)
                .textSelection(.enabled)
                .background(message.isUser ? Color.accentColor.opacity(0.2) : Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }
    
    private func copyText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.text, forType: .string)
    }
}
