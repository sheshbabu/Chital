<p align="center">
  <img width="256" src="icon.png">
  <h1 align="center">Chital</h1>
  <p align="center">A native macOS app for chatting with Ollama models</p>
</p>

## Features
* Fast launch times with minimal memory footprint
* Compact 2MB binary size
* Multiple concurrent chat threads
* Model switching during conversations
* Markdown rendering for formatted responses
* Image attachments for vision models
* Reasoning display and thinking level picker for thinking models
* Auto-generated thread titles based on conversation content

https://github.com/user-attachments/assets/14eddab2-87c3-4dd5-b26a-a58e2f12f76a

## Requirements
* macOS 14 Sonoma and above
* Ensure [Ollama](https://ollama.com) is installed 
* Ensure atleast one LLM [model](https://ollama.com/library) is downloaded

## Installation
* Download [Chital](https://github.com/sheshbabu/Chital/releases)
* Move `Chital.app` from the `Downloads` folder into the `Applications` folder. 
* Goto `System Settings` ->  `Privacy & Security` -> click `Open Anyway`
<img width="500" alt="Screenshot 2024-09-29 at 10 35 50 AM" src="https://github.com/user-attachments/assets/04f61c0b-a817-4350-854b-36140195fd1b">


## Configuration
The following settings can be changed from Chital > Settings:
* Default model
* Ollama base URL
* Context length
* Font size
* Chat thread title summarization prompt

## Keyboard Shortcuts
* `Command + N` New chat thread
* `Option + Enter` Multiline input

## Contributions
This is a personal project built for my own use. The codebase is available for forking and modifications. Note that I may not actively review pull requests or respond to issues due to time constraints.

## New Version
* Update version in `project.pbxproj`
* Xcode > Product > Archive > Distribute App > Custom > Copy App > Select folder ...
* Draft a new release and attach the application

## License
MIT
