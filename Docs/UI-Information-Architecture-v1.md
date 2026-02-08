# PhotoTime UI Information Architecture v1

## Goal
Freeze UI skeleton before visual redesign, based on stable render/export behavior.

## Primary Flow
1. Import assets
2. Tune settings
3. Preview frame/timeline
4. Export
5. Recover from failure or finish

## Top-Level Regions
- `A. Asset Panel`
- `B. Preview Panel`
- `C. Settings Panel`
- `D. Export Panel`
- `E. Diagnostics Panel`

## Region Responsibilities

### A. Asset Panel
- Show selected assets (name, count)
- Show failed assets after export failure
- Actions:
  - Select assets
  - Reselect failed assets

### B. Preview Panel
- Show current frame preview
- Show timeline slider with time label
- States:
  - idle (preview available)
  - previewing (loading indicator)
  - failed (error message + recovery action)
- Actions:
  - Generate preview
  - Seek timeline (throttled)

### C. Settings Panel
- Group fields:
  - Output: width/height/fps
  - Timing: image duration/transition duration
  - Motion: Ken Burns
  - Performance: prefetch radius/max concurrent
- Rules:
  - Bind to single source `RenderEditorConfig`
  - Invalid config shows inline validation

### D. Export Panel
- Core actions:
  - Export MP4
  - Cancel export
  - Retry last export
- Progress:
  - progress bar only for `exporting/cancelling`
- Enable/disable driven by workflow state machine

### E. Diagnostics Panel
- Always-visible status text from workflow
- On failure, must include:
  - error code
  - recovery action
  - suggestion
  - log path

## Workflow State Mapping

### `idle`
- Enable: import assets, import/export template, preview, export
- Disable: cancel

### `previewing`
- Disable all write operations
- Show preview loading status

### `exporting`
- Enable: cancel only
- Show progress

### `cancelling`
- Disable new operations
- Keep progress visible

### `succeeded`
- Enable: new export / preview / template actions
- Show output filename + log path

### `failed`
- Enable: retry, reselect assets, adjust settings
- Show diagnostics and recovery action

## Must-Have UI Interactions Before Visual Redesign
1. State-driven button availability (no ad-hoc booleans)
2. Inline validation from `RenderEditorConfig.invalidMessage`
3. Failure card (failed assets + recovery action + log)
4. Preview loading/failure states
5. Export completion card (output + log)

## Out of Scope (Postpone)
- Multi-task queue UI
- Complex template library management
- Theme/polish animations
