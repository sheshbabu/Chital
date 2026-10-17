import SwiftUI
import ImageIO
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

    @Binding var selectedModel: String
    @Binding var thinkLevel: String?
    let models: [OllamaModelInfo]

    @State private var currentInputMessage = ""
    @State private var attachments: [ImageAttachment] = []
    @State private var showImagePicker = false
    @State private var isProcessingImages = false
    @FocusState private var isTextFieldFocused: Bool

    @AppStorage("fontSize") private var fontSize = AppConstants.defaultFontSize

    private var selectedModelInfo: OllamaModelInfo? {
        models.first { $0.name == selectedModel }
    }

    private var canAttachImages: Bool {
        selectedModelInfo?.supportsImages ?? false
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
                .onChange(of: selectedModel) { isTextFieldFocused = true }
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
                                    .cornerRadius(8)
                                    .clipped()

                                Button(action: {
                                    attachments.removeAll { $0.id == attachment.id }
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(.white)
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
                if canAttachImages {
                    Button(action: {
                        showImagePicker = true
                    }) {
                        Image(systemName: isProcessingImages ? "clock" : "plus.circle")
                            .font(.title2)
                            .foregroundColor(isStreaming || isProcessingImages ? .gray : .primary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(isStreaming || isProcessingImages)
                    .help(isProcessingImages ? "Processing images..." : "Attach images")
                }

                TextField(isStreaming ? "Thinking..." : "How can I help you today?", text: $currentInputMessage, axis: .vertical)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: fontSize))
                    .lineLimit(10)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(20)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
                    )
                    .onSubmit(submit)
                    .disabled(isStreaming || models.isEmpty)
                    .focused($isTextFieldFocused)
                    .onDrop(of: [.image], isTargeted: nil) { providers in
                        guard canAttachImages else {
                            return false
                        }
                        handleDroppedImages(providers: providers)
                        return true
                    }

                if isStreaming {
                    Button(action: onStop) {
                        Image(systemName: "stop.circle.fill")
                            .font(.title2)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Stop generation")
                }
            }
            .padding(.horizontal)
        }
        .padding(.bottom, 12)
        .onAppear {
            isTextFieldFocused = true
        }
        .onChange(of: isStreaming) { _, isStreaming in
            if !isStreaming {
                isTextFieldFocused = true
            }
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
        let text = currentInputMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty && attachments.isEmpty {
            return
        }
        onSubmit(text, attachments.map { $0.data })
        currentInputMessage = ""
        attachments = []
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

    // Image decoding and encoding run off the main thread to keep typing smooth.
    private func processImages(_ loaders: [() async -> Data?]) {
        isProcessingImages = true
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
            isProcessingImages = false
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
        let models = [
            OllamaModelInfo(name: "llama3.1", capabilities: ["completion"], thinkLevels: []),
            OllamaModelInfo(name: "gemma4", capabilities: ["completion", "vision", "thinking"], thinkLevels: ["false", "true"])
        ]

        var body: some View {
            ChatInputView(
                isStreaming: false,
                onSubmit: { _, _ in },
                onStop: {},
                selectedModel: $selectedModel,
                thinkLevel: $thinkLevel,
                models: models
            )
            .frame(height: 100)
            .padding()
        }
    }

    return PreviewWrapper()
}
