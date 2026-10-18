# Chital

Native macOS SwiftUI app for chatting with local Ollama models. Small, fast, minimal binary. Personal project.

## Stack
- Swift, SwiftUI, SwiftData. macOS 14+.
- Only dependency: [swift-markdown-ui](https://github.com/gonzalezreal/swift-markdown-ui) (SPM) for rendering responses.
- No test target. Build and run via Xcode (`Chital.xcodeproj`).

## Layout
All source is flat in `Chital/`:
- `ChitalApp.swift` app entry, SwiftData container, Settings scene, Chat menu commands (act on the focused window through `ThreadActions`/`SidebarActions` focused values).
- `ChatModels.swift` SwiftData models `ChatThread` and `ChatMessage` (images stored as `[Data]`).
- `OllamaService.swift` HTTP client for Ollama `/api/chat` (streaming and single), `/api/tags` and `/api/show` (capabilities, thinking levels).
- `ChatStreamer.swift` owns in-flight replies and the last error per thread (neither persisted), batches tokens, generates titles. A streaming reply's text lives in an observable `LiveReply` and is written to its `ChatMessage` once at the end, because every SwiftData write invalidates every view that uses SwiftData.
- `ContentView.swift` window and model list, plus `ThreadSidebar` (sorted by last activity, searchable, rename, new/delete). The sidebar owns the threads `@Query`, because the query updates on every streamed token and would otherwise re-run the whole window.
- `ChatThreadView.swift` message list (an eager `VStack`, since `LazyVStack` plus `scrollTo` can livelock), sending, retry, edit, fork, inline errors, auto-scroll, Markdown export.
- `ChatInputView.swift` text input (draft kept in `ChatThreadView` state and written to the thread on switch, resign active and quit, for the same reason), Send/Stop button, model and thinking pickers, image attachment (file picker, drag/drop, Cmd+V paste, resized once with ImageIO).
- `ChatBubbleView.swift` one message: user messages as right-aligned grey bubbles, replies as plain left-aligned Markdown (ChatGPT/Claude style), collapsible thinking, copy, retry, edit and branch. Replies are split into chunks at top-level blank lines by `MarkdownChunker`, which keeps finished chunks and only scans new lines. Each chunk is a separate equatable `Markdown` view, so streaming only re-renders the last one. The message column width is `AppConstants.chatColumnWidth`.
- `SettingsView.swift` user settings.
- `AppConstants.swift` defaults for settings.

## Conventions
- User settings use `@AppStorage` with defaults from `AppConstants`. Keys: `ollamaBaseURL`, `defaultModelName`, `contextLength` (0 means Ollama default), `fontSize`, `titleSummaryPrompt`, `systemPrompt` (empty means none). Add new settings the same way.
- Keep it lean. Avoid new dependencies; the small binary and fast launch are features.

## Release
Bump `MARKETING_VERSION` in `project.pbxproj`, then Xcode > Product > Archive > Distribute App > Custom > Copy App, and attach to a GitHub release.
