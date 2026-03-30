# Pattern drafts and active-pattern switching

This document describes how **working state** (auto-saved drafts) stays aligned with the **correct pattern** when the user switches patterns, opens the library, or returns to the projects list. It complements [OFFLINE_AUTO_SAVE.md](../OFFLINE_AUTO_SAVE.md).

## Problem

- **`TableState`**, **`PlaybackState`**, and **`SampleBankState`** are provided **above** the sequencer and are **shared** across the app.
- Only one logical grid exists in memory at a time.
- **`PatternsState.activePattern`** can change **before** the next `SequencerScreenV2` finishes loading the next pattern’s snapshot.
- If auto-save always wrote under **`activePattern.id`** without coordination, a debounced save could persist **pattern B’s id** while the grid still reflected **pattern A**, or the opposite—corrupting `working_states/<pattern_id>.json` and making **projects list previews** look like empty “new” patterns.

## Solution overview

1. **Pre-switch flush**  
   When **`PatternsState.setActivePattern`** is called with a **different** pattern id, it **awaits** all registered **before-switch** listeners **before** updating **`_activePattern`**. Each mounted **`SequencerScreenV2`** registers a listener that exports the current shared sequencer state and writes it to **`working_states/<outgoing_pattern_id>.json`** while **`activePattern`** still refers to that session.

2. **Loaded pattern id**  
   Each **`SequencerScreenV2`** instance records **`_loadedPatternId`** after bootstrap (the pattern that screen opened for). Debounced and dispose-time saves only run when **`activePattern?.id == _loadedPatternId`**, and the snapshot is saved under **`_loadedPatternId`** via **`_saveWorkingStateForPatternId`**.

3. **Suppress after handoff**  
   After a successful pre-switch flush, the instance sets **`_suppressAutoSave`** so it does not write again while the shared table is about to belong to another pattern or route.

4. **Timestamps**  
   **`PatternsState.updatePatternTimestampForId(patternId)`** updates **`updatedAt`** for the pattern file that was actually saved (not only when it matches **`activePattern`** in edge cases).

## API surface

| Location | Responsibility |
|----------|----------------|
| **`PatternsState.addBeforeActivePatternSwitchListener` / `removeBeforeActivePatternSwitchListener`** | Registry of flush callbacks; **`setActivePattern`** copies the list and awaits each callback before changing the active id. |
| **`PatternsState.setActivePattern`** | If the new id equals the current one, only ensures checkpoints are loaded; otherwise runs listeners, then assigns **`_activePattern`**. |
| **`SequencerScreenV2._onBeforeActivePatternSwitch`** | Cancels debounce timer, calls **`_saveWorkingStateForPatternId`**, sets **`_suppressAutoSave`** on success. |
| **`SequencerScreenV2._performAutoSave`** | No-op if **`_suppressAutoSave`**, bootstrap incomplete, or **`activePattern?.id != _loadedPatternId`**. |

## Projects list preview

**`ProjectsScreen._getProjectSnapshot`** resolves thumbnails in order:

1. **Working state** file for that pattern id (draft), if present.  
2. Else **latest checkpoint** snapshot (checkpoints are sorted newest-first when loaded).  
3. Else a **minimal empty** snapshot used only for layout.

This avoids tiles that look like blank new projects when a checkpoint exists but no draft file was written yet.

## Opening the sequencer from Library vs Projects

Both flows should pass a **checkpoint fallback** into **`PatternScreen(initialSnapshot: …)`** when **`WorkingStateCacheService`** has no draft, so bootstrap does not leave stale shared table data with nothing to import. **Projects** and **Library** both resolve **`fallbackSnapshot`** from **`patternsState.getCheckpoints(pattern.id)`** (after **`setActivePattern`**, which loads checkpoints if needed).

## Key files

- `app/lib/state/patterns_state.dart` — listeners, **`setActivePattern`**, **`updatePatternTimestampForId`**
- `app/lib/screens/sequencer_screen_v2.dart` — registration, **`_loadedPatternId`**, flush, **`_performAutoSave`**
- `app/lib/screens/projects_screen.dart` — preview resolution, **`_getProjectSnapshot`**
- `app/lib/screens/library_screen.dart` — **`PatternScreen(initialSnapshot: fallbackSnapshot)`**
- `app/lib/services/cache/working_state_cache_service.dart` — on-disk draft storage

## Related

- [OFFLINE_AUTO_SAVE.md](../OFFLINE_AUTO_SAVE.md) — debounce, back/background save, storage layout  
- [working_state_auto_save.md](./sequencer/working_state_auto_save.md) — older milestone doc (threads-era); prefer this file and **OFFLINE_AUTO_SAVE** for current behavior  
