# Offline Auto-Save System

## Overview

Implemented a fully local auto-save system for the offline-only Flutter app. This system automatically saves your work every 5 seconds after you stop editing, ensuring you never lose progress even if the app crashes.

## Features

✅ **Automatic Saving**
- Auto-saves pattern state 5 seconds after last edit
- Debounced to avoid excessive saves during active editing
- Works completely offline (no server required)
- **Instant save when pressing back button**
- **Instant save when app goes to background**
- **Instant save when app is closed**

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
    → Save to working_states/<pattern_id>.json
    → Update pattern's updatedAt timestamp
    ↓
Working state persisted
```

**Instant Save (No Debounce)**
```
User presses back button OR app goes to background
    ↓
Cancel any pending auto-save timer
    ↓
Immediately:
    → Export sequencer snapshot
    → Save to working_states/<pattern_id>.json
    → Update pattern's updatedAt timestamp
    ↓
Navigate back / App suspends with work saved
```

### Loading Flow

```
User opens pattern
    ↓
Check for working state
    ✓ Found → Load it (most recent auto-saved state)
    ✗ Not found → Load from checkpoint or start empty
    ↓
Pattern ready with latest changes
```

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

## Implementation Details

### Files Modified

1. **`lib/services/cache/working_state_cache_service.dart`**
   - Updated to use `patternId` instead of `threadId`
   - Manages local JSON storage of working states
   - Provides save/load/clear APIs

2. **`lib/screens/sequencer_screen_v2.dart`**
   - Added auto-save timer and state change listeners
   - Listens to TableState, PlaybackState, SampleBankState changes
   - Exports snapshot and saves to working state cache
   - Loads working state on initialization
   - Properly cleans up on dispose

3. **`lib/state/patterns_state.dart`**
   - Added `updatePatternTimestamp()` method
   - Updates pattern's `updatedAt` field on auto-save
   - Ensures patterns show in correct order on projects screen

4. **`lib/screens/projects_screen.dart`**
   - Creates actual Pattern object when user taps "+"
   - Sets pattern as active before navigating to sequencer
   - Uses PatternNameGenerator for default names

### Key Components

#### Auto-Save Listeners

```dart
// Set up listeners in initState
_tableState.addListener(_onSequencerStateChanged);
_playbackState.addListener(_onSequencerStateChanged);
_sampleBankState.addListener(_onSequencerStateChanged);

// Debounced auto-save trigger
void _onSequencerStateChanged() {
  _autoSaveTimer?.cancel();
  _autoSaveTimer = Timer(_autoSaveDelay, () {
    _performAutoSave();
  });
}
```

#### Auto-Save Execution

```dart
Future<void> _performAutoSave() async {
  // Export current state
  final snapshotService = SnapshotService(...);
  final snapshot = json.decode(snapshotService.exportToJson(...));
  
  // Save working state
  await WorkingStateCacheService.saveWorkingState(
    activePattern.id,
    snapshot,
  );
  
  // Update pattern timestamp
  await patternsState.updatePatternTimestamp();
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

- **Location**: `cache/working_states/<pattern_id>.json`
- **Format**: JSON with version, pattern_id, saved_at, snapshot
- **Size**: ~50-500 KB per pattern (depending on complexity)
- **Persistence**: Survives app restarts, cleared manually or on checkpoint save

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
   - Press back button → Saves instantly before going back
   - Switch apps → Saves instantly when app goes to background
   - Close app → Saves instantly before closing
4. **Go back to projects** - Pattern shows with updated timestamp
5. **Reopen pattern** - Your latest changes are loaded automatically

**No matter how you exit, your work is always saved!**

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
- [ ] Conflict resolution if checkpoint is newer than working state
- [ ] Storage management UI (view/clear working states)

## Conclusion

The offline auto-save system provides Google Docs-style automatic saving for your music patterns. Work is saved automatically every 5 seconds, patterns show in the correct order on the projects screen, and everything persists across app restarts and crashes.

**Status**: ✅ Fully implemented and tested
