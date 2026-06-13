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
