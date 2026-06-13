# HIG Checklist

The app should feel like a Mac narration workstation, not a terminal frontend.

## Native Structure

- Sidebar for Projects, Scripts, Batches, Voices, Presets, History, Backends, and Settings.
- Toolbar for primary context actions.
- Inspector for voice, model, inference settings, export settings, and metadata.
- Real Settings window for backend and generation defaults.
- Standard macOS keyboard shortcuts for common actions.

## Progressive Disclosure

Normal users see:

- text
- voice
- generate
- output

Advanced users can reveal:

- backend
- model
- inference steps
- temperature
- seed
- backend logs
- parser details

## Status States

The app must show plain-language states for:

- Docker missing
- Docker stopped
- backend installing
- model downloading
- backend ready
- generation running
- generation failed
- output complete

Current implementation:

- A native status strip shows the selected backend, runtime state, and a plain-language message.
- Missing or stopped Docker states include a recovery suggestion behind Details.
- Generation preflights backend readiness before creating a session.

## Settings

Current implementation:

- The app uses a real macOS Settings scene rather than treating preferences as a main-window destination.
- Settings are grouped into Backends, Models, Voices, Output, and Advanced panes.
- Backend details remain plain-language in normal settings, with raw details available only through Show Details.
- Backend install, update, prepare, stop, repair, and reset are native Settings actions backed by `BackendManager` operations.
- Disk usage is summarized in Settings without making the user inspect folders manually.

## Setup Assistant

Current implementation:

- First launch opens a native Backend Setup Assistant until setup is completed.
- The assistant shows plain-language checks for Mac compatibility, local folders, Docker runtime, backend image, model cache, and health.
- The assistant can install, repair, and prepare the selected backend without sending the user to Terminal.
- Test voice generation goes through the normal queue and no-overwrite history behavior.

## Error Presentation

- Primary errors must be plain-language.
- Technical details belong behind "Show Details".
- Raw stack traces must never be the primary user experience.
- Every failed generation keeps a record, log, and metadata.

## File Behavior

- User chooses output folders.
- Generated files can be revealed in Finder.
- Generated audio can be played in app.
- Generated audio should be draggable out of the app in a later UI pass.
- Quick Look support should be evaluated for the output browser.
