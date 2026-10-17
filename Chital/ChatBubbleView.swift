import SwiftUI
import MarkdownUI

struct ChatBubbleView: View {
    let message: ChatMessage
    let isStreaming: Bool
    let canRetry: Bool
    let onRetry: () -> Void
    
    @AppStorage("fontSize") private var fontSize = AppConstants.defaultFontSize
    @State private var isHovering = false
    @State private var isThinkingExpanded = false
    
    var body: some View {
        VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
            if message.isUser {
                userContent
            } else {
                assistantContent
            }
            
            // Always laid out so spacing doesn't jump while streaming, and revealed on hover except for a failed message's retry.
            let canShowActions = message.text != "" && !isStreaming
            HStack(spacing: 4) {
                ChatBubbleButton(title: "Copy", systemImage: "doc.on.doc", action: copyText)
                if canRetry {
                    ChatBubbleButton(title: "Retry", systemImage: "arrow.counterclockwise", action: onRetry)
                }
            }
            .foregroundColor(.secondary)
            .opacity(canShowActions && (isHovering || (message.isUser && canRetry)) ? 1 : 0)
            .allowsHitTesting(canShowActions)
            .animation(.easeInOut(duration: 0.2), value: isHovering)
        }
        .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
        .onHover { hovering in
            isHovering = hovering
        }
    }
    
    private var userContent: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if let images = message.images, !images.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Spacer(minLength: minimumBubbleInset)
                    ForEach(Array(images.enumerated()), id: \.offset) { index, imageData in
                        if let nsImage = NSImage(data: imageData) {
                            // Rounded before framing so the corners follow the image, and trailing so tall images sit flush right.
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .frame(maxWidth: 150, maxHeight: 150, alignment: .trailing)
                        }
                    }
                }
            }
            
            if !message.text.isEmpty {
                HStack(spacing: 0) {
                    Spacer(minLength: minimumBubbleInset)
                    // Neutral rather than coloured, as in ChatGPT and Claude, so it works in both light and dark mode.
                    Text(message.text)
                        .font(.system(size: fontSize))
                        .textSelection(.enabled)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.primary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
        }
    }
    
    // Replies are plain text across the full column so code blocks and tables have room.
    private var assistantContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let thinking = message.thinking, !thinking.isEmpty {
                // A plain button instead of DisclosureGroup, which on macOS only toggles from its small triangle.
                Button(action: { isThinkingExpanded.toggle() }) {
                    HStack(spacing: 4) {
                        Image(systemName: isThinkingExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: fontSize - 4))
                        Text(isStreaming && message.text.isEmpty ? "Thinking..." : "Thoughts")
                            .font(.system(size: fontSize - 1))
                    }
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                if isThinkingExpanded {
                    // A quote-style rule sets the reasoning apart from the answer below it.
                    // Apple's inline Markdown parser is much faster than MarkdownUI for long reasoning, and keeps line breaks for lists.
                    Text(Self.inlineMarkdown(thinking))
                        .font(.system(size: fontSize - 1))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(.leading, 10)
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.4))
                                .frame(width: 2)
                        }
                }
            }
            
            if !message.text.isEmpty {
                Markdown(message.text)
                    .markdownTextStyle {
                        FontSize(fontSize)
                    }
                    // Wide code and tables scroll sideways instead of being squeezed or cut off.
                    .markdownBlockStyle(\.codeBlock) { configuration in
                        ScrollView(.horizontal) {
                            configuration.label
                                .fixedSize(horizontal: false, vertical: true)
                                .relativeLineSpacing(.em(0.15))
                                .markdownTextStyle {
                                    FontFamilyVariant(.monospaced)
                                    FontSize(.em(0.94))
                                }
                                .padding(10)
                        }
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .markdownMargin(top: .zero, bottom: .em(1))
                    }
                    .markdownBlockStyle(\.table) { configuration in
                        ScrollView(.horizontal) {
                            configuration.label
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .markdownMargin(top: .zero, bottom: .em(1))
                    }
                    .textSelection(.enabled)
            } else if message.thinking == nil {
                Text("...")
                    .font(.system(size: fontSize))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // Keeps user bubbles from spanning the whole column, so the two sides stay distinct.
    private let minimumBubbleInset: CGFloat = 80
    
    private static func inlineMarkdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
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
        .font(.system(size: 13))
        .padding(4)
        .contentShape(Rectangle())
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
            isStreaming: false,
            canRetry: true,
            onRetry: {}
        )
        
        ChatBubbleView(
            message: ChatMessage(
                text: "Hello! How can I assist you today?",
                isUser: false,
                timestamp: Date()
            ),
            isStreaming: false,
            canRetry: true,
            onRetry: {}
        )
    }
    .padding()
    .frame(width: 400)
}
