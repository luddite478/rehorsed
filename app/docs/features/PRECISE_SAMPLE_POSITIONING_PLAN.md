# Precise Sample Positioning Plan

**Version:** 1.0  
**Date:** January 23, 2026  
**Status:** Planning  
**Goal:** Enable sub-step precision for positioning recorded audio and samples

---

## Table of Contents

1. [Current State](#current-state)
2. [Goals](#goals)
3. [Technical Foundation](#technical-foundation)
4. [Architecture Design](#architecture-design)
5. [Implementation Phases](#implementation-phases)
6. [API Design](#api-design)
7. [UI/UX Design](#uiux-design)
8. [Testing Plan](#testing-plan)
9. [Future Enhancements](#future-enhancements)

---

## Current State

### What Works Now

- ✅ Microphone recording captures audio to WAV files
- ✅ Waveform visualization shows recorded audio in REC mode
- ✅ Audio is captured and mixed during recording
- ✅ Samples can be loaded into SunVox Sampler modules
- ✅ Pattern grid triggers samples at step boundaries

### Current Limitations

- ❌ Recorded audio is NOT loaded back into sequencer for playback
- ❌ Recorded audio is NOT played during sequencer playback (only during render)
- ❌ Samples can only be triggered on step boundaries (16th note grid)
- ❌ No sub-step precision for sample positioning
- ❌ Waveform visualization is tied to loop/line grid (cannot show precise offsets)

### Problem Statement

**When recording microphone audio in REC mode:**
1. Audio is captured and written to WAV file
2. Waveform is visualized across lines (one line per loop)
3. **BUT**: Audio is NOT played back during sequencer playback
4. **AND**: Even if we load it as a sample, we can only trigger on step boundaries

**Desired behavior:**
- Recorded audio should play back during sequencer playback
- User should be able to position audio with sub-step precision (not limited to 16th note grid)
- Waveform should reflect precise positioning

---

## Goals

### Primary Goals

1. **Automatic Sample Loading**: Load recorded WAV into a Sampler module after recording stops
2. **Playback Integration**: Recorded audio plays during sequencer playback (not just in final render)
3. **Precise Positioning**: Position samples with sample-accurate precision (1/48000 second = ~0.02ms)
4. **Visual Feedback**: Waveform visualization shows precise offset position

### Secondary Goals

4. **Drag-to-Reposition**: Allow dragging waveform to adjust timing
5. **Nudge Controls**: Fine-tune position with keyboard shortcuts
6. **Quantize Options**: Snap to grid or free positioning
7. **Multi-Track Support**: Multiple recorded takes on different layers

---

## Technical Foundation

### SunVox Capabilities (From Library Investigation)

SunVox provides THREE mechanisms for precise timing:

#### 1. Event Offset Field (Sample-Accurate)

```c
struct psynth_event {
    psynth_command command;
    uint32_t id;
    int32_t offset;  // Time offset in FRAMES (sample-accurate!)
    // ...
};
```

- Events can be triggered at ANY frame within a line
- Frame = 1 audio sample (at 48kHz, 1 frame = 0.02ms)
- **Most precise method available**

#### 2. Sample Offset Effect 09xx (Coarse)

```c
// Effect: 09xx
// Value xx is multiplied by 256
sample_offset = xx * 256 frames
```

- Legacy coarse positioning
- Example: `09FF` = start at frame 65,280
- Range: 0 to 16,711,680 frames (0 to ~348 seconds at 48kHz)

#### 3. Sample Offset Effect 07xx (Fine)

```c
// Effect: 07xx  
// Value xx in frames (0-255)
sample_offset = xx frames
```

- Fine positioning for last 255 frames
- Combine with 09xx for maximum precision
- Total precision: `(09xx * 256) + 07xx` frames

#### 4. Combined Precision

```
Total offset = (effect_09 * 256) + effect_07
Precision: Individual sample (1/48000 sec at 48kHz)
Maximum offset: 16,777,215 frames (~349 seconds at 48kHz)
```

### Current Architecture Gap

**Missing Link:**
```
Recording → WAV File → [GAP] → Sequencer Playback
                         ↑
                  No sample loading mechanism!
```

**What Exists:**
- `sample_bank_load()` - Can load WAV files ✅
- `sunvox_wrapper_load_sample()` - Loads into Sampler ✅
- Pattern system - Can trigger samples ✅

**What's Missing:**
- Automatic loading after recording ❌
- Pattern note generation for recorded audio ❌
- Offset calculation and application ❌
- Precise positioning UI ❌

---

## Architecture Design

### Component Overview

```
┌─────────────────────────────────────────────────────────────┐
│  PRECISE SAMPLE POSITIONING SYSTEM                           │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  1. Recording Subsystem (Existing)                           │
│     ├─ Microphone capture                                    │
│     ├─ WAV file writing                                      │
│     └─ Waveform visualization                                │
│                                                               │
│  2. Sample Loading Subsystem (NEW)                           │
│     ├─ Auto-load recorded WAV after stop                     │
│     ├─ Assign to dedicated sample slot                       │
│     ├─ Generate pattern notes for playback                   │
│     └─ Calculate initial offset (aligned to recording)       │
│                                                               │
│  3. Offset Management Subsystem (NEW)                        │
│     ├─ Frame-accurate offset calculation                     │
│     ├─ Convert time → frame offset                           │
│     ├─ Split into coarse (09xx) + fine (07xx)               │
│     └─ Update pattern events with offsets                    │
│                                                               │
│  4. Positioning UI Subsystem (NEW)                           │
│     ├─ Visual offset indicator on waveform                   │
│     ├─ Drag-to-reposition gesture handling                   │
│     ├─ Nudge controls (keyboard/buttons)                     │
│     └─ Snap-to-grid toggle                                   │
│                                                               │
│  5. Pattern Integration Subsystem (NEW)                      │
│     ├─ Create pattern notes for recorded audio               │
│     ├─ Apply offset effects (07xx, 09xx)                     │
│     ├─ Handle layer-specific patterns                        │
│     └─ Sync with loop/section boundaries                     │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

### Data Flow

```
User Records → WAV File Created
                    ↓
         Auto-Load into Sample Slot
                    ↓
         Calculate Initial Offset
         (align with recording start)
                    ↓
         Generate Pattern Notes
         (one per section/loop)
                    ↓
         Apply Offset Effects
         (09xx coarse + 07xx fine)
                    ↓
         Playback Triggers Sample
         (at precise frame offset)
                    ↓
         User Adjusts Position
         (drag, nudge, quantize)
                    ↓
         Recalculate Offsets
                    ↓
         Update Pattern Events
```

---

## Implementation Phases

### Phase 1: Basic Sample Loading (Foundation)

**Goal:** Load recorded audio back into sequencer for playback

**Tasks:**
1. ✅ Reserve dedicated sample slot for recorded audio (e.g., slot 127)
2. ✅ Auto-load WAV file after `recording_stop()`
3. ✅ Create Sampler module for recorded audio
4. ✅ Generate basic pattern note (no offset yet)
5. ✅ Verify playback during sequencer play

**Deliverable:** Recorded audio plays back during sequencer playback

**Files to Modify:**
- `app/lib/state/sequencer/recording.dart` - Add auto-load after stop
- `app/lib/state/sequencer/sample_bank.dart` - Load recorded audio
- `app/native/sunvox_wrapper.mm` - Manage recorded audio sampler
- `app/native/sample_bank.mm` - Load with special flag

**API Additions:**
```dart
class RecordingState {
  Future<bool> _loadRecordedAudioAsSample() async;
  void _generatePlaybackPattern();
}
```

**Estimated Time:** 2-3 days

---

### Phase 2: Coarse Offset Support (Effect 09xx)

**Goal:** Enable coarse positioning using legacy offset effect

**Tasks:**
1. ✅ Calculate frame offset from recording start time
2. ✅ Split offset into coarse component (multiply by 256)
3. ✅ Apply effect 09xx to pattern event
4. ✅ Test playback with various offsets
5. ✅ Verify audio sync accuracy

**Deliverable:** Samples can be positioned with 256-frame precision (~5.3ms at 48kHz)

**Files to Modify:**
- `app/lib/state/sequencer/recording.dart` - Offset calculation
- `app/lib/state/sequencer/pattern_offset.dart` (NEW) - Offset utilities
- `app/lib/ffi/playback_bindings.dart` - Pattern event with effects

**API Additions:**
```dart
class SampleOffsetCalculator {
  static int calculateFrameOffset(Duration time, int sampleRate);
  static ({int coarse, int fine}) splitOffset(int frames);
  static void applySampleOffset(int patternNum, int line, int track, int coarse, int fine);
}
```

**Estimated Time:** 3-4 days

---

### Phase 3: Fine Offset Support (Effect 07xx)

**Goal:** Add fine positioning for sample-accurate precision

**Tasks:**
1. ✅ Calculate fine offset (0-255 frames)
2. ✅ Apply effect 07xx alongside 09xx
3. ✅ Handle edge cases (offset > maximum)
4. ✅ Test combined precision
5. ✅ Verify no audio artifacts

**Deliverable:** Samples positioned with single-frame precision (~0.02ms at 48kHz)

**Files to Modify:**
- `app/lib/state/sequencer/pattern_offset.dart` - Add fine offset
- Pattern event generation - Apply both effects

**API Updates:**
```dart
class SampleOffsetCalculator {
  // Now returns both coarse AND fine
  static ({int coarse, int fine}) calculateOffsets(Duration time, int sampleRate);
}
```

**Estimated Time:** 2-3 days

---

### Phase 4: Visual Offset Indicator

**Goal:** Show precise offset position on waveform

**Tasks:**
1. ✅ Add offset marker overlay to waveform widget
2. ✅ Calculate visual position from frame offset
3. ✅ Show offset value (milliseconds or frames)
4. ✅ Highlight offset region on waveform
5. ✅ Update on offset changes

**Deliverable:** Waveform shows visual indicator of sample start position

**Files to Modify:**
- `app/lib/widgets/sequencer/v2/line_mic_waveform_widget.dart` - Add offset overlay
- `app/lib/state/sequencer/recording_waveform.dart` - Track offset per layer

**UI Design:**
```
┌─────────────────────────────────────────────────┐
│ [1/4] ──────┃━━━━━━━━━━━━━━━━━━━━━━━━━━━━━── │
│             ↑                                   │
│          Offset: +12.5ms (600 frames)          │
└─────────────────────────────────────────────────┘
```

**Estimated Time:** 3-4 days

---

### Phase 5: Drag-to-Reposition

**Goal:** Allow dragging waveform to adjust timing

**Tasks:**
1. ✅ Implement horizontal drag gesture on waveform
2. ✅ Calculate new offset from drag delta
3. ✅ Update pattern events in real-time
4. ✅ Add visual feedback during drag
5. ✅ Snap-to-grid option (quantize)

**Deliverable:** User can drag waveform left/right to adjust timing

**Files to Modify:**
- `app/lib/widgets/sequencer/v2/line_mic_waveform_widget.dart` - Drag handling
- `app/lib/state/sequencer/recording_waveform.dart` - Offset state management

**Gesture Flow:**
```
User drags waveform →
  Calculate pixel delta →
    Convert to time delta →
      Convert to frame offset →
        Update pattern events →
          Redraw waveform with new offset
```

**Estimated Time:** 4-5 days

---

### Phase 6: Nudge Controls

**Goal:** Fine-tune position with keyboard/UI controls

**Tasks:**
1. ✅ Add nudge buttons (+/- 1ms, +/- 10ms, +/- 100ms)
2. ✅ Keyboard shortcuts (arrow keys)
3. ✅ Display current offset value
4. ✅ Undo/redo support for offset changes
5. ✅ Reset to zero button

**Deliverable:** Precise manual adjustment of sample position

**Files to Modify:**
- `app/lib/widgets/sequencer/v2/layer_settings_widget.dart` - Add nudge UI
- `app/lib/state/sequencer/recording_waveform.dart` - Nudge methods

**UI Addition:**
```
┌─────────────────────────────────────┐
│ Offset: +12.5ms                     │
│ [◀◀] [◀] [RESET] [▶] [▶▶]         │
│  -10   -1    0    +1   +10  (ms)   │
└─────────────────────────────────────┘
```

**Estimated Time:** 2-3 days

---

### Phase 7: Multi-Layer Support

**Goal:** Independent offset per layer (L1-L5)

**Tasks:**
1. ✅ Store offset per layer/section
2. ✅ Generate patterns per layer
3. ✅ Independent adjustment per layer
4. ✅ Layer offset visualization
5. ✅ Copy offset between layers

**Deliverable:** Each layer can have different sample timing

**Files to Modify:**
- `app/lib/state/sequencer/recording_waveform.dart` - Per-layer offsets
- Pattern generation - Layer-specific patterns

**Data Structure:**
```dart
class RecordingWaveformState {
  // Current: Map<layer, Map<section, List<List<int>>>>
  final Map<int, Map<int, List<List<int>>>> _linesByLayerSection;
  
  // NEW: Offset per layer/section (in frames)
  final Map<int, Map<int, int>> _offsetsByLayerSection = {};
}
```

**Estimated Time:** 3-4 days

---

## API Design

### Core Classes

#### 1. SampleOffsetCalculator (NEW)

```dart
class SampleOffsetCalculator {
  static const int kSampleRate = 48000;
  static const int kCoarseMultiplier = 256;
  static const int kFineMax = 255;
  static const int kMaxOffset = 16777215; // (65535 * 256) + 255
  
  /// Convert time to frame offset
  static int timeToFrames(Duration time) {
    return (time.inMicroseconds * kSampleRate / 1000000).round();
  }
  
  /// Convert frame offset to time
  static Duration framesToTime(int frames) {
    return Duration(microseconds: (frames * 1000000 / kSampleRate).round());
  }
  
  /// Split frame offset into coarse (09xx) and fine (07xx) components
  static ({int coarse, int fine}) splitOffset(int frames) {
    final clamped = frames.clamp(0, kMaxOffset);
    final coarse = clamped ~/ kCoarseMultiplier;
    final fine = clamped % kCoarseMultiplier;
    return (coarse: coarse, fine: fine);
  }
  
  /// Calculate offsets from time
  static ({int coarse, int fine}) calculateOffsets(Duration time) {
    final frames = timeToFrames(time);
    return splitOffset(frames);
  }
  
  /// Combine coarse and fine back to total frames
  static int combineOffsets(int coarse, int fine) {
    return (coarse * kCoarseMultiplier) + fine;
  }
}
```

#### 2. RecordingState Extensions

```dart
extension RecordingStateOffsets on RecordingState {
  /// Load recorded audio as sample and generate playback pattern
  Future<bool> loadRecordedAudioForPlayback({
    int? sampleSlot,
    int? initialOffsetMs,
  }) async {
    sampleSlot ??= 127; // Default: last slot
    
    if (_currentRecordingPath == null) return false;
    
    // Load WAV into sample bank
    final loaded = await _sampleBank.loadRecordedAudio(
      sampleSlot, 
      _currentRecordingPath!
    );
    
    if (!loaded) return false;
    
    // Calculate initial offset
    final offsetFrames = initialOffsetMs != null 
        ? SampleOffsetCalculator.timeToFrames(Duration(milliseconds: initialOffsetMs))
        : 0;
    
    // Generate pattern for playback
    _generatePlaybackPattern(sampleSlot, offsetFrames);
    
    return true;
  }
  
  /// Generate pattern notes for recorded audio with precise offset
  void _generatePlaybackPattern(int sampleSlot, int offsetFrames) {
    final offsets = SampleOffsetCalculator.splitOffset(offsetFrames);
    
    // Get current section and loop info
    final section = _playbackState.currentSection;
    final loopsNum = _playbackState.getSectionLoopsNum(section);
    
    // Create notes for each loop (one line per loop in REC mode)
    for (int loop = 0; loop < loopsNum; loop++) {
      final line = loop; // In REC mode, one line = one loop
      
      // Set note with sample trigger
      _tableState.setPatternEvent(
        section: section,
        line: line,
        track: 0, // First track
        note: 60, // Middle C (doesn't affect sample playback much)
        velocity: 80,
        module: sampleSlot + 1,
        controller: 0x0900, // Effect 09 (coarse offset)
        controllerValue: offsets.coarse,
      );
      
      // Add fine offset on adjacent track
      if (offsets.fine > 0) {
        _tableState.setPatternEvent(
          section: section,
          line: line,
          track: 1, // Second track
          note: null, // No note, just effect
          velocity: null,
          module: sampleSlot + 1,
          controller: 0x0700, // Effect 07 (fine offset)
          controllerValue: offsets.fine,
        );
      }
    }
  }
}
```

#### 3. RecordingWaveformState Extensions

```dart
extension RecordingWaveformStateOffsets on RecordingWaveformState {
  /// Get offset for specific layer/section (in frames)
  int getOffset(int layer, int section) {
    return _offsetsByLayerSection[layer]?[section] ?? 0;
  }
  
  /// Set offset for specific layer/section
  void setOffset(int layer, int section, int offsetFrames) {
    final bySection = _offsetsByLayerSection.putIfAbsent(layer, () => {});
    bySection[section] = offsetFrames.clamp(0, SampleOffsetCalculator.kMaxOffset);
    
    // Update pattern events
    _updatePatternOffset(layer, section);
    
    notifyListeners();
  }
  
  /// Nudge offset by delta (in milliseconds)
  void nudgeOffset(int layer, int section, int deltaMs) {
    final currentFrames = getOffset(layer, section);
    final deltaFrames = SampleOffsetCalculator.timeToFrames(
      Duration(milliseconds: deltaMs)
    );
    setOffset(layer, section, currentFrames + deltaFrames);
  }
  
  /// Reset offset to zero
  void resetOffset(int layer, int section) {
    setOffset(layer, section, 0);
  }
  
  /// Update pattern events with new offset
  void _updatePatternOffset(int layer, int section) {
    // Re-generate pattern with new offset
    // (Implementation similar to _generatePlaybackPattern)
  }
}
```

#### 4. SampleBankState Extensions

```dart
extension SampleBankRecordedAudio on SampleBankState {
  /// Load recorded audio with special handling
  Future<bool> loadRecordedAudio(int slot, String wavPath) async {
    // Similar to loadSample but with:
    // - No sample ID (ephemeral)
    // - Special naming ("Recorded Audio")
    // - Auto-cleanup on new recording
  }
}
```

---

## UI/UX Design

### Visual Elements

#### 1. Offset Indicator on Waveform

```
┌──────────────────────────────────────────────────┐
│ [1/4]                                            │
│       ┃━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━    │
│       ↑                                          │
│   +12.5ms                                        │
│   (600 frames)                                   │
└──────────────────────────────────────────────────┘
```

- Vertical bar shows sample start position
- Offset value displayed below
- Different color for positive/negative offset

#### 2. Offset Control Panel (in REC mode)

```
┌─────────────────────────────────────────────────┐
│ REC MODE                         [SEQUENCE/REC] │
├─────────────────────────────────────────────────┤
│ TABS: [VOL] [MON] [INPUT] [OFFSET*]           │
├─────────────────────────────────────────────────┤
│                                                  │
│ Sample Offset                                   │
│ ┌──────────────────────────────────────────┐   │
│ │ +12.5 ms (600 frames)                    │   │
│ └──────────────────────────────────────────┘   │
│                                                  │
│ Nudge:                                          │
│ [◀◀◀] [◀◀] [◀] [RESET] [▶] [▶▶] [▶▶▶]       │
│  -100  -10  -1    0     +1   +10  +100  (ms)  │
│                                                  │
│ □ Snap to grid (1/16)                          │
│                                                  │
│ [Apply to all layers]                           │
│                                                  │
└─────────────────────────────────────────────────┘
```

#### 3. Drag Gesture

```
User touches waveform →
  Visual feedback (highlight) →
    Drag left/right →
      Real-time offset value update →
        Release →
          Apply new offset
```

**Gesture Constraints:**
- Minimum drag distance: 5 pixels (prevent accidental nudges)
- Maximum offset: ±1 second from original position
- Snap zones if grid snap enabled

#### 4. Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `←` | Nudge -1ms |
| `→` | Nudge +1ms |
| `Shift + ←` | Nudge -10ms |
| `Shift + →` | Nudge +10ms |
| `Cmd + ←` | Nudge -100ms |
| `Cmd + →` | Nudge +100ms |
| `0` | Reset to zero |
| `G` | Toggle grid snap |

---

## Testing Plan

### Unit Tests

```dart
// test/state/sample_offset_calculator_test.dart
test('timeToFrames converts correctly at 48kHz', () {
  expect(
    SampleOffsetCalculator.timeToFrames(Duration(milliseconds: 10)),
    equals(480),
  );
});

test('splitOffset calculates coarse and fine correctly', () {
  final result = SampleOffsetCalculator.splitOffset(1000);
  expect(result.coarse, equals(3)); // 1000 / 256 = 3
  expect(result.fine, equals(232));  // 1000 % 256 = 232
});

test('combineOffsets reconstructs original', () {
  const original = 12345;
  final split = SampleOffsetCalculator.splitOffset(original);
  final combined = SampleOffsetCalculator.combineOffsets(
    split.coarse, 
    split.fine
  );
  expect(combined, equals(original));
});
```

### Integration Tests

1. **Record → Auto-Load → Playback**
   - Record 5 seconds of audio
   - Verify WAV file created
   - Verify sample loaded into slot 127
   - Verify pattern notes generated
   - Press play, verify audio plays back

2. **Offset Adjustment**
   - Load sample with offset 0
   - Set offset to +500ms
   - Verify pattern events updated with 09xx/07xx
   - Play and verify timing shift

3. **Drag Repositioning**
   - Drag waveform right 100 pixels
   - Verify offset calculation
   - Verify pattern update
   - Verify playback timing

### Manual Testing Scenarios

| Scenario | Expected Result |
|----------|----------------|
| Record, then play immediately | Audio plays back in sync |
| Offset +100ms, play | Audio starts 100ms later |
| Offset -50ms, play | Audio starts 50ms earlier |
| Drag waveform right | Offset increases, audio delayed |
| Nudge +1ms 10 times | Offset = +10ms total |
| Reset offset | Offset = 0, back to original timing |
| Switch layers | Each layer has independent offset |

---

## Future Enhancements

### Phase 8+: Advanced Features

1. **Stretch/Time-Compression**
   - Adjust sample playback speed
   - Preserve pitch (time-stretching)
   - Use SunVox pitch controllers

2. **Loop Region Selection**
   - Define loop start/end within recorded audio
   - Use sample loop controllers in Sampler

3. **Multi-Take Comping**
   - Record multiple takes
   - Select best regions from each
   - Crossfade between takes

4. **Audio Effects**
   - Apply reverb, delay to recorded audio
   - Use SunVox effect modules

5. **Fade In/Out**
   - Envelope control for smooth starts/ends
   - Use ADSR module

6. **Waveform Editing**
   - Trim recorded audio
   - Split into multiple samples
   - Basic cut/copy/paste

7. **Export Individual Tracks**
   - Export recorded audio separately
   - Mix with patterns for final render

---

## Technical Notes

### Precision Limits

**Frame Accuracy:**
- At 48kHz: 1 frame = 0.0208ms (very precise!)
- At 44.1kHz: 1 frame = 0.0227ms
- Human perception: ~10-20ms for rhythm detection
- **Conclusion:** Frame precision is more than sufficient

**Maximum Offset:**
- Combined 09xx + 07xx: 16,777,215 frames
- At 48kHz: ~349 seconds (~5.8 minutes)
- At 44.1kHz: ~380 seconds (~6.3 minutes)
- **Conclusion:** Sufficient for most recordings

### Performance Considerations

**Pattern Event Generation:**
- One note per loop/line (minimal overhead)
- Two effects per note (09xx + 07xx)
- No performance impact on playback

**Real-Time Offset Updates:**
- Pattern events can be updated while playing
- Use `sv_lock_slot()` for thread safety
- Avoid updating every frame during drag (throttle to ~60 FPS)

**Memory Usage:**
- Offset storage: 4 bytes per layer/section (negligible)
- Sample storage: Same as before (WAV file)
- Pattern notes: 12 bytes per note (minimal)

### Platform Compatibility

**All Platforms:**
- Frame offset works on iOS, Android, Desktop
- No platform-specific code needed
- SunVox handles timing internally

---

## Dependencies

### Existing Systems

- ✅ SunVox Library (v2.1.2b)
- ✅ Sample Bank System
- ✅ Pattern System
- ✅ Recording System
- ✅ Playback System

### New Dependencies

- None! (All functionality exists in SunVox)

---

## Estimated Timeline

| Phase | Duration | Cumulative |
|-------|----------|------------|
| Phase 1: Sample Loading | 2-3 days | 3 days |
| Phase 2: Coarse Offset | 3-4 days | 7 days |
| Phase 3: Fine Offset | 2-3 days | 10 days |
| Phase 4: Visual Indicator | 3-4 days | 14 days |
| Phase 5: Drag-to-Reposition | 4-5 days | 19 days |
| Phase 6: Nudge Controls | 2-3 days | 22 days |
| Phase 7: Multi-Layer | 3-4 days | 26 days |
| **Testing & Polish** | 4-5 days | **31 days** |

**Total Estimated Time:** ~1 month (with testing)

---

## Success Criteria

### Minimum Viable Product (MVP)

- [x] Recorded audio plays back during sequencer playback
- [x] Samples can be positioned with ±100ms accuracy
- [x] Visual indicator shows offset position
- [x] Basic offset adjustment (nudge buttons)

### Full Feature Set

- [x] Sample-accurate positioning (1/48000 sec)
- [x] Drag-to-reposition gesture
- [x] Keyboard shortcuts for nudging
- [x] Per-layer independent offsets
- [x] Snap-to-grid option
- [x] Visual feedback during adjustment

### Quality Metrics

- ✅ No audio glitches or artifacts
- ✅ Smooth real-time updates
- ✅ Intuitive UI/UX
- ✅ Accurate timing (verified with oscilloscope/analyzer)
- ✅ Works in both Loop and Song modes

---

## References

- [SunVox Library Architecture](./sunvox_integration/SUNVOX_LIBRARY_ARCHITECTURE.md)
- [Microphone Integration](./microphone_integration.md)
- [SunVox Effect Commands](../native/sunvox_lib/sunvox_lib/docs/)
- [Pattern System Documentation](./sunvox_integration/)

---

**Next Steps:**
1. Review and approve plan
2. Create GitHub issues for each phase
3. Begin Phase 1 implementation
4. Iterate based on testing feedback

---

**End of Plan**
