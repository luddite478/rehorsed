# Microphone Recording Test Guide

## Overview

This guide provides step-by-step testing procedures for the microphone recording system after the January 2026 rewrite.

---

## Test Environment Setup

### Prerequisites

1. iOS device with microphone access granted
2. App built with latest code changes
3. Debug logs enabled to monitor recording behavior

### Initial Setup

1. Launch app and navigate to sequencer
2. Enable microphone (mic button should show active)
3. Verify microphone level indicator shows audio input
4. Set BPM to a comfortable tempo (e.g., 120 BPM)

---

## Test Scenarios

### Test 1: Loop Mode - Single Section Recording

**Objective**: Verify unlimited line creation in loop mode

**Steps**:
1. Create a new pattern
2. Set section 0 to 16 steps
3. Select layer 0
4. Switch layer 0 to REC mode
5. Start playback
6. Press record button
7. Let it record for 5+ loops (watch section indicator)
8. Press stop recording

**Expected Results**:
- ✅ New waveform line created every 16 steps
- ✅ At least 5 waveform lines visible in UI
- ✅ Each line shows audio waveform data
- ✅ Debug log shows: `🔄 [LINE_MIC] Completed loop iteration!` for each line
- ✅ WAV file created in recordings directory
- ✅ Sample loaded to slot 25
- ✅ Pattern event created on layer 0, line 0

**Debug Logs to Check**:
```
🎙️ [LINE_MIC] Started capture: layer=0, section=0, startStep=X
📊 [LINE_MIC] Capturing: line 1, samples=X, level=0.XXX
🔄 [LINE_MIC] Completed loop iteration! Created line 2 (mode=loop, totalSteps=16)
➕ [LINE_MIC] Started new line 2 for layer=0 section=0
...
⏹️ [LINE_MIC] Stopped capture (waveform preserved): totalSteps=80, lines=5
```

---

### Test 2: Loop Mode - Endless Recording

**Objective**: Verify system handles 20+ loops without issues

**Steps**:
1. Continue from Test 1 or start fresh
2. Set layer 0 to REC mode
3. Start playback and recording
4. Let it record for 20+ loops (approximately 1-2 minutes)
5. Stop recording

**Expected Results**:
- ✅ 20+ waveform lines created
- ✅ UI scrollable to view all lines
- ✅ No crashes or freezes
- ✅ Waveform continues updating in real-time
- ✅ WAV file size grows continuously
- ✅ Memory usage remains stable

**Performance Checks**:
- UI remains responsive during recording
- Waveform rendering doesn't lag
- Audio capture continues smoothly

---

### Test 3: Song Mode - Single Section with Loop Limit

**Objective**: Verify line creation respects loop limits in song mode

**Steps**:
1. Create new pattern
2. Switch to SONG mode
3. Set section 0 to 16 steps, 4 loops
4. Select layer 0, switch to REC mode
5. Start playback and recording
6. Let it play through all 4 loops and continue
7. Stop recording after 6+ loops

**Expected Results**:
- ✅ Exactly 4 waveform lines created (one per loop)
- ✅ No 5th line created after loop 4
- ✅ Debug log shows: `⏹️ [LINE_MIC] Song mode: reached loop limit 4, not creating new line`
- ✅ Native WAV recording continues beyond 4 loops
- ✅ WAV file contains all 6+ loops of audio
- ✅ Waveform shows only first 4 loops visually

**Debug Logs to Check**:
```
🔄 [LINE_MIC] Completed loop iteration! Created line 1 (mode=song, totalSteps=16)
🔄 [LINE_MIC] Completed loop iteration! Created line 2 (mode=song, totalSteps=32)
🔄 [LINE_MIC] Completed loop iteration! Created line 3 (mode=song, totalSteps=48)
🔄 [LINE_MIC] Completed loop iteration! Created line 4 (mode=song, totalSteps=64)
⏹️ [LINE_MIC] Song mode: reached loop limit 4 (line 4), not creating new line
```

---

### Test 4: Song Mode - Multi-Section Recording

**Objective**: Verify continuous recording across multiple sections

**Steps**:
1. Create pattern with 3 sections
2. Switch to SONG mode
3. Set section 0: 16 steps, 2 loops
4. Set section 1: 8 steps, 3 loops
5. Set section 2: 16 steps, 2 loops
6. Set layer 0 to REC mode for ALL sections
7. Start playback and recording
8. Let it play through all sections
9. Stop recording

**Expected Results**:
- ✅ Section 0: 2 waveform lines created
- ✅ Section 1: 3 waveform lines created (new section, new lines)
- ✅ Section 2: 2 waveform lines created (new section, new lines)
- ✅ Debug log shows section transitions: `📍 [LINE_MIC] Section changed: 0 → 1`
- ✅ Single continuous WAV file created
- ✅ Total 7 waveform lines visible (2+3+2)
- ✅ Each section's lines show correct loop count

**Debug Logs to Check**:
```
🎙️ [LINE_MIC] Started capture: layer=0, section=0, startStep=0
🔄 [LINE_MIC] Completed loop iteration! Created line 2 (mode=song, totalSteps=16)
📍 [LINE_MIC] Section changed: 0 → 1
✅ [LINE_MIC] Continuing recording in new section 1
➕ [LINE_MIC] Started new line 1 for layer=0 section=1
🔄 [LINE_MIC] Completed loop iteration! Created line 2 (mode=song, totalSteps=8)
🔄 [LINE_MIC] Completed loop iteration! Created line 3 (mode=song, totalSteps=16)
📍 [LINE_MIC] Section changed: 1 → 2
...
```

---

### Test 5: Multi-Section with Mode Changes

**Objective**: Verify recording stops when section without REC mode is reached

**Steps**:
1. Create pattern with 3 sections
2. Switch to SONG mode
3. Set section 0: REC mode on layer 0
4. Set section 1: SEQUENCE mode on layer 0 (not REC)
5. Set section 2: REC mode on layer 0
6. Start playback and recording
7. Let it play through all sections

**Expected Results**:
- ✅ Section 0: Waveform lines created
- ✅ Section 1: Waveform capture stops (debug log shows stop)
- ✅ Section 2: Waveform capture does NOT restart (recording already stopped)
- ✅ Native WAV recording continues throughout
- ✅ Debug log: `⏹️ [LINE_MIC] New section 1 not in REC mode, stopping waveform capture`

---

### Test 6: Waveform Persistence

**Objective**: Verify waveform persists after recording stops

**Steps**:
1. Record 3 loops in loop mode
2. Stop recording
3. Switch layer to SEQUENCE mode
4. Verify waveform still visible
5. Switch back to REC mode
6. Verify waveform still visible
7. Start new recording
8. Verify old waveform cleared, new waveform starts

**Expected Results**:
- ✅ Waveform visible after recording stops
- ✅ Waveform persists when switching to SEQUENCE mode
- ✅ Waveform persists when switching back to REC mode
- ✅ New recording clears old waveform
- ✅ Debug log: `🗑️ [LINE_MIC] Cleared lines for layer=0 section=0` on new recording

---

### Test 7: Sample Playback Integration

**Objective**: Verify recorded audio plays back correctly

**Steps**:
1. Record 3 loops
2. Stop recording
3. Wait for sample loading (check debug logs)
4. Start playback (without recording)
5. Listen to audio output

**Expected Results**:
- ✅ Debug log: `✅ [SAMPLE_BANK_STATE] Loaded recorded audio into slot 25`
- ✅ Debug log: `✅ [RECORDING] Generated single pattern event for recorded audio`
- ✅ Recorded audio plays back on layer 0
- ✅ Audio matches what was recorded
- ✅ Playback starts at beginning of section
- ✅ Entire recording plays through (all 3 loops)

---

### Test 8: Recording Without Playback

**Objective**: Verify recording works when playback is stopped

**Steps**:
1. Stop playback if running
2. Set layer 0 to REC mode
3. Press record button
4. Speak/make sounds into microphone for 10 seconds
5. Stop recording

**Expected Results**:
- ✅ Recording starts immediately (no waiting for loop boundary)
- ✅ Single waveform line created (no loop iterations)
- ✅ Waveform shows continuous audio data
- ✅ WAV file created with 10 seconds of audio
- ✅ Sample loads correctly

---

### Test 9: Rapid Start/Stop

**Objective**: Verify system handles quick record button presses

**Steps**:
1. Start playback
2. Quickly press record, wait 1 second, stop
3. Repeat 3 times
4. Check for any errors or crashes

**Expected Results**:
- ✅ No crashes or freezes
- ✅ Each recording creates new WAV file
- ✅ Previous recordings are overwritten (expected behavior)
- ✅ Waveform clears and restarts each time
- ✅ No memory leaks

---

### Test 10: Large Recording Memory Test

**Objective**: Verify system handles very long recordings

**Steps**:
1. Set loop mode
2. Start recording
3. Let it record for 100+ loops (5+ minutes)
4. Monitor memory usage
5. Stop recording

**Expected Results**:
- ✅ 100+ waveform lines created
- ✅ UI remains responsive
- ✅ Waveform downsampling kicks in (max 4096 samples per line)
- ✅ Memory usage stays within reasonable bounds
- ✅ WAV file created successfully
- ✅ Sample loads (may show memory warning if >30MB)

---

## Common Issues and Solutions

### Issue: No Waveform Lines Created

**Symptoms**: Recording starts but no waveform lines appear

**Debug**:
1. Check `_isActuallyRecording` is true
2. Verify `_captureLineSamples()` is being called
3. Check `_currentLineSteps` is incrementing
4. Verify section step count is correct

**Solution**: Ensure recording state is properly connected to waveform state

---

### Issue: Lines Not Created in Loop Mode

**Symptoms**: Only 1 line created, no subsequent lines

**Debug**:
1. Check debug logs for step counting
2. Verify `_currentLineSteps >= sectionSteps` condition
3. Check playback is actually looping

**Solution**: Verify playback state is updating correctly

---

### Issue: Waveform Disappears After Recording

**Symptoms**: Waveform visible during recording, gone after stop

**Debug**:
1. Check `stopCapture()` implementation
2. Verify `clearExisting` flag usage
3. Check if `clearLines()` is being called unexpectedly

**Solution**: Ensure `stopCapture()` doesn't clear `_linesByLayerSection`

---

### Issue: Recording Doesn't Continue Across Sections

**Symptoms**: Recording stops when section changes

**Debug**:
1. Check section transition detection
2. Verify new section has REC mode
3. Check debug logs for section change messages

**Solution**: Ensure all sections have REC mode for continuous recording

---

## Performance Benchmarks

### Expected Performance

| Metric | Target | Acceptable |
|--------|--------|------------|
| Line creation latency | <100ms | <200ms |
| UI frame rate during recording | 60 FPS | >30 FPS |
| Memory per 100 lines | <10MB | <20MB |
| WAV file write performance | Real-time | No drops |
| Sample load time (30MB) | <2s | <5s |

---

## Debug Log Reference

### Key Log Messages

| Message | Meaning |
|---------|---------|
| `🎙️ [LINE_MIC] Started capture` | Recording waveform capture started |
| `📊 [LINE_MIC] Capturing: line N` | Actively capturing samples |
| `🔄 [LINE_MIC] Completed loop iteration!` | New line created (loop completed) |
| `➕ [LINE_MIC] Started new line N` | New waveform line initialized |
| `📍 [LINE_MIC] Section changed` | Section transition detected |
| `✅ [LINE_MIC] Continuing recording` | Recording continues in new section |
| `⏹️ [LINE_MIC] Stopped capture` | Recording stopped, waveform preserved |
| `🗑️ [LINE_MIC] Cleared lines` | Waveform data cleared |

---

## Conclusion

All tests should pass for the recording system to be considered fully functional. Any failures should be investigated using the debug logs and troubleshooting steps provided.

---

Last Updated: 2026-01-25
