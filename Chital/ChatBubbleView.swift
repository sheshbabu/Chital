import SwiftUI
import MarkdownUI
import ImageIO

struct ChatBubbleView: View {
    let message: ChatMessage
    // Set while the reply streams, and read instead of the message so only this bubble updates on each flush.
    let live: LiveReply?
    let isStreaming: Bool
    let canRetry: Bool
    let canEdit: Bool
    let onRetry: () -> Void
    let onEdit: (String) -> Void
    let onFork: () -> Void
    
    @AppStorage("fontSize") private var fontSize = AppConstants.defaultFontSize
    @State private var isHovering = false
    @State private var isThinkingExpanded = false
    @State private var editText: String?
    @State private var chunker = MarkdownChunker()
    @FocusState private var isEditorFocused: Bool

    private var text: String {
        live?.text ?? message.text
    }

    private var hasThinking: Bool {
        live?.hasThinking ?? !(message.thinking ?? "").isEmpty
    }
    
    var body: some View {
        VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
            if let editText {
                editor(editText)
            } else if message.isUser {
                userContent
            } else {
                assistantContent
            }
            
            // Always laid out so spacing doesn't jump while streaming, and revealed on hover except for a failed message's retry.
            let canShowActions = text != "" && !isStreaming && editText == nil
            HStack(spacing: 4) {
                CopyButton(text: message.text)
                if message.isUser && canEdit {
                    ChatBubbleButton(title: "Edit", systemImage: "pencil") {
                        editText = message.text
                    }
                }
                if !message.isUser {
                    ChatBubbleButton(title: "Branch into new thread", systemImage: "arrow.triangle.branch", action: onFork)
                }
                if canRetry {
                    ChatBubbleButton(title: "Retry", systemImage: "arrow.counterclockwise", action: onRetry)
                }
            }
            .foregroundStyle(.secondary)
            .opacity(canShowActions && (isHovering || (message.isUser && canRetry)) ? 1 : 0)
            .allowsHitTesting(canShowActions)
            .animation(.easeInOut(duration: 0.2), value: isHovering)
        }
        .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
        .onHover { hovering in
            isHovering = hovering
        }
    }
    
    // Editing a message replaces it and drops everything after it, then asks again.
    private func editor(_ text: String) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            TextField("", text: Binding(get: { text }, set: { editText = $0 }), axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: fontSize))
                .lineLimit(1...12)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.primary.opacity(0.08))
                .clipShape(.rect(cornerRadius: 18, style: .continuous))
                .focused($isEditorFocused)
                // Focusing in the same update that inserts the field is ignored on macOS, so it waits a turn.
                .task { isEditorFocused = true }
                .onSubmit(submitEdit)
                .onExitCommand { editText = nil }
            HStack {
                Button("Cancel") { editText = nil }
                Button("Send", action: submitEdit)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (message.images ?? []).isEmpty)
            }
            .controlSize(.small)
        }
        .padding(.leading, minimumBubbleInset)
    }

    private func submitEdit() {
        guard let text = editText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty || !(message.images ?? []).isEmpty else {
            return
        }
        editText = nil
        onEdit(text)
    }

    private var userContent: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if let images = message.images, !images.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Spacer(minLength: minimumBubbleInset)
                    ForEach(images.indices, id: \.self) { index in
                        MessageImage(data: images[index], cacheKey: "\(message.id)-\(index)")
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
            if hasThinking {
                // A plain button instead of DisclosureGroup, which on macOS only toggles from its small triangle.
                Button(action: { isThinkingExpanded.toggle() }) {
                    HStack(spacing: 4) {
                        Image(systemName: isThinkingExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: fontSize - 4))
                        Text(isStreaming && text.isEmpty ? "Thinking..." : "Thoughts")
                            .font(.system(size: fontSize - 1))
                    }
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                if isThinkingExpanded {
                    ThinkingText(message: message, live: live, fontSize: fontSize)
                }
            }
            
            if !text.isEmpty {
                // Separate Markdown views per top-level block group, so a streaming reply only re-renders its last part.
                let chunks = chunker.chunks(for: text)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(chunks.indices, id: \.self) { index in
                        MarkdownChunk(text: chunks[index])
                            .equatable()
                            .padding(.top, index == 0 ? 0 : Self.chunkSpacing(after: chunks[index - 1], before: chunks[index]) * fontSize)
                    }
                }
                .markdownTheme(Self.markdownTheme)
                .markdownTextStyle {
                    FontSize(fontSize)
                }
                .textSelection(.enabled)
            } else if !hasThinking {
                Text("...")
                    .font(.system(size: fontSize))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // Keeps user bubbles from spanning the whole column, so the two sides stay distinct.
    private let minimumBubbleInset: CGFloat = 80

    // Built once, because styles created in body are new closures on every update, which changes the environment and re-renders every finished chunk.
    // Wide code and tables scroll sideways instead of being squeezed or cut off.
    private static let markdownTheme = Theme.basic
        .codeBlock { configuration in
            CodeBlock(configuration: configuration)
                .markdownMargin(top: .zero, bottom: .em(1))
        }
        .table { configuration in
            ScrollView(.horizontal) {
                configuration.label
                    .fixedSize(horizontal: false, vertical: true)
            }
            .markdownMargin(top: .zero, bottom: .em(1))
        }
    
    // Mirrors MarkdownUI's spacing in ems, which keeps the larger of the previous block's bottom margin and the next block's top margin.
    // Every block ends with a 1em margin except a thematic break, which has 2em on both sides, and headings start with 1.5em.
    private static func chunkSpacing(after previous: String, before chunk: String) -> CGFloat {
        if isThematicBreak(previous) || isThematicBreak(chunk) {
            return 2
        }
        let hashes = chunk.prefix { $0 == "#" }.count
        return (1...6).contains(hashes) && isEndOrWhitespace(chunk.dropFirst(hashes).first) ? 1.5 : 1
    }

    private static func isThematicBreak(_ chunk: String) -> Bool {
        // A break is a few characters, so longer chunks are skipped without scanning them.
        guard chunk.utf8.count < 40 else {
            return false
        }
        let marks = chunk.filter { !$0.isWhitespace }
        guard let mark = marks.first, "-*_".contains(mark) else {
            return false
        }
        return marks.count >= 3 && marks.allSatisfy { $0 == mark }
    }

}

// Reads the thinking in its own view, so only an expanded section updates as it streams.
private struct ThinkingText: View {
    let message: ChatMessage
    let live: LiveReply?
    let fontSize: Double

    var body: some View {
        // A quote-style rule sets the reasoning apart from the answer below it.
        // Apple's inline Markdown parser is much faster than MarkdownUI for long reasoning, and keeps line breaks for lists.
        Text(Self.inlineMarkdown(live?.thinking ?? message.thinking ?? ""))
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

    private static func inlineMarkdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

private struct CodeBlock: View {
    let configuration: CodeBlockConfiguration

    @State private var isHovering = false

    var body: some View {
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
        .clipShape(.rect(cornerRadius: 6))
        .overlay(alignment: .topTrailing) {
            CopyButton(text: configuration.content)
                .foregroundStyle(.secondary)
                .background(.regularMaterial, in: .rect(cornerRadius: 6))
                .padding(4)
                .opacity(isHovering ? 1 : 0)
        }
        .onHover { isHovering = $0 }
    }
}

// Decodes a downscaled copy off the main thread once, since full-size images are slow to decode and the bubble only shows 150pt.
private struct MessageImage: View {
    let data: Data
    let cacheKey: String

    @State private var image: NSImage?

    private static let cache = NSCache<NSString, NSImage>()

    var body: some View {
        Group {
            if let image = image ?? Self.cache.object(forKey: cacheKey as NSString) {
                // Rounded before framing so the corners follow the image, and trailing so tall images sit flush right.
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(.rect(cornerRadius: 8))
                    .frame(maxWidth: 150, maxHeight: 150, alignment: .trailing)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 150, height: 150)
            }
        }
        .task(id: cacheKey) {
            guard Self.cache.object(forKey: cacheKey as NSString) == nil else {
                return
            }
            let data = data
            let thumbnail = await Task.detached(priority: .userInitiated) {
                Self.thumbnail(from: data)
            }.value
            if let thumbnail {
                Self.cache.setObject(thumbnail, forKey: cacheKey as NSString)
                image = thumbnail
            }
        }
    }

    // Twice the display size keeps it sharp on Retina screens.
    nonisolated private static func thumbnail(from data: Data) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 300
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: image, size: NSSize(width: image.width / 2, height: image.height / 2))
    }
}

// Splits a reply at blank lines that start a new top-level block outside code fences.
// Lines that continue a list (indented, or another list item) are never split from it, so lists keep their numbering and nesting.
// Finished chunks are kept, so each streaming update only scans the lines added since the last one.
private final class MarkdownChunker {
    private var finishedChunks: [String] = []
    // UTF-8 offsets of where the unfinished chunk starts and where the next unscanned line starts.
    private var chunkStart = 0
    private var scanned = 0
    // The open fence's character and length, since only a matching fence at least as long closes it.
    private var fence: (character: Character, length: Int)?
    private var isPreviousBlank = false

    func chunks(for text: String) -> [String] {
        // A reply only grows in place while streaming, so shorter text means a different reply and starts over.
        if text.utf8.count < scanned {
            finishedChunks = []
            chunkStart = 0
            scanned = 0
            fence = nil
            isPreviousBlank = false
        }

        let utf8 = text.utf8
        var lineStart = utf8.index(utf8.startIndex, offsetBy: scanned)
        // Only complete lines are scanned, since a partial line can't be classified yet.
        while let newline = utf8[lineStart...].firstIndex(of: UInt8(ascii: "\n")) {
            let line = text[lineStart..<newline]
            let isBlank = line.allSatisfy(\.isWhitespace)
            if fence == nil && isPreviousBlank && !isBlank && scanned > chunkStart && Self.startsTopLevelBlock(line) {
                finishedChunks.append(String(text[utf8.index(utf8.startIndex, offsetBy: chunkStart)..<lineStart]))
                chunkStart = scanned
            }
            updateFence(with: line)
            isPreviousBlank = isBlank
            lineStart = utf8.index(after: newline)
            scanned = utf8.distance(from: utf8.startIndex, to: lineStart)
        }

        let unfinished = String(text[utf8.index(utf8.startIndex, offsetBy: chunkStart)...])
        return unfinished.isEmpty ? finishedChunks : finishedChunks + [unfinished]
    }

    private func updateFence(with line: Substring) {
        let trimmed = line.drop { $0 == " " || $0 == "\t" }
        guard let marker = trimmed.first, marker == "`" || marker == "~" else {
            return
        }
        let length = trimmed.prefix { $0 == marker }.count
        guard length >= 3 else {
            return
        }
        if fence == nil {
            fence = (marker, length)
        } else if let open = fence, open.character == marker, length >= open.length, trimmed.dropFirst(length).allSatisfy(\.isWhitespace) {
            fence = nil
        }
    }

    private static func startsTopLevelBlock(_ line: Substring) -> Bool {
        guard let first = line.first, first != " ", first != "\t" else {
            return false
        }
        if "-*+".contains(first) {
            return !isEndOrWhitespace(line.dropFirst().first)
        }
        let digits = line.prefix { $0.isASCII && $0.isNumber }.count
        if (1...9).contains(digits), let marker = line.dropFirst(digits).first, marker == "." || marker == ")" {
            return !isEndOrWhitespace(line.dropFirst(digits + 1).first)
        }
        return true
    }
}

// Plain character checks rather than Regex, since these run on every line of a reply.
private func isEndOrWhitespace(_ character: Character?) -> Bool {
    character.map(\.isWhitespace) ?? true
}

private struct MarkdownChunk: View, Equatable {
    let text: String

    var body: some View {
        Markdown(text)
    }
}

// Shows a checkmark for a moment so it's clear the copy happened.
struct CopyButton: View {
    let text: String

    @State private var didCopy = false

    var body: some View {
        ChatBubbleButton(title: didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            didCopy = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                didCopy = false
            }
        }
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
            live: nil,
            isStreaming: false,
            canRetry: true,
            canEdit: true,
            onRetry: {},
            onEdit: { _ in },
            onFork: {}
        )
        
        ChatBubbleView(
            message: ChatMessage(
                text: "Hello! How can I assist you today?",
                isUser: false,
                timestamp: Date()
            ),
            live: nil,
            isStreaming: false,
            canRetry: true,
            canEdit: false,
            onRetry: {},
            onEdit: { _ in },
            onFork: {}
        )
    }
    .padding()
    .frame(width: 400)
}
