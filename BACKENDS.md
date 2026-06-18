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

## Registered Backends

### VibeVoiceTTS

- Runtime: Docker
- Role: long-form expressive narration
- Strength: longer scripts, richer voice behavior
- Risk: heavier setup, more parameters, slower generation
- Current image: `vibevoice-cpu`
- Current model: `microsoft/VibeVoice-Realtime-0.5B`

#### VibeVoice Docker Compatibility Shim

The current `vibevoice-cpu` Dockerfile includes a container-local `sitecustomize.py` shim that forces `torch.load(..., weights_only=False)` for VibeVoice voice-preset `.pt` loading under PyTorch 2.6+.

This is a compatibility workaround for the current upstream VibeVoice loader. It must remain scoped to the managed VibeVoice image and must not be applied to the user's macOS Python environment or to unrelated backend images.

Risk: `weights_only=False` enables pickle-backed loading inside the container. The app should only use this image with the managed VibeVoice workflow and trusted model or preset sources; it should not present the image as a general-purpose PyTorch runtime for arbitrary `.pt` files.

Removal condition: remove the shim when upstream VibeVoice supports safe voice-preset loading with PyTorch's current defaults, or when the image pins and documents a VibeVoice loader that no longer requires the global `torch.load` override.

### Kokoro

- Runtime: external service or installed Docker image
- Role: fast clean preview and simple final narration
- Strength: speed, simplicity, quality per complexity
- Risk: service contract depends on the installed Kokoro package or image
- Current model id: `kokoro/default`
- Current adapter: `KokoroHTTPAdapter`
- Default service paths: `/health`, `/v1/audio/speech`

### Chatterbox TTS

- Runtime: external local service
- Role: expressive local narration with predefined and reference voices
- Strength: temperature, exaggeration, CFG weight, seed, speed, language, and chunking controls
- Risk: progress is request-based unless the running service exposes streaming job status
- Current model id: `chatterbox`
- Current adapter: `ChatterboxHTTPAdapter`
- Default service URL: `http://127.0.0.1:8004`
- Health endpoint: `/api/model-info`
- Generation endpoint: `/tts`
- Voice catalog endpoints: `/get_predefined_voices`, `/get_reference_files`
- Output policy: the app requests non-streaming WAV output and archives it as `history/<session_id>/output.wav`

## Planned Backend Classes

### ComfyUI TTS-Audio-Suite

- Runtime: Docker or external ComfyUI server
- Role: node/workflow engine
- Strength: extensibility
- Risk: technical complexity

### F5-TTS / CosyVoice

- Runtime: Docker
- Role: experimental and high-quality alternatives
- Strength: voice cloning and expressive options
- Risk: model-specific instability

## Docker Policy

Docker is allowed as a runtime, but never as the product identity. The app should detect, explain, install, start, stop, repair, and uninstall Docker-backed services through native UI flows.

## Managed Operations

The current manager supports:

- install: prepare local folders and pull the managed backend image
- update: pull the managed backend image again
- prepare: verify the local runtime and image before generation
- stop: stop app-owned `vibevoice_batch_` containers
- health check: report runtime readiness in plain language
- repair: rebuild local folders and install the image if needed
- reset: stop app-owned containers and recover stray staging WAV files without deleting history, generated outputs, logs, metadata, or model cache
- disk usage: report project, history, outputs, recovered, and model-cache storage

VibeVoice currently runs as a one-shot generation container, not a resident server. For this backend, "prepare" is the equivalent of starting managed infrastructure: it verifies that Docker is available and the image is present.
