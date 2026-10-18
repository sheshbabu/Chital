import Foundation
import SwiftUI
import SwiftData

// Owns in-flight generations so they survive switching threads and are never persisted.
@MainActor
@Observable
final class ChatStreamer {
    @ObservationIgnored @AppStorage("titleSummaryPrompt") private var titleSummaryPrompt = AppConstants.titleSummaryPrompt
    @ObservationIgnored @AppStorage("systemPrompt") private var systemPrompt = AppConstants.systemPrompt

    private(set) var streamingThreadIDs: Set<UUID> = []
    // The last failure per thread, shown inline at the end of that thread until the next send.
    private(set) var errors: [UUID: String] = [:]

    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private let ollamaService = OllamaService()

    // Batching keeps Markdown re-rendering to a few times per second instead of once per token.
    // 100ms, as in Enchanted, still looks smooth and halves the SwiftUI update and layout work of 50ms.
    private let flushInterval: Duration = .milliseconds(100)

    func isStreaming(_ thread: ChatThread) -> Bool {
        streamingThreadIDs.contains(thread.id)
    }

    func error(for thread: ChatThread) -> String? {
        errors[thread.id]
    }

    func stop(_ thread: ChatThread) {
        tasks[thread.id]?.cancel()
    }

    func stopAll() {
        tasks.values.forEach { $0.cancel() }
    }

    func send(_ thread: ChatThread, model: OllamaModelInfo?) {
        guard !isStreaming(thread) else {
            return
        }
        errors[thread.id] = nil
        guard let model, let modelName = thread.selectedModel, modelName == model.name else {
            errors[thread.id] = "No model selected."
            return
        }

        let prompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let system = prompt.isEmpty ? [] : [OllamaChatMessage(role: "system", content: prompt)]
        let history = system + thread.chronologicalMessages.map { message in
            OllamaChatMessage(
                role: message.isUser ? "user" : "assistant",
                content: message.text,
                images: message.images?.map { $0.base64EncodedString() }
            )
        }
        let think = thread.thinkLevel.flatMap { model.thinkLevels.contains($0) ? $0 : nil }

        let reply = ChatMessage(text: "", isUser: false, timestamp: Date())
        thread.messages.append(reply)
        thread.updatedAt = Date()

        let threadID = thread.id
        streamingThreadIDs.insert(threadID)

        tasks[threadID] = Task {
            defer {
                tasks[threadID] = nil
                streamingThreadIDs.remove(threadID)
                try? thread.modelContext?.save()
            }

            var pendingText = ""
            var pendingThinking = ""
            var lastFlush = ContinuousClock.now

            func flush() {
                // The thread may have been deleted while streaming.
                guard !reply.isDeleted else {
                    return
                }
                if !pendingText.isEmpty {
                    reply.text += pendingText
                }
                if !pendingThinking.isEmpty {
                    reply.thinking = (reply.thinking ?? "") + pendingThinking
                }
                pendingText = ""
                pendingThinking = ""
                lastFlush = .now
            }

            var failed = false
            do {
                for try await chunk in ollamaService.streamConversation(model: modelName, messages: history, think: think) {
                    pendingText += chunk.content ?? ""
                    pendingThinking += chunk.thinking ?? ""
                    if ContinuousClock.now - lastFlush >= flushInterval {
                        flush()
                    }
                }
            } catch {
                failed = true
                if !Task.isCancelled {
                    errors[threadID] = ollamaErrorMessage(error)
                }
            }
            flush()

            // A cancelled stream ends without throwing, so this runs for Stop as well as for errors.
            // An empty reply bubble is useless, and removing it lets the user retry from their message.
            if !reply.isDeleted && reply.text.isEmpty && (reply.thinking ?? "").isEmpty {
                thread.messages.removeAll { $0.id == reply.id }
                reply.modelContext?.delete(reply)
                return
            }

            if !failed && !Task.isCancelled && !thread.isDeleted && !thread.hasReceivedFirstMessage {
                thread.hasReceivedFirstMessage = true
                generateTitle(thread, reply: reply, model: model)
            }
        }
    }

    private func generateTitle(_ thread: ChatThread, reply: ChatMessage, model: OllamaModelInfo) {
        // The opening question and its answer as text are enough for a title, and skip re-sending images and long histories.
        // An image-only question has no text, and an empty turn only confuses the model.
        let firstQuestion = thread.chronologicalMessages.first { $0.isUser }
        let firstExchange = [firstQuestion, reply].compactMap { $0 }.filter { !$0.text.isEmpty }.map { message in
            OllamaChatMessage(role: message.isUser ? "user" : "assistant", content: message.text)
        }
        let messages = firstExchange + [OllamaChatMessage(role: "user", content: titleSummaryPrompt)]
        let provisionalTitle = thread.title

        Task {
            do {
                let summary = try await ollamaService.sendSingleMessage(model: model.name, messages: messages, think: model.cheapestThinkLevel)
                let title = summary.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines).first ?? ""
                // A rename while the title was generating wins.
                if !thread.isDeleted && !title.isEmpty && thread.title == provisionalTitle {
                    thread.title = title
                }
            } catch {
                print("Error summarizing thread: \(error.localizedDescription)")
            }
        }
    }
}
