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
            }
            
            ZStack(alignment: .bottom) {
                Markdown(message.text)
                    .padding(12)
                    .textSelection(.enabled)
                    .background(message.isUser ? Color.accentColor.opacity(0.2) : Color(NSColor.textBackgroundColor))
                    .cornerRadius(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                HStack() {
                    Button(action: copyText) {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .help("Copy")
                    .buttonStyle(PlainButtonStyle())
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(alignment: .leading)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(NSColor.textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
                    )
                    .offset(y: 16)
                    .opacity(isHovering ? 1 : 0)
                    .animation(.easeInOut(duration: 0.2), value: isHovering)
                    
                    Spacer()
                }
            }
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
