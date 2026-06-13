# Project Direction

This project is a native macOS local narration workstation, not a single-model wrapper.

The app must be irreproachable by macOS Human Interface Guidelines standards:

- native layout
- native menus
- real Settings
- proper status states
- clear error handling
- progressive disclosure
- no terminal-first UX
- no raw Docker complexity exposed to normal users

## Architecture Requirement

Support multiple TTS engines through an `EngineAdapter` abstraction.

VibeVoiceTTS is one backend, not the app architecture. Docker is allowed as a backend runtime, but the user experience must treat it as managed infrastructure. The app should detect, install or connect, health-check, start, stop, repair, and explain backend state through native UI.

Before implementing any feature, explain:

1. how it fits the long-term architecture
2. whether it improves or damages HIG compliance
3. whether it preserves multi-model backend support
4. which files or modules should own the logic
5. what technical debt it creates

## Product Layers

- Docker and Python are service infrastructure.
- Engine adapters are the expansion layer.
- HIG compliance is the trust layer.
- History, presets, batches, and reproducible metadata are the product layer.
