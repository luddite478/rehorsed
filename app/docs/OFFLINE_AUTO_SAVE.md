# Offline Auto-Save System

## Overview

Implemented a fully local auto-save system for the offline-only Flutter app. This system automatically saves your work every 5 seconds after you stop editing, ensuring you never lose progress even if the app crashes.

## Features

✅ **Automatic Saving**
- Auto-saves pattern state 5 seconds after last edit
- Debounced to avoid excessive saves during active editing
- Works completely offline (no server required)
- **Save requested when pressing back / switching pattern / app lifecycle changes**
- **Single serialized save gate prevents overlapping writes**
- **If exit-time save can't be confirmed immediately, background retry is scheduled**

✅ **Crash Recovery**
- Survives app crashes and force quits
- Loads most recent working state when reopening a pattern
- Persists across app restarts
- Never lose work, even with quick edits and immediate navigation

✅ **Pattern Timestamp Updates**
- Updates pattern's `updatedAt` timestamp on auto-save
- Patterns appear in correct order on projects screen
- Shows recently edited patterns at the top

✅ **Seamless Integration**
- Transparent background operation
- No UI changes or user interaction required
- Zero friction - just like Google Docs

## How It Works

### Auto-Save Flow

**Normal Auto-Save (Debounced)**
```
User makes changes (edit cells, change BPM, load samples)
    ↓
State change listener triggered
    ↓
Auto-save timer scheduled (5 seconds, debounced)
    ↓
If no changes in 5 seconds:
    → Export sequencer snapshot
    → Save to latest_states/<pattern_id>.json
    → Update pattern's updatedAt timestamp
    ↓
Working state persisted
```

**Exit Save (No Debounce)**
```
User presses back OR app goes background/detached OR pattern switches
    ↓
Cancel any pending auto-save timer
    ↓
Request save through the same queued save gate
    → Export snapshot (bounded retries + structure validation)
    → Atomic write to latest_states/<pattern_id>.json
    → Update pattern's updatedAt timestamp
    ↓
If not confirmed in time:
    → Continue navigation/lifecycle
    → Retry in background (bounded attempts)
```

### Loading Flow

Sequencer bootstrap now uses a **single restore source**:

1. Load `latest_states/<pattern_id>.json`.
2. Validate structure (`SnapshotTableValidator`) and import.
3. If invalid/corrupt, clear latest-state file and continue with empty/default native state.

`PatternScreen(initialSnapshot: ...)` is treated as an explicit snapshot input only
(for dedicated take/revision entry flows), not as default checkpoint fallback for
normal project open.

### Pattern Creation Flow

```
User taps "+" button
    ↓
Create new Pattern object with generated name
    ↓
Set as active pattern in PatternsState
    ↓
Navigate to sequencer
    ↓
User makes changes → Auto-save activates
```

### Pattern switch coordination (shared sequencer state)

`TableState` / playback / sample bank are **shared** Provider state. Changing **`PatternsState.activePattern`** (e.g. opening another pattern from the Library) **before** the next sequencer import could previously save the wrong snapshot under the wrong **`pattern_id`**, or leave list previews inconsistent.

**Behavior now:**

1. **`PatternsState.setActivePattern`** — If the new pattern id **differs** from the current one, **all** **`addBeforeActivePatternSwitchListener`** callbacks run **first** (awaited). Each **`SequencerScreenV2`** flushes the current grid to **`latest_states/<outgoing_id>.json`** while **`activePattern`** still matches that session.
2. **`SequencerScreenV2`** tracks **`_loadedPatternId`** for this route instance. Auto-save and dispose-time save only run when **`activePattern?.id == _loadedPatternId`**, and writes use **`updatePatternTimestampForId(patternId)`** for the saved id.
3. After a successful pre-switch flush, the screen sets **`_suppressAutoSave`** so it does not write again after the shared table belongs to another pattern.

Full detail: [features/patterns_draft_and_switching.md](./features/patterns_draft_and_switching.md).

### Projects list preview (latest state vs checkpoint)

For each tile, the snapshot used for the mini preview is resolved as:

1. **Latest autosave** — `WorkingStateCacheService.loadWorkingState` reads `latest_states/` (and migrates legacy `working_states/` once), if present.  
2. Otherwise **latest recording checkpoint** snapshot (newest-first).  
3. Otherwise an empty template.

Opening from **Projects** and **Library** now uses `PatternScreen()` without
checkpoint fallback. Normal restore always comes from latest-state autosave.

**Export:** Before returning JSON, `SnapshotExporter` now:
- syncs table state for serialization
- validates `sections_count` consistency with native table state
- validates table structure (`SnapshotTableValidator`)
- retries export in a bounded loop and aborts write on persistent mismatch

### Multi-section reliability status

The save pipeline is now hardened against stale/truncated multi-section exports:

1. **Queued saves only** — all triggers share one save gate to avoid overlapping writes.
2. **Export validation before persist** — mismatched `sections_count` or invalid table shape causes bounded re-export attempts.
3. **No destructive overwrite on failed export** — if retries fail, latest-state file is not replaced.
4. **Atomic file writes** — latest-state writes use temp-file swap to avoid partial JSON.

If a reopen still shows only one section, inspect `cache/latest_states/<pattern_id>.json` and confirm:
- `snapshot.source.table.sections_count`
- `snapshot.source.table.sections.length`
- `snapshot.source.table.table_cells.length`

## Implementation Details

### Files Modified

1. **`lib/services/cache/working_state_cache_service.dart`**
   - Updated to use `patternId` instead of `threadId`
   - Manages local JSON storage of latest states
   - Stores in `latest_states/` and migrates legacy files from `working_states/` on first load
   - Provides save/load/clear APIs and `loadWorkingStateEnvelope`

2. **`lib/services/snapshot/export.dart`**
   - Retries export in bounded attempts
   - Validates native/exported section count consistency
   - Validates exported table structure before returning JSON

3. **`lib/services/snapshot/snapshot_table_validator.dart`**
   - Structural validation for `source.table` before import

4. **`lib/screens/sequencer_screen_v2.dart`**
   - Auto-save timer and listeners on TableState, PlaybackState, SampleBankState
   - Single queued `requestSave(reason)` pipeline for debounce/back/lifecycle/switch/dispose
   - Soft-timeout exit behavior with bounded background retry
   - Registers **`addBeforeActivePatternSwitchListener`**; tracks **`_loadedPatternId`**, **`_suppressAutoSave`**
   - **`_saveWorkingStateForPatternId`** with guarded writes for loaded pattern id
   - **`_loadLatestStateForActivePattern`** on bootstrap
   - Cleans up listeners and **`removeBeforeActivePatternSwitchListener`** on dispose

5. **`lib/state/patterns_state.dart`**
   - `updatePatternTimestamp()` / `updatePatternTimestampForId()` for `updatedAt` after saves
   - `addBeforeActivePatternSwitchListener` / `removeBeforeActivePatternSwitchListener`
   - `setActivePattern` awaits pre-switch listeners when the active id changes (flush outgoing draft)
   - Removed duplicate autosave timer logic (sequencer is sole autosave orchestrator)
   - Ensures patterns show in correct order on projects screen

6. **`lib/screens/projects_screen.dart`**
   - Creates actual Pattern object when user taps "+"
   - Sets pattern as active before navigating to sequencer
   - Uses PatternNameGenerator for default names
   - Pattern tile preview: working state, else latest checkpoint, else empty template

7. **`lib/screens/library_screen.dart`**
   - Opens `PatternScreen()` directly (no checkpoint fallback)

### Key Components

#### Auto-Save Listeners

```dart
// Set up listeners in initState
_tableState.addListener(_onSequencerStateChanged);
_playbackState.addListener(_onSequencerStateChanged);
_sampleBankState.addListener(_onSequencerStateChanged);

// Debounced trigger into single queued save pipeline
void _onSequencerStateChanged() {
  _autoSaveTimer?.cancel();
  _autoSaveTimer = Timer(_autoSaveDelay, () {
    _requestSave(reason: SaveReason.debounce);
  });
}
```

#### Auto-Save Execution

Saves target the **pattern this screen instance loaded** (`_loadedPatternId`), not merely whatever `activePattern` is at timer fire (guards stacked routes / id races). Pre-switch flush uses the same helper.

```dart
Future<bool> _saveWorkingStateForPatternId(String patternId) async {
  final snapshotService = SnapshotService(...);
  final snapshotJson = snapshotService.exportToJson(...); // throws on invalid export after retries
  final saved = await WorkingStateCacheService.saveWorkingState(
    patternId,
    json.decode(snapshotJson) as Map<String, dynamic>,
  );
  if (!saved) return false;
  await patternsState.updatePatternTimestampForId(patternId);
  return true;
}
```

#### Working State Loading

```dart
// Check for working state on load
final workingState = await WorkingStateCacheService.loadWorkingState(
  activePattern.id
);

if (workingState != null) {
  // Load most recent auto-saved state
  await service.importFromJson(json.encode(workingState));
}
```

## Storage

- **Location**: `cache/latest_states/<pattern_id>.json`
- **Format**: JSON with version, pattern_id, saved_at, snapshot
- **Size**: ~50-500 KB per pattern (depending on complexity)
- **Persistence**: Survives app restarts, cleared manually
- **Migration**: old `cache/working_states/` files are migrated on first load

## Configuration

```dart
// Auto-save delay (in sequencer_screen_v2.dart)
static const _autoSaveDelay = Duration(seconds: 5);
```

## Usage

### For Users

1. **Create a new pattern** - Tap the "+" button on projects screen
2. **Make changes** - Edit cells, change BPM, load samples, etc.
3. **Auto-save happens automatically**:
   - Wait 5 seconds after last edit → Auto-save triggers
   - Press back button / switch pattern / app lifecycle change → save is requested immediately
   - If save cannot be confirmed fast enough during exit, app proceeds and retries save in background
4. **Go back to projects** - Pattern shows with updated timestamp
5. **Reopen pattern** - Your latest changes are loaded automatically

**Exit path is best-effort + bounded retry, without blocking navigation.**

### For Developers

```dart
// Check if working state exists
final hasWorkingState = await WorkingStateCacheService.hasWorkingState(patternId);

// Get working state timestamp
final savedAt = await WorkingStateCacheService.getWorkingStateTimestamp(patternId);

// Clear working state (e.g., after saving checkpoint)
await WorkingStateCacheService.clearWorkingState(patternId);

// Get all patterns with working states
final patterns = await WorkingStateCacheService.getPatternsWithWorkingStates();

// Get storage statistics
final stats = await WorkingStateCacheService.getWorkingStateStats();
```

## Benefits

✅ **Never lose work** - Auto-saves every 5 seconds  
✅ **Crash recovery** - Survives app crashes and force quits  
✅ **Offline-first** - No network required, fully local  
✅ **Seamless UX** - Transparent, no UI changes needed  
✅ **Pattern ordering** - Recently edited patterns show at top  
✅ **Low overhead** - Minimal performance impact  

## Debugging

All auto-save operations are logged:

```
💾 [WORKING_STATE] Saved working state for pattern abc123
📝 [WORKING_STATE] Loaded working state for pattern abc123 (saved: 2026-01-11T...)
⏰ [PATTERNS_STATE] Updated pattern timestamp: abc123
💾 Auto-saved pattern My Pattern
```

## Future Enhancements

- [ ] Show "Last auto-saved: X minutes ago" in UI
- [ ] Option to manually trigger save
- [ ] Working state history (keep last 3 auto-saves)
- [x] Conflict resolution if checkpoint is newer than working state (recency + validation in sequencer bootstrap)
- [ ] Storage management UI (view/clear working states)

## Conclusion

The offline auto-save system provides Google Docs-style automatic saving for your music patterns. Work is saved automatically every 5 seconds, patterns show in the correct order on the projects screen, and everything persists across app restarts and crashes.

**Status**: ✅ Fully implemented and tested
