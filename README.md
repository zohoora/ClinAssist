# ClinAssist

A native macOS menu bar app that acts as a real-time ambient assistant for family physicians.

![macOS](https://img.shields.io/badge/macOS-14.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9+-orange)
![License](https://img.shields.io/badge/License-MIT-green)

## Features

- **Menu Bar App**: Lives quietly in your menu bar with a stethoscope icon
- **Real-time Transcription**: Records and transcribes patient encounters using Deepgram
- **Problem-oriented SOAP Notes**: Automatically generates and updates SOAP notes
- **Clinical Decision Support**: Provides DDx suggestions, red flags, and suggested questions
- **Drug Cards**: Displays medication information when drugs are mentioned
- **Local Storage**: All encounter data saved locally on your Desktop

## Requirements

- macOS 14.0 (Sonoma) or later
- M1/M2 Mac recommended
- Microphone access
- Accessibility access (for global hotkey)

## API Keys Required

You'll need API keys from:
- [OpenRouter](https://openrouter.ai/) - For LLM processing
- [Deepgram](https://deepgram.com/) - For speech-to-text

## Installation

### From Source

1. Clone the repository:
   ```bash
   git clone https://github.com/YOUR_USERNAME/ClinAssist.git
   cd ClinAssist
   ```

2. Open in Xcode:
   ```bash
   open ClinAssist.xcodeproj
   ```

3. Build and run (⌘R)

### Configuration

Create a config file at `~/Desktop/ClinAssist/config.json`:

```json
{
  "openrouter_api_key": "sk-or-your-key-here",
  "deepgram_api_key": "your-deepgram-key-here",
  "model": "openai/gpt-4.1",
  "timing": {
    "transcription_interval_seconds": 10,
    "helper_update_interval_seconds": 20,
    "soap_update_interval_seconds": 30
  }
}
```

## Usage

1. **Start**: Click the stethoscope icon in the menu bar, or press `⌃⌥S`
2. **Record**: Speak naturally with your patient
3. **Monitor**: Watch the transcript and SOAP note update in real-time
4. **End**: Click "End Encounter" to generate the final note
5. **Copy**: Use "Copy to Clipboard" to paste into your EMR

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌃⌥S` | Start/End Encounter |

## Project Structure

```
ClinAssist/
├── ClinAssistApp.swift           # App entry point
├── AppDelegate.swift             # Menu bar & window management
├── AppState.swift                # State enum
├── Config/
│   └── ConfigManager.swift       # API key loading
├── Audio/
│   └── AudioManager.swift        # AVAudioEngine recording
├── Transcription/
│   ├── STTClient.swift           # Protocol
│   └── DeepgramRESTClient.swift  # Deepgram integration
├── LLM/
│   └── LLMClient.swift           # OpenRouter integration
├── Encounter/
│   ├── EncounterState.swift      # Data models
│   ├── EncounterController.swift # Orchestrates everything
│   └── EncounterStorage.swift    # File persistence
└── Views/
    ├── MainWindow.swift          # Main window view
    ├── TranscriptView.swift      # Transcript display
    ├── SOAPView.swift            # SOAP note display
    ├── HelperPanelView.swift     # Assistant panel
    ├── EndEncounterSheet.swift   # End encounter modal
    └── SetupView.swift           # Configuration setup
```

## Data Storage

Encounters are saved to:
```
~/Desktop/ClinAssist/encounters/YYYY-MM-DD_HH-MM-SS/
├── encounter.json      # Full encounter state
├── transcript.txt      # Plain text transcript
└── soap_note.txt       # Final SOAP note
```

## Privacy & Security

- **All data stays local**: No cloud sync, no telemetry
- **API keys stored locally**: In your config.json file
- **Audio deleted after processing**: Temp files cleaned up automatically

## Tech Stack

- **Language**: Swift 5.9+
- **UI**: SwiftUI
- **Audio**: AVFoundation
- **Networking**: URLSession
- **STT**: Deepgram REST API
- **LLM**: OpenRouter API

## License

MIT License - see LICENSE file for details.

## Disclaimer

This tool is intended to assist healthcare providers and should not replace clinical judgment. Always verify AI-generated content before use in patient care.

