import SwiftUI
import ImageIO
import QuickLook
import UniformTypeIdentifiers

struct ImageAttachment: Identifiable {
    let id = UUID()
    let data: Data
    let thumbnail: NSImage
}

struct ChatInputView: View {
    let isStreaming: Bool
    let onSubmit: (String, [Data]) -> Void
    let onStop: () -> Void

    @Binding var text: String
    @Binding var selectedModel: String
    @Binding var thinkLevel: String?
    var isFocused: FocusState<Bool>.Binding
    let models: [OllamaModelInfo]
    // Dropped on the whole chat pane, since the text field would take file drops itself and type in their paths.
    @Binding var droppedItems: [NSItemProvider]

    @State private var attachments: [ImageAttachment] = []
    @State private var showImagePicker = false
    // A count rather than a flag, since a second batch can start before the first one finishes.
    @State private var processingImageBatches = 0
    @State private var pasteMonitor: Any?
    // Mirrored into state because the paste monitor's closure keeps the view as it was when installed, and state reads stay live.
    @State private var canPasteImages = false
    @State private var inputWindow: NSWindow?
    @State private var previewURL: URL?

    @AppStorage("fontSize") private var fontSize = AppConstants.defaultFontSize

    private var selectedModelInfo: OllamaModelInfo? {
        models.first { $0.name == selectedModel }
    }

    private var canAttachImages: Bool {
        selectedModelInfo?.supportsImages ?? false
    }

    private var isProcessingImages: Bool {
        processingImageBatches > 0
    }

    private var canSubmit: Bool {
        !isStreaming && !isProcessingImages && !models.isEmpty
            && (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty)
    }

    var body: some View {
        VStack {
            HStack {
                Spacer()
                if let levels = selectedModelInfo?.thinkLevels, !levels.isEmpty {
                    Picker(selection: $thinkLevel, label: EmptyView()) {
                        Text("Default thinking").tag(String?.none)
                        ForEach(levels, id: \.self) { level in
                            Text(thinkLevelLabel(level)).tag(String?.some(level))
                        }
                    }
                    .buttonStyle(.borderless)
                    .fixedSize()
                    .help("Thinking")
                }
                Picker(selection: $selectedModel, label: EmptyView()) {
                    ForEach(models, id: \.name) { model in
                        Text(model.name).tag(model.name)
                    }
                }
                .onChange(of: selectedModel) {
                    // A level the new model doesn't offer would leave the thinking picker blank.
                    if let level = thinkLevel, !(selectedModelInfo?.thinkLevels.contains(level) ?? false) {
                        thinkLevel = nil
                    }
                    isFocused.wrappedValue = true
                }
                .buttonStyle(.borderless)
                .fixedSize()
                .disabled(models.isEmpty)
            }
            .padding(.trailing)
            .padding(.bottom, 6)

            if !attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(attachments) { attachment in
                            ZStack(alignment: .topTrailing) {
                                Image(nsImage: attachment.thumbnail)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 60, height: 60)
                                    .clipShape(.rect(cornerRadius: 8))
                                    .onTapGesture {
                                        previewURL = quickLookFile(for: attachment.data, name: attachment.id.uuidString)
                                    }

                                Button(action: {
                                    attachments.removeAll { $0.id == attachment.id }
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.white)
                                        .background(Color.black.opacity(0.8))
                                        .clipShape(Circle())
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            .frame(width: 60, height: 60)
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(height: 68)
            }

            HStack {
                // Hidden rather than removed for models without vision, so the input doesn't shift sideways.
                Button(action: {
                    showImagePicker = true
                }) {
                    Image(systemName: isProcessingImages ? "clock" : "plus.circle")
                        .font(.title2)
                }
                .buttonStyle(PlainButtonStyle())
                .foregroundStyle(isProcessingImages ? .secondary : .primary)
                .disabled(isProcessingImages)
                .help(isProcessingImages ? "Processing images..." : "Attach images")
                .opacity(canAttachImages ? 1 : 0)
                .disabled(!canAttachImages)

                // Stays editable while a reply streams so the next message can be drafted, and only sending waits.
                TextField("Message \(selectedModel)", text: $text, axis: .vertical)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: fontSize))
                    .lineLimit(10)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(.rect(cornerRadius: 20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
                    )
                    .onSubmit(submit)
                    // Return when there's nothing to send would end editing and select all the text, so it's swallowed instead.
                    .onKeyPress(keys: [.return]) { press in
                        canSubmit || !press.modifiers.isEmpty ? .ignored : .handled
                    }
                    .disabled(models.isEmpty)
                    .focused(isFocused)

                // Send and Stop share one spot, as in ChatGPT and Claude.
                if isStreaming {
                    Button(action: onStop) {
                        Label("Stop generating", systemImage: "stop.circle.fill")
                            .labelStyle(.iconOnly)
                            .font(.title2)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Stop generating")
                } else {
                    Button(action: submit) {
                        Label("Send", systemImage: "arrow.up.circle.fill")
                            .labelStyle(.iconOnly)
                            .font(.title2)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundStyle(canSubmit ? .primary : .tertiary)
                    .disabled(!canSubmit)
                    .help("Send")
                }
            }
            .padding(.horizontal)
        }
        .padding(.bottom, 12)
        .onAppear {
            isFocused.wrappedValue = true
            canPasteImages = canAttachImages
            installPasteMonitor()
        }
        .onChange(of: canAttachImages) {
            canPasteImages = canAttachImages
        }
        .quickLookPreview($previewURL)
        .onChange(of: droppedItems) {
            guard !droppedItems.isEmpty else {
                return
            }
            let images = droppedItems.filter { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }
            if canAttachImages && !images.isEmpty {
                handleDroppedImages(providers: images)
            }
            insertTextFiles(from: droppedItems.filter { !images.contains($0) })
            droppedItems = []
        }
        // The window that holds the focused input, so a paste in Settings or another chat window is left alone.
        .onChange(of: isFocused.wrappedValue, initial: true) {
            if isFocused.wrappedValue {
                inputWindow = NSApp.keyWindow
            }
        }
        .onDisappear {
            if let pasteMonitor {
                NSEvent.removeMonitor(pasteMonitor)
            }
            pasteMonitor = nil
        }
        .fileImporter(
            isPresented: $showImagePicker,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                processImages(urls.map { url in
                    { () async -> Data? in
                        guard url.startAccessingSecurityScopedResource() else {
                            return nil
                        }
                        defer { url.stopAccessingSecurityScopedResource() }
                        return try? Data(contentsOf: url)
                    }
                })
            case .failure(let error):
                print("Failed to import images: \(error)")
            }
        }
    }

    private func submit() {
        guard canSubmit else {
            return
        }
        onSubmit(text.trimmingCharacters(in: .whitespacesAndNewlines), attachments.map { $0.data })
        text = ""
        attachments = []
    }

    // The text field only pastes text, so Cmd+V with an image or image file on the clipboard is caught here and attached instead.
    private func installPasteMonitor() {
        guard pasteMonitor == nil else {
            return
        }
        pasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  event.charactersIgnoringModifiers == "v",
                  isFocused.wrappedValue, event.window === inputWindow, canPasteImages, !isProcessingImages else {
                return event
            }
            let pasteboard = NSPasteboard.general
            let imageTypes = NSImage.imageTypes.map { NSPasteboard.PasteboardType($0) }
            let fileURLs = (pasteboard.readObjects(forClasses: [NSURL.self], options: [
                .urlReadingFileURLsOnly: true,
                .urlReadingContentsConformToTypes: [UTType.image.identifier]
            ]) as? [URL]) ?? []

            if !fileURLs.isEmpty {
                processImages(fileURLs.map { url in { try? Data(contentsOf: url) } })
                return nil
            }
            // Word, Pages and some browsers add a PDF or TIFF copy next to copied text, and that should still paste as text.
            if pasteboard.availableType(from: [.string]) != nil {
                return event
            }
            if let type = pasteboard.availableType(from: imageTypes), let data = pasteboard.data(forType: type) {
                processImages([{ data }])
                return nil
            }
            return event
        }
    }

    private func thinkLevelLabel(_ level: String) -> String {
        switch level {
        case "true": return "Thinking on"
        case "false": return "Thinking off"
        default: return "\(level.capitalized) thinking"
        }
    }

    private func handleDroppedImages(providers: [NSItemProvider]) {
        let loaders: [() async -> Data?] = providers.map { provider in
            {
                await withCheckedContinuation { continuation in
                    provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                        continuation.resume(returning: data)
                    }
                }
            }
        }
        processImages(loaders)
    }

    // Text and code files go into the message as fenced blocks named after the file, and other files are skipped.
    private func insertTextFiles(from providers: [NSItemProvider]) {
        Task {
            for provider in providers {
                let url = await withCheckedContinuation { continuation in
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        continuation.resume(returning: url)
                    }
                }
                guard let url, UTType(filenameExtension: url.pathExtension)?.conforms(to: .text) == true,
                      let contents = try? String(contentsOf: url, encoding: .utf8) else {
                    continue
                }
                // A blank line before each block, so several dropped files stay apart.
                let separator = text.isEmpty || text.hasSuffix("\n\n") ? "" : text.hasSuffix("\n") ? "\n" : "\n\n"
                text += separator + Self.fencedBlock(name: url.lastPathComponent, contents: contents)
            }
        }
    }

    // The fence is longer than any backtick run inside, so a Markdown file with its own code blocks stays intact.
    private static func fencedBlock(name: String, contents: String) -> String {
        var fence = "```"
        while contents.contains(fence) {
            fence += "`"
        }
        return "\(name):\n\(fence)\n\(contents.trimmingCharacters(in: .newlines))\n\(fence)\n"
    }

    // Image decoding and encoding run off the main thread to keep typing smooth.
    private func processImages(_ loaders: [() async -> Data?]) {
        processingImageBatches += 1
        Task {
            for loader in loaders {
                guard let data = await loader() else {
                    continue
                }
                let attachment = await Task.detached(priority: .userInitiated) {
                    ChatInputView.makeAttachment(from: data)
                }.value
                if let attachment {
                    attachments.append(attachment)
                }
            }
            processingImageBatches -= 1
        }
    }

    // Vision models downscale anyway, so larger images only cost memory and upload time.
    nonisolated private static func makeAttachment(from data: Data) -> ImageAttachment? {
        let maxPixelSize = 1024
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let hasAlpha = ![.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)
        let type = hasAlpha ? UTType.png : UTType.jpeg
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        let thumbnail = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        return ImageAttachment(data: output as Data, thumbnail: thumbnail)
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var selectedModel = "llama3.1"
        @State private var thinkLevel: String?
        @State private var text = ""
        @FocusState private var isFocused: Bool
        let models = [
            OllamaModelInfo(name: "llama3.1", capabilities: ["completion"], thinkLevels: []),
            OllamaModelInfo(name: "gemma4", capabilities: ["completion", "vision", "thinking"], thinkLevels: ["false", "true"])
        ]

        var body: some View {
            ChatInputView(
                isStreaming: false,
                onSubmit: { _, _ in },
                onStop: {},
                text: $text,
                selectedModel: $selectedModel,
                thinkLevel: $thinkLevel,
                isFocused: $isFocused,
                models: models,
                droppedItems: .constant([])
            )
            .frame(height: 100)
            .padding()
        }
    }

    return PreviewWrapper()
}
