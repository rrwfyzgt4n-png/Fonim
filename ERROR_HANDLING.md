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

### Backend Operation Failed

Title: Backend action failed

Explanation: The app could not complete the selected backend action, such as install, update, prepare, stop, repair, or reset.

Recovery: Keep the primary message plain-language, offer a next action, and put command output behind Show Details.

Details: include the managed operation name, backend id, and captured process output.

### Session Archived

Title: Session archived

Explanation: The session was moved out of active history; no input, output audio, log, or metadata files were deleted.

Recovery: Move the archived session folder from `recovered/deleted_sessions` back into `history`.

Details: include the archived folder name.

## Non-Negotiables

- Never delete failed session folders.
- Never overwrite logs, input text, metadata, or output audio.
- Archive history and outputs by moving session folders into `recovered/deleted_sessions`; never delete them in place.
- Never show raw stack traces as the primary message.
- Always provide a way to copy user-facing error details.
- Session input, logs, and metadata should remain copyable from the app.
- Always preserve enough metadata to reproduce or diagnose the run.
- Backend reset must not delete history, generated audio, logs, metadata, or model cache.
- Filing outputs into a project must be idempotent and must not move, rewrite, or mutate session folders.
