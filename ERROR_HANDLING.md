# Error Handling

Errors should help the user recover without making them read infrastructure logs.

## User-Facing Error Shape

Every backend error should have:

- plain-language title
- plain-language explanation
- suggested recovery action
- optional technical details
- related backend id or job id when available

## Examples

### Docker Missing

Title: Backend runtime not installed

Explanation: This backend needs Docker Desktop, but Docker was not found on this Mac.

Recovery: Open Settings -> Backends and install or connect a supported backend.

Details: include the executable paths checked.

### Docker Stopped

Title: Backend runtime is not running

Explanation: Docker Desktop is installed but is not currently available.

Recovery: Start Docker Desktop, then retry the backend health check.

Details: include `docker info` output.

### Generation Failed

Title: Generation failed

Explanation: The selected backend could not complete this narration.

Recovery: Keep the session record, show details, and offer retry or duplicate as new.

Details: include backend logs and command metadata.

## Non-Negotiables

- Never delete failed session folders.
- Never overwrite logs, input text, metadata, or output audio.
- Never show raw stack traces as the primary message.
- Always preserve enough metadata to reproduce or diagnose the run.
