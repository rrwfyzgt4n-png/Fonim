# HIG Checklist

The app should feel like a Mac narration workstation, not a terminal frontend.

## Native Structure

- Sidebar for Projects, Scripts, Batches, Outputs, Voices, Presets, History, Backends, and Settings.
- Toolbar for primary context actions.
- Inspector for voice, model, inference settings, export settings, and metadata.
- Real Settings window for backend and generation defaults.
- Standard macOS keyboard shortcuts for common actions.

Current implementation note:

- The core data model supports Projects, Scripts, and Batches separately from History.
- The main window now uses a native source-list sidebar for Projects, Scripts, Batches, Outputs, Voices, Presets, History, Backends, and Settings.
- History sessions remain selectable beneath History so existing session detail, playback, duplicate, and folder actions continue to work.
- Outputs has its own browser for archived WAV files, with in-app playback, Finder reveal, Quick Look, path copy, drag-out support, and duplicate-as-new.
- The Settings sidebar destination opens toward the native Settings scene instead of replacing preferences with an in-window settings clone.

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

Current implementation:

- The editor surface now stays focused on text, text metrics, and Generate.
- The right-side inspector exposes voice, model, inference, export, and contextual metadata controls.
- Inspector visibility is a window-scoped preference and can be toggled from the toolbar.
- The Batches destination exposes queued, running, completed, failed, and cancelled jobs with row-level cancel, retry, and duplicate actions.

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
- Running queue rows show elapsed time, parsed progress when available, estimated remaining time when available, and the session identifier once created.

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
- Generated audio can be dragged out of the output browser.
- Quick Look is available from output rows and details through the native macOS preview panel.
