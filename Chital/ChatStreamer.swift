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
    // Streaming replies by message ID, kept out of SwiftData until they end, since every SwiftData write invalidates every view that uses SwiftData.
    private(set) var liveReplies: [UUID: LiveReply] = [:]
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

    func liveReply(for message: ChatMessage) -> LiveReply? {
        liveReplies[message.id]
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
        let live = LiveReply()
        liveReplies[reply.id] = live

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
                if !pendingText.isEmpty {
                    live.text += pendingText
                }
                if !pendingThinking.isEmpty {
                    live.thinking += pendingThinking
                }
                pendingText = ""
                pendingThinking = ""
                lastFlush = .now
            }

            var tokensPerSecond: Double?
            var tokensUsed: Int?
            var failed = false
            do {
                for try await chunk in ollamaService.streamConversation(model: modelName, messages: history, think: think) {
                    pendingText += chunk.message?.content ?? ""
                    pendingThinking += chunk.message?.thinking ?? ""
                    // Timed per chunk rather than per flush, and set once each, since Observation notifies on every set.
                    if chunk.message?.thinking?.isEmpty == false && live.thinkingStart == nil {
                        live.thinkingStart = .now
                    }
                    if chunk.message?.content?.isEmpty == false && live.thinkingStart != nil && live.thinkingEnd == nil {
                        live.thinkingEnd = .now
                    }
                    if let count = chunk.eval_count, let duration = chunk.eval_duration, duration > 0 {
                        tokensPerSecond = Double(count) / (Double(duration) / 1_000_000_000)
                    }
                    if let prompt = chunk.prompt_eval_count, let count = chunk.eval_count {
                        tokensUsed = prompt + count
                    }
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
            // A reply stopped while thinking still gets a duration.
            if live.thinkingStart != nil && live.thinkingEnd == nil {
                live.thinkingEnd = .now
            }

            // Written in the same update that drops the live reply, so the bubble switches over without a blank frame.
            // The thread may have been deleted while streaming.
            if !reply.isDeleted {
                reply.text = live.text
                reply.thinking = live.thinking.isEmpty ? nil : live.thinking
                reply.tokensPerSecond = tokensPerSecond
                reply.thinkingSeconds = live.thinkingSeconds
            }
            liveReplies[reply.id] = nil

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

            // In its own task, so the extra request doesn't hold up the end of streaming.
            if let tokensUsed {
                Task {
                    if let total = await ollamaService.fetchContextLength(model: modelName), total > 0, !reply.isDeleted {
                        reply.contextUsage = Double(tokensUsed) / Double(total)
                        // The reply was already saved when streaming ended, and autosave can lag.
                        try? reply.modelContext?.save()
                    }
                }
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

@Observable
final class LiveReply {
    var text = ""
    var thinking = ""
    // Each is set once, when thinking starts and when the answer starts, so the label can count up live.
    var thinkingStart: Date?
    var thinkingEnd: Date?

    // Lets a collapsed thinking section depend on the start alone, so it skips the update of every thinking flush.
    var hasThinking: Bool {
        thinkingStart != nil
    }

    var thinkingSeconds: Double? {
        guard let thinkingStart, let thinkingEnd else {
            return nil
        }
        return thinkingEnd.timeIntervalSince(thinkingStart)
    }
}
