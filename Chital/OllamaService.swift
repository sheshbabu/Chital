import Foundation
import SwiftUI

struct OllamaChatMessage: Encodable {
    let role: String
    let content: String
    let images: [String]?

    init(role: String, content: String, images: [String]? = nil) {
        self.role = role
        self.content = content
        self.images = images
    }
}

struct OllamaChatRequestOptions: Encodable {
    let num_ctx: Int
}

struct OllamaChatRequest: Encodable {
    let model: String
    let messages: [OllamaChatMessage]
    let stream: Bool
    let options: OllamaChatRequestOptions?
    let think: String?

    enum CodingKeys: String, CodingKey {
        case model, messages, stream, options, think
    }

    // Ollama expects think as a bool for on/off models and as a string for models with levels.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(messages, forKey: .messages)
        try container.encode(stream, forKey: .stream)
        try container.encodeIfPresent(options, forKey: .options)
        switch think {
        case nil:
            break
        case "true":
            try container.encode(true, forKey: .think)
        case "false":
            try container.encode(false, forKey: .think)
        case let level?:
            try container.encode(level, forKey: .think)
        }
    }
}

struct OllamaResponseMessage: Decodable {
    let content: String?
    let thinking: String?
}

struct OllamaChatResponse: Decodable {
    let message: OllamaResponseMessage?
    let done: Bool?
    let error: String?
    // Only on the final chunk. The duration is in nanoseconds.
    let prompt_eval_count: Int?
    let eval_count: Int?
    let eval_duration: Int?
}

struct OllamaErrorResponse: Decodable {
    let error: String
}

struct OllamaModelResponse: Decodable {
    let models: [OllamaModel]
}

struct OllamaModel: Decodable {
    let name: String
}

struct OllamaRunningResponse: Decodable {
    let models: [OllamaRunningModel]
}

struct OllamaRunningModel: Decodable {
    let name: String
    let context_length: Int?
}

struct OllamaShowResponse: Decodable {
    let capabilities: [String]?
    let thinking: OllamaThinkingInfo?
}

struct OllamaThinkingInfo: Decodable {
    let values: [OllamaThinkValue]?
}

// Thinking values are a mix of booleans and level names, so both are kept as strings.
struct OllamaThinkValue: Decodable {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) {
            value = bool ? "true" : "false"
        } else {
            value = try container.decode(String.self)
        }
    }
}

struct OllamaModelInfo: Equatable {
    let name: String
    // Nil when the Ollama server is too old to report capabilities.
    let capabilities: [String]?
    let thinkLevels: [String]

    var canChat: Bool {
        capabilities?.contains("completion") ?? true
    }

    var supportsImages: Bool {
        capabilities?.contains("vision") ?? true
    }

    // Titles should be cheap, so use thinking off or the lowest level the model offers.
    var cheapestThinkLevel: String? {
        thinkLevels.contains("false") ? "false" : thinkLevels.first
    }
}

enum OllamaError: LocalizedError {
    case invalidBaseURL(String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL(let url):
            return "The Ollama base URL \"\(url)\" is not valid. Please fix it in Settings."
        case .server(let message):
            return "Ollama returned an error: \(message)"
        }
    }
}

func ollamaErrorMessage(_ error: Error) -> String {
    switch (error as? URLError)?.code {
    case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost:
        return "Unable to connect to the Ollama API. Please ensure that the Ollama server is running."
    case .timedOut:
        return "The request to Ollama API timed out. Please try again later."
    default:
        if let ollamaError = error as? OllamaError {
            return ollamaError.localizedDescription
        }
        return "An unexpected error occurred while communicating with the Ollama API: \(error.localizedDescription)"
    }
}

class OllamaService {
    @AppStorage("ollamaBaseURL") private var baseURLString = AppConstants.ollamaDefaultBaseURL
    @AppStorage("contextLength") private var contextLength = AppConstants.contextLength

    // Large models can take minutes to load before the first token arrives.
    private let chatTimeout: TimeInterval = 300

    // Accepts both "http://host:11434" and "http://host:11434/api", since users commonly enter either.
    private func endpoint(_ path: String) throws -> URL {
        var base = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") {
            base.removeLast()
        }
        if !base.hasSuffix("/api") {
            base += "/api"
        }
        guard let url = URL(string: "\(base)/\(path)"), url.scheme != nil, url.host != nil else {
            throw OllamaError.invalidBaseURL(baseURLString)
        }
        return url
    }

    private func chatRequest(model: String, messages: [OllamaChatMessage], stream: Bool, think: String?) throws -> URLRequest {
        // Only send num_ctx when the user set one, since Ollama picks a larger default based on available memory.
        let options = contextLength > 0 ? OllamaChatRequestOptions(num_ctx: contextLength) : nil
        let payload = OllamaChatRequest(model: model, messages: messages, stream: stream, options: options, think: think)

        var req = URLRequest(url: try endpoint("chat"))
        req.httpMethod = "POST"
        req.timeoutInterval = chatTimeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(payload)
        return req
    }

    private func checkStatus(_ response: URLResponse, body: Data) throws {
        guard let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) else {
            return
        }
        if let res = try? JSONDecoder().decode(OllamaErrorResponse.self, from: body) {
            throw OllamaError.server(res.error)
        }
        throw OllamaError.server("HTTP \(http.statusCode)")
    }

    func sendSingleMessage(model: String, messages: [OllamaChatMessage], think: String?) async throws -> String {
        let req = try chatRequest(model: model, messages: messages, stream: false, think: think)
        let (data, response) = try await URLSession.shared.data(for: req)
        try checkStatus(response, body: data)
        let res = try JSONDecoder().decode(OllamaChatResponse.self, from: data)

        return res.message?.content ?? ""
    }

    func streamConversation(model: String, messages: [OllamaChatMessage], think: String?) -> AsyncThrowingStream<OllamaChatResponse, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let req = try chatRequest(model: model, messages: messages, stream: true, think: think)
                    let (stream, response) = try await URLSession.shared.bytes(for: req)

                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        var body = Data()
                        for try await byte in stream {
                            body.append(byte)
                        }
                        try checkStatus(response, body: body)
                    }

                    for try await line in stream.lines {
                        guard let data = line.data(using: .utf8),
                              let res = try? JSONDecoder().decode(OllamaChatResponse.self, from: data) else {
                            continue
                        }
                        // Errors that happen after streaming started arrive as a line with an error field.
                        if let error = res.error {
                            throw OllamaError.server(error)
                        }
                        continuation.yield(res)
                        if res.done == true {
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            // Cancelling the request is what makes Ollama stop generating.
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // The context length the model is loaded with, which Ollama picks from available memory unless the user set one.
    func fetchContextLength(model: String) async -> Int? {
        if contextLength > 0 {
            return contextLength
        }
        guard let url = try? endpoint("ps"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let res = try? JSONDecoder().decode(OllamaRunningResponse.self, from: data) else {
            return nil
        }
        return res.models.first { $0.name == model }?.context_length
    }

    func fetchModels() async throws -> [OllamaModelInfo] {
        let (data, response) = try await URLSession.shared.data(from: try endpoint("tags"))
        try checkStatus(response, body: data)
        let names = try JSONDecoder().decode(OllamaModelResponse.self, from: data).models.map { $0.name }

        let infos = await withTaskGroup(of: OllamaModelInfo.self) { group in
            for name in names {
                group.addTask { await self.fetchModelInfo(name) }
            }
            var infos: [OllamaModelInfo] = []
            for await info in group {
                infos.append(info)
            }
            return infos
        }

        // Concurrent lookups finish out of order, so map back to the server's order.
        return names.compactMap { name in infos.first { $0.name == name } }.filter { $0.canChat }
    }

    private func fetchModelInfo(_ name: String) async -> OllamaModelInfo {
        do {
            var req = URLRequest(url: try endpoint("show"))
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(["model": name])

            let (data, response) = try await URLSession.shared.data(for: req)
            try checkStatus(response, body: data)
            let res = try JSONDecoder().decode(OllamaShowResponse.self, from: data)
            let levels = res.capabilities?.contains("thinking") == true ? (res.thinking?.values ?? []).map { $0.value } : []
            return OllamaModelInfo(name: name, capabilities: res.capabilities, thinkLevels: levels)
        } catch {
            return OllamaModelInfo(name: name, capabilities: nil, thinkLevels: [])
        }
    }
}
