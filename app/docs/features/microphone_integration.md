# Microphone Integration (Hidden Feature)

## Overview

Microphone integration is currently hidden behind a feature flag while integration issues are being resolved.

Current implementation remains in-place and is intentionally preserved:

- Pattern playback always comes from SunVox (`sv_audio_callback`).
- Microphone capture is handled by native iOS (`AVAudioEngine` tap + ring buffer).
- During recording:
  - Mic OFF -> record pattern playback only.
  - Mic ON -> record file mix (`pattern + mic`).
- Speaker output remains pattern playback only (no live mic monitor).
- After stop, recorded WAV is auto-loaded into sample slot `25`, then auto-triggered on the dedicated recording layer for live sequencer playback.

This document reflects only the active approach, not historical debugging logs.

Feature flag (default OFF):

- `lib/config/feature_flags.dart`
- `enableMicrophoneIntegration = false`

When this flag is OFF:

- Sequencer layer settings do not show the `SEQUENCE/REC` switch.
- UI stays in sequence-only interaction mode.
- Microphone and recording code remains compiled and available for future re-enable.

---

## Button Model

- Pattern record and microphone enable are separate controls.
- Pattern record does not auto-start playback.
- Pattern record does not auto-enable microphone.
- If playback is stopped, pattern record asks the user to start playback first.
- Recorded takes are auto-routed to a dedicated recording layer (last layer), not mixed into arbitrary user layer placement.

---

## Audio Paths

### 1) Speaker path (always stable)

`sv_audio_callback(...) -> pOutput -> speakers`

- Mic is not added to speaker output.
- This avoids live monitoring feedback and keeps playback quality predictable.

### 2) Recording file path (WAV)

When recording is active:

- Mic OFF: write `pOutput` to WAV (pattern only).
- Mic ON: read mic frames and write `pOutput + mic` mix to WAV.

Mixing is done only for file writing, not speaker rendering.

### 3) Post-recording path

- WAV is auto-loaded into sample slot `25`.
- Pattern cell is placed on the dedicated recording layer (last layer) at section start.
- Existing cells at section start on that dedicated layer are cleared before placement so latest take replaces previous take trigger.
- Slot `25` then plays through regular sequencer playback (live arrangement playback), independent of MP3 conversion.

---

## iOS Session Strategy

Current iOS strategy in native code:

- Use `PlayAndRecord` with:
  - `MixWithOthers`
  - `DefaultToSpeaker`
- Pre-initialize mic engine in playback init (`mic_input_init`) to reduce first-use lag.
- On mic start, code prefers wired mic classes (`HeadsetMic`, `USBAudio`, `LineIn`) when connected; otherwise built-in mic (`setPreferredInput`), with graceful fallback.

Why:

- `DefaultToSpeaker` prevents very quiet receiver routing in record mode.
- Wired-first, built-in-second preference is the active path for input selection.
- Minimal extra session churn keeps record-start lag lower.

---

## Wired Input Behavior (Current)

- Wired-capable inputs (`HeadsetMic`, `USBAudio`, `LineIn`) are treated as wired in native selection logic.
- Current active route is used to resolve selected input UID/name for UI state, reducing stale INPUT state.
- Multitask INPUT label should show wired state (`IN:WIRED`) when a wired source is selected.

What currently works reliably:

- Built-in mic recording.
- Pattern playback + mic mixed WAV recording.
- No live mic monitoring to speaker output path.
- WAV auto-load to slot `25` and live sequencer playback trigger.

---

## Waveform Rows (UI)

- Existing waveform rows remain compatible.
- Waveform capture flow is unchanged and still tied to recording state.
- No waveform rendering rewrite is required for this approach.

---

## File Map

- `native/playback_sunvox.mm` - playback callback + recording-file mix logic
- `native/microphone_input.mm` - AVAudioEngine mic capture + input preference/session handling
- `native/recording.mm` - WAV encoder write path
- `lib/state/sequencer/recording.dart` - recording lifecycle, WAV auto-load to slot `25`, pattern placement
- `lib/state/sequencer/microphone.dart` - mic enable/disable state and native calls
- `lib/widgets/sequencer/v2/line_mic_waveform_widget.dart` - waveform row rendering
- `lib/state/sequencer/recording_waveform.dart` - waveform capture state

---

## Quick Verification

- Default hidden behavior (`enableMicrophoneIntegration = false`):
  - Layer settings show sequence-only UI.
  - `SEQUENCE/REC` selector is not visible.

- Re-enable behavior (`enableMicrophoneIntegration = true`):
  - Layer settings show `SEQUENCE/REC` selector again.
  - `REC` mode can be selected and microphone controls become visible for recording layers.

- Play only: sample volume/quality unchanged.
- Pattern record + mic OFF: resulting WAV contains pattern only.
- Pattern record + mic ON: resulting WAV contains pattern + mic (built-in and wired paths).
- No live mic monitor heard from speaker path.
- Recorded WAV auto-loads to slot `25` and auto-plays via dedicated recording layer trigger in sequencer.

---

## Build

```bash
cd /Users/romansmirnov/projects/rehorsed/app
./run-ios.sh stage device "" ""
```

---

## Re-enable Process

1. Open `lib/config/feature_flags.dart`.
2. Set `enableMicrophoneIntegration` to `true`.
3. Rebuild app.
4. Verify the `SEQUENCE/REC` layer switch appears in layer settings.
5. Run microphone recording smoke test from the Quick Verification section.

---

Last Updated: 2026-03-10
