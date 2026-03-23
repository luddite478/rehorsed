# Debug Guide: Recording Lines Issue

## Current Status

Added comprehensive debug logging to track line creation and display issues.

## What to Look For in Logs

### 1. Recording Start
```
🎙️ [LINE_MIC] Started capture: layer=0, section=0, loop=0
```

### 2. Line Creation
```
➕ [LINE_MIC] Started new line: 1 → 2 for layer=0 section=0
   Current lines in memory: [128, 0]
```
- First number (1 → 2) shows line count before and after
- Array shows sample counts for each line

### 3. Loop Detection
```
🔄 [LINE_MIC] Loop changed: 0 → 1
✅ [LINE_MIC] Loop iteration completed! Created line 2 (mode=loop)
```
OR
```
✅ [LINE_MIC] Loop wraparound detected (loop mode)! Created line 2
```

### 4. Sample Capture
```
📊 [LINE_MIC] Capturing: line 1/1, samples=1280, level=0.234
```
- Shows which line we're capturing to
- Total number of lines
- Sample count in current line

### 5. UI Display
```
🖼️ [UI] Displaying layer=0, section=0, lines=2, loopsNum=4
```
- Shows what the UI is trying to display
- If lines=1 but you expect more, lines aren't being created

### 6. Line Retrieval
```
📖 [LINE_MIC] getLines(layer=0, section=0): returning 2 lines with samples: [1280, 640]
```
- Shows what data is being returned to UI
- Array shows sample counts for each line

### 7. Line Clearing (Should NOT happen during recording!)
```
🗑️ [LINE_MIC] Cleared 2 lines for layer=0 section=0
   Stack trace: ...
```
- If you see this during recording, that's the bug!
- Stack trace will show who called clearLines

## Expected Flow for 3 Loops

```
1. Start recording:
   🎙️ [LINE_MIC] Started capture: layer=0, section=0, loop=0
   
2. First loop samples:
   📊 [LINE_MIC] Capturing: line 1/1, samples=128, level=0.2
   📊 [LINE_MIC] Capturing: line 1/1, samples=256, level=0.3
   ...
   
3. Loop completes, new line created:
   🔄 [LINE_MIC] Loop changed: 0 → 1
   ➕ [LINE_MIC] Started new line: 1 → 2 for layer=0 section=0
   ✅ [LINE_MIC] Loop iteration completed! Created line 2
   
4. Second loop samples:
   📊 [LINE_MIC] Capturing: line 2/2, samples=128, level=0.2
   ...
   
5. Another loop:
   🔄 [LINE_MIC] Loop changed: 1 → 2
   ➕ [LINE_MIC] Started new line: 2 → 3 for layer=0 section=0
   ✅ [LINE_MIC] Loop iteration completed! Created line 3
   
6. Stop recording:
   ⏹️ [LINE_MIC] Stopped capture (waveform preserved): lines=3
```

## Common Issues

### Issue 1: Lines Get Cleared During Recording
**Symptom**: See `🗑️ [LINE_MIC] Cleared` message while recording

**Cause**: `clearLines()` or `startCapture(clearExisting: true)` called during recording

**Fix**: Check stack trace to see who's calling it

### Issue 2: Only One Line Created
**Symptom**: Never see line count increase beyond 1

**Possible Causes**:
1. Loop counter not changing (check for `🔄 [LINE_MIC] Loop changed` messages)
2. Wraparound not detected (check for step messages)
3. Song mode loop limit reached too early

**Fix**: Look for loop detection messages

### Issue 3: UI Shows Wrong Number of Lines
**Symptom**: `getLines` returns N lines but UI shows different count

**Cause**: UI `lineCount` calculation issue or wrong section/layer

**Fix**: Compare:
- `📖 [LINE_MIC] getLines` output
- `🖼️ [UI] Displaying` output
- Check if layer/section match

### Issue 4: Lines Appear Then Disappear
**Symptom**: Lines flash briefly then vanish

**Possible Causes**:
1. `clearLines()` called after creation
2. UI rebuilding with different section
3. `hasRecordedData()` returning false

**Fix**: Check for clear messages and UI display section changes

## Testing Commands

### Test in Loop Mode
1. Set section to 16 steps
2. Set layer to REC mode
3. Start playback
4. Press record
5. Watch logs for 3+ loops
6. Stop recording
7. Check final line count

### Expected Logs
- Should see 3+ `➕ [LINE_MIC] Started new line` messages
- Should see 3+ `✅ [LINE_MIC] Loop iteration completed` messages
- Final `⏹️ [LINE_MIC] Stopped capture` should show lines=3+
- Should NOT see any `🗑️ [LINE_MIC] Cleared` messages during recording

## Next Steps

1. Run the app with debug logs enabled
2. Start recording for 3 loops
3. Copy all logs starting from `🎙️ [LINE_MIC] Started capture`
4. Look for the patterns above
5. Identify which issue matches your symptoms
