import Foundation
import SwiftUI

struct OllamaChatMessage: Codable {
    let role: String
    let content: String
}

struct OllamaChatRequestOptions: Codable {
    let num_ctx: Int
}

struct OllamaChatRequest: Codable {
    let model: String
    let messages: [OllamaChatMessage]
    let stream: Bool?
    let options: OllamaChatRequestOptions?
}

struct OllamaChatResponse: Codable {
    let message: OllamaChatMessage?
    let done: Bool
}

struct OllamaModelResponse: Codable {
    let models: [OllamaModel]
}

struct OllamaModel: Codable {
    let name: String
}

class OllamaService {
    @AppStorage("ollamaBaseURL") private var baseURLString = AppConstants.ollamaDefaultBaseURL
    @AppStorage("contextWindowLength") private var contextWindowLength = AppConstants.contextWindowLength
    
    private var baseURL: URL {
        guard let url = URL(string: baseURLString) else {
            fatalError("Invalid base URL: \(baseURLString)")
        }
        return url
    }
    
    func sendSingleMessage(model: String, messages: [OllamaChatMessage]) async throws -> String {
        let url = baseURL.appendingPathComponent("chat")
        let payload = OllamaChatRequest(model: model, messages: messages, stream: false, options: OllamaChatRequestOptions(num_ctx: contextWindowLength))
        
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(payload)
        
        let (data, _) = try await URLSession.shared.data(for: req)
        let res = try JSONDecoder().decode(OllamaChatResponse.self, from: data)
        
        return res.message?.content ?? ""
    }
    
    func streamConversation(model: String, messages: [OllamaChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let url = baseURL.appendingPathComponent("chat")
                    let payload = OllamaChatRequest(model: model, messages: messages, stream: true, options: OllamaChatRequestOptions(num_ctx: contextWindowLength))
                    
                    var req = URLRequest(url: url)
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.httpBody = try JSONEncoder().encode(payload)
                    
                    let (stream, _) = try await URLSession.shared.bytes(for: req)
                    
                    for try await line in stream.lines {
                        if let data = line.data(using: .utf8),
                           let res = try? JSONDecoder().decode(OllamaChatResponse.self, from: data) {
                            if let content = res.message?.content {
                                continuation.yield(content)
                            }
                            if res.done {
                                continuation.finish()
                                return
                            }
                        }
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    func fetchModelList() async throws -> [String] {
        let url = baseURL.appendingPathComponent("tags")
        
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        
        let (data, _) = try await URLSession.shared.data(for: req)
        let res = try JSONDecoder().decode(OllamaModelResponse.self, from: data)
        
        return res.models.map { $0.name }
    }
}
