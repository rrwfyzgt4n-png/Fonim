# Backends

Backends are managed infrastructure. Users choose narration goals and voices; they should not feel like they are operating Docker.

## Backend Profile

Each backend profile defines:

- `id`
- `displayName`
- `engineType`
- `installMethod`
- `runtime`
- `dockerImage`
- `requiredModels`
- `requiredDiskSpace`
- `requiredMemory`
- `supportedArchitectures`
- `exposedPort`
- `healthCheckURL`
- `generateEndpoint`
- `cancelEndpoint`
- `progressParser`
- `logParser`
- `outputFormatSupport`
- `licenseNotes`

## Initial Backend

### VibeVoiceTTS

- Runtime: Docker
- Role: long-form expressive narration
- Strength: longer scripts, richer voice behavior
- Risk: heavier setup, more parameters, slower generation
- Current image: `vibevoice-cpu`
- Current model: `microsoft/VibeVoice-Realtime-0.5B`

## Planned Backend Classes

### Kokoro

- Runtime: Docker or local Python
- Role: fast clean preview and simple final narration
- Strength: speed, simplicity, quality per complexity
- Risk: less ambitious than VibeVoice for expressive long-form reads

### ComfyUI TTS-Audio-Suite

- Runtime: Docker or external ComfyUI server
- Role: node/workflow engine
- Strength: extensibility
- Risk: technical complexity

### F5-TTS / Chatterbox / CosyVoice

- Runtime: Docker
- Role: experimental and high-quality alternatives
- Strength: voice cloning and expressive options
- Risk: model-specific instability

## Docker Policy

Docker is allowed as a runtime, but never as the product identity. The app should detect, explain, install, start, stop, repair, and uninstall Docker-backed services through native UI flows.
