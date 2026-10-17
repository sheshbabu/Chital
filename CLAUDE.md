# Chital

Native macOS SwiftUI app for chatting with local Ollama models. Small, fast, minimal binary. Personal project.

## Stack
- Swift, SwiftUI, SwiftData. macOS 14+.
- Only dependency: [swift-markdown-ui](https://github.com/gonzalezreal/swift-markdown-ui) (SPM) for rendering responses.
- No test target. Build and run via Xcode (`Chital.xcodeproj`).

## Layout
All source is flat in `Chital/`:
- `ChitalApp.swift` app entry, SwiftData container, Settings scene.
- `ChatModels.swift` SwiftData models `ChatThread` and `ChatMessage` (images stored as `[Data]`).
- `OllamaService.swift` HTTP client for Ollama `/api/chat` (streaming and single), `/api/tags` and `/api/show` (capabilities, thinking levels).
- `ChatStreamer.swift` owns in-flight replies per thread (not persisted), batches tokens, generates titles.
- `ContentView.swift` sidebar of threads, model list, new/delete threads.
- `ChatThreadView.swift` message list, sending, retry, auto-scroll.
- `ChatInputView.swift` text input, model and thinking pickers, image attachment (file picker, drag/drop, resized once with ImageIO).
- `ChatBubbleView.swift` one message: user messages as right-aligned grey bubbles, replies as plain left-aligned Markdown (ChatGPT/Claude style), collapsible thinking, copy and retry. The message column width is `AppConstants.chatColumnWidth`.
- `SettingsView.swift` user settings.
- `AppConstants.swift` defaults for settings.

## Conventions
- User settings use `@AppStorage` with defaults from `AppConstants`. Keys: `ollamaBaseURL`, `defaultModelName`, `contextLength` (0 means Ollama default), `fontSize`, `titleSummaryPrompt`. Add new settings the same way.
- Keep it lean. Avoid new dependencies; the small binary and fast launch are features.

## Release
Bump `MARKETING_VERSION` in `project.pbxproj`, then Xcode > Product > Archive > Distribute App > Custom > Copy App, and attach to a GitHub release.
