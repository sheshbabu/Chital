import Foundation

enum AppConstants {
    static let ollamaDefaultBaseURL = "http://127.0.0.1:11434/api"
    
    // Zero means Ollama picks the context length based on available memory.
    static let contextLength = 0
    
    static let defaultModelName = ""
    
    // Empty means no system message is sent.
    static let systemPrompt = ""
    
    static let defaultFontSize: Double = 14.0
    
    // Caps line length in wide windows, as long lines are hard to read.
    static let chatColumnWidth: CGFloat = 760
    
    static let titleSummaryPrompt = """
    Summarize the discussion with a single relevant emoji followed by exactly three words.
    The emoji should be at the beginning, and there should be no punctuation at the end.
    The summary should capture the essence of the conversation concisely.
    
    Examples:
    🌋 Volcanic eruption explained
    🎭 Shakespeare's hidden influence
    🧬 CRISPR technology breakthrough
    🚀 Mars colonization plans
    🎨 Surrealism movement origins
    🌊 Ocean plastics crisis
    🤖 AI ethics debate
    🍄 Mycology research findings
    🏛️ Ancient Rome politics
    🧘 Mindfulness benefits explored
    
    Please provide only the emoji and three-word summary, without any additional text or explanation.
    """
}
