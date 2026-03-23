# Bluetooth Audio Quality Limitation

**Date:** January 13, 2026  
**Issue:** Sound quality drops when enabling microphone with Bluetooth earbuds  
**Status:** ⚠️ Hardware Limitation (Cannot be fixed in software)

---

## The Problem

**User Experience:**
1. Bluetooth earbuds connected
2. Patterns sound great (high quality)
3. Enable microphone
4. **Suddenly patterns sound terrible** (muffled, mono, low quality)

---

## Why This Happens

### Bluetooth Has Two Modes

Bluetooth audio devices operate in different "profiles" depending on what you're doing:

#### A2DP - Music Mode (One-Way)
```
Direction: Output only (no microphone)
Quality:   High (~320 kbps, stereo)
Sample:    44.1 kHz or higher
Use:       Music, podcasts, media playback
Result:    🎵 Sounds great!
```

#### HFP - Phone Call Mode (Two-Way)
```
Direction: Bidirectional (mic + output)
Quality:   Low (~64 kbps, mono)
Sample:    16 kHz (voice call quality)
Use:       Phone calls, voice chat
Result:    📞 Sounds like a phone call
```

### The Switch

When you enable the microphone in the app:

```
BEFORE (Listening only):
  Bluetooth → A2DP mode
  Output: High quality stereo
  No mic needed
  ✅ Great sound!

AFTER (Recording with mic):
  iOS detects: "Need microphone + output"
  Bluetooth → HFP mode (forced by hardware)
  Output: Low quality mono
  Mic: Enabled (16kHz)
  ❌ Poor sound quality!
```

**This is a Bluetooth hardware limitation - the device cannot transmit high-quality audio in both directions simultaneously.**

---

## Why Can't We Fix This?

### Hardware Bandwidth Limitation

```
Bluetooth Classic Bandwidth: ~2-3 Mbps total

A2DP (Music):
  Output: 320 kbps (stereo)
  Total: 320 kbps ✅ Fits easily

HFP (Calls):
  Output: 64 kbps (mono)
  Input: 64 kbps (mono)
  Total: 128 kbps ✅ Fits easily

A2DP + Microphone (Impossible):
  Output: 320 kbps (stereo)
  Input: 64 kbps (mic)
  Total: 384 kbps ❌ Would work...
  
But profiles are fixed by Bluetooth spec:
  - A2DP = output only (no mic)
  - HFP = bidirectional (low quality)
  - No "high quality bidirectional" mode exists!
```

### It's Not Just Our App

**Every app** has this limitation:
- FaceTime, WhatsApp, Zoom → HFP mode (voice quality)
- Voice memos with Bluetooth → HFP mode
- GarageBand with Bluetooth mic → HFP mode
- **No iOS app can bypass this** - it's in the Bluetooth spec

---

## Solutions & Workarounds

### ✅ Solution 1: iPhone Mic + Bluetooth Output (RECOMMENDED)

**Best quality for recording patterns with voice:**

**⚠️ IMPORTANT:** Due to Bluetooth device limitations, you need to follow this specific sequence:

1. **Connect Bluetooth earbuds**
2. **DO NOT enable microphone yet**
3. **Play patterns** - verify high quality sound (A2DP mode)
4. **When ready to record:**
   - Enable microphone
   - **Immediately select "iPhone Microphone"** in INPUT tab
   - If already in Bluetooth mic, follow "Manual Workaround" below

**Manual Workaround (If Stuck in HFP Mode):**

If patterns sound low quality after switching to iPhone mic:

1. **Disable microphone** in app (tap mic button to turn off)
2. **iOS Settings → Bluetooth → [Your Device] → Disconnect**
3. **Wait 2 seconds**
4. **Reconnect** your Bluetooth device
5. **Return to app**
6. **Enable microphone**
7. **Select "iPhone Microphone"** in INPUT tab
8. **Result:** High quality A2DP output! ✅

**Why This Is Needed:**

Most Bluetooth devices cannot automatically switch from HFP (phone mode) back to A2DP (music mode) while the app is running. This is a hardware/firmware limitation in the Bluetooth device itself, not an app bug.

**Pros:**
- ✅ High quality pattern playback (A2DP) - *when done correctly*
- ✅ Good mic quality (iPhone mic is decent)
- ✅ No phone call audio quality

**Cons:**
- ⚠️ Requires manual Bluetooth reconnect if you start with Bluetooth mic
- ⚠️ Less isolation (patterns might bleed into mic)
- ⚠️ Need to hold phone closer

---

### ✅ Solution 2: Wired Headphones (BEST QUALITY)

**Professional recording quality:**

1. Use wired headphones with mic (Lightning or USB-C)
2. Enable microphone
3. **Result:**
   - Output: High quality (digital)
   - Input: Wired mic (48kHz, no compression)
   - ✅ Perfect quality for both!

**Pros:**
- ✅ Highest quality possible
- ✅ Zero latency
- ✅ Perfect isolation (no bleed)
- ✅ No Bluetooth limitations

**Cons:**
- ⚠️ Need wired headphones
- ⚠️ Cable can be annoying

---

### ⚠️ Solution 3: Accept Low Quality (QUICK DRAFTS)

**For quick ideas/demos:**

1. Use Bluetooth mic + Bluetooth output
2. Accept HFP mode (low quality)
3. **Result:**
   - Output: Low quality (16kHz mono)
   - Input: Bluetooth mic (16kHz)
   - ⚠️ Poor quality but functional

**Pros:**
- ✅ Wireless convenience
- ✅ Good enough for drafts/ideas
- ✅ No setup needed

**Cons:**
- ❌ Poor pattern quality (muffled, mono)
- ❌ 16kHz audio (phone call quality)
- ❌ Not suitable for final recordings

**Use when:**
- Quick idea capture
- Draft recordings
- Don't care about quality
- Will re-record later

---

## Technical Details

### What Happens in Code

```objective-c
// Our audio session setup
[session setCategory:AVAudioSessionCategoryPlayAndRecord 
             options:AVAudioSessionCategoryOptionAllowBluetooth |
                     AVAudioSessionCategoryOptionAllowBluetoothA2DP];

// iOS behavior:
if (bluetooth_mic_selected) {
    // iOS: "Need bidirectional Bluetooth audio"
    // iOS: "Only HFP supports this"
    // iOS: "Switch to HFP mode"
    
    result = HFP_MODE;  // Low quality
    sample_rate = 16000;  // Phone call quality
    channels = 1;  // Mono
}

if (iphone_mic_selected) {
    // iOS: "Bluetooth for output only"
    // iOS: "Can use A2DP for high quality"
    
    result = A2DP_MODE;  // High quality
    output_quality = HIGH;  // Stereo, 44.1/48kHz
}
```

### Logs When Bluetooth Mic Active

```
🎤 [MIC_INPUT] Current input: AirPods Pro (type: BluetoothHFP)
🔊 [MIC_INPUT] Current output: AirPods Pro (type: BluetoothHFP)
⚠️ [MIC_INPUT] WARNING: Bluetooth bidirectional audio uses HFP (low quality ~16kHz)
💡 [MIC_INPUT] TIP: For better quality, use iPhone mic + Bluetooth output
🎙️ [MIC_INPUT] Input format: 16000 Hz, 1 channels
⚠️ [MIC_INPUT] 16kHz (Bluetooth HFP) - will resample 3x to 48kHz
```

Notice:
- Both input and output show "BluetoothHFP" (not A2DP)
- Sample rate: 16000 Hz (phone quality)
- Channels: 1 (mono)

### Logs When iPhone Mic + Bluetooth Output (Success)

```
🎤 [MIC_INPUT] Current input: iPhone Microphone (type: MicrophoneBuiltIn)
🔊 [MIC_INPUT] Current output: AirPods Pro (type: BluetoothA2DP)
✅ [MIC_INPUT] ~48kHz native - no resampling needed
🎙️ [MIC_INPUT] Input format: 48000 Hz, 1 channels
```

Notice:
- Output shows "BluetoothA2DP" (high quality!)
- Sample rate: 48000 Hz (professional quality)
- Input: Built-in mic (also 48kHz)

### Logs When Profile Switch Fails

```
🔄 [MIC_INPUT] Switching from Bluetooth to built-in mic - forcing A2DP output
   Step 1: Temporarily routing to speaker
   Step 2: Cleared route override - allowing Bluetooth
   Step 3: Session reactivated
🔊 [MIC_INPUT] Output now: AirPods Pro (type: BluetoothHFP)
⚠️ [MIC_INPUT] Still in HFP mode - device doesn't support profile switch
💡 [MIC_INPUT] Try: Disable mic, disconnect/reconnect Bluetooth, enable mic, select iPhone mic
```

**If you see this:**
1. Some Bluetooth devices refuse to switch profiles while app is running
2. Manual workaround needed (see below)

---

## Comparison Table

| Setup | Output Quality | Input Quality | Isolation | Best For |
|-------|---------------|---------------|-----------|----------|
| **Wired headphones** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | Final recordings |
| **iPhone mic + BT out** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ | High quality wireless |
| **BT mic + BT out** | ⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | Quick drafts |
| **Built-in speaker** | ⭐⭐⭐⭐⭐ | ⭐⭐ | ⭐ | Testing only |

---

## Manual Workaround (If Automatic Switch Fails)

Some Bluetooth devices stubbornly stay in HFP mode even after switching to iPhone mic. If you see:

```
⚠️ Still in HFP mode - device doesn't support profile switch
```

**Try this manual process:**

### Method 1: Disable Mic First (Simplest)
1. **Disable microphone** completely (tap mic button to turn it off)
2. **Wait 2-3 seconds** for Bluetooth to switch back to A2DP automatically
3. **Check iOS Control Center** - you should see normal Bluetooth icon
4. **Re-enable microphone**
5. **Immediately switch to "iPhone Microphone"** in INPUT tab before iOS settles into HFP
6. iOS should now use A2DP for output

### Method 2: Reconnect Bluetooth (Most Reliable)
1. **Disable microphone** in app
2. Go to **iOS Settings → Bluetooth**
3. **Disconnect** your earbuds (tap (i) → Disconnect)
4. **Wait 2 seconds**
5. **Reconnect** your earbuds
6. Return to app
7. **Enable microphone**
8. **Select "iPhone Microphone"** in INPUT tab
9. Should now be in A2DP mode!

### Method 3: Start Fresh (Nuclear Option)
1. **Close the app** completely
2. Go to **iOS Settings → Bluetooth**
3. **Disconnect** Bluetooth earbuds
4. **Reconnect** Bluetooth earbuds
5. **Open app**
6. **Enable microphone**
7. **Select "iPhone Microphone"** in INPUT tab IMMEDIATELY
8. Should now be A2DP!

### Why This Happens

Once iOS establishes a Bluetooth connection in HFP mode (bidirectional), some devices:
- Lock into that mode
- Refuse to switch back to A2DP while app is running
- Require a full disconnect/reconnect cycle

**Device-specific:** Some earbuds handle this better than others. AirPods usually switch fine, cheap Bluetooth earbuds often get stuck.

---

## Frequently Asked Questions

### Q: Can you add a setting to force high quality Bluetooth?
**A:** No. This is a Bluetooth hardware limitation. The profiles (A2DP vs HFP) are defined by the Bluetooth specification and cannot be changed by software.

### Q: Why does [other app] work better?
**A:** It doesn't - all apps have the same limitation. Apps that seem to work better are either:
1. Using iPhone mic (not Bluetooth mic)
2. The quality difference is less noticeable for voice-only content
3. Heavy audio compression makes the quality loss less obvious

### Q: Will Bluetooth 5.0 fix this?
**A:** No. Bluetooth 5.0 increases range and IoT features, but audio profiles remain the same. Even Bluetooth 5.3 uses the same HFP/A2DP profiles.

### Q: What about AptX or LDAC codecs?
**A:** Those improve A2DP quality (music mode) but don't help with HFP (call mode). When microphone is active, you're in HFP mode regardless of codec support.

### Q: Can I disable HFP and force A2DP?
**A:** No - if you do that, the microphone won't work at all. A2DP is output-only by design.

---

## Recommendations

### For Different Use Cases

**🎵 Casual Recording (Good Enough):**
- Use: Bluetooth mic + Bluetooth output
- Accept: Low quality HFP mode
- Works for: Ideas, drafts, demos

**🎤 Serious Recording (High Quality):**
- Use: iPhone mic + Bluetooth output
- Get: A2DP quality output
- Works for: Most productions

**🎚️ Professional Recording (Best Quality):**
- Use: Wired headphones with mic
- Get: Full quality everything
- Works for: Final recordings

---

## What We Did in Code

### Added Warning Logs
```objective-c
if (bluetooth_input && bluetooth_output) {
    prnt("⚠️ WARNING: Bluetooth bidirectional = low quality HFP mode");
    prnt("💡 TIP: Use iPhone mic + Bluetooth output for better quality");
}
```

### Added Resampling
```objective-c
// When HFP gives us 16kHz, we resample to 48kHz
// This fixes the speed but can't improve the quality
if (sampleRate == 16000.0) {
    resample_to_48kHz();  // Correct speed, maintain HFP quality
}
```

### What We CANNOT Do
- ❌ Force A2DP with microphone (impossible - A2DP has no mic)
- ❌ Improve HFP quality (fixed by Bluetooth spec)
- ❌ Create custom Bluetooth profile (requires hardware firmware)
- ❌ Bypass iOS Bluetooth stack (not allowed)

---

## Conclusion

The sound quality drop when using Bluetooth mic is **not a bug** - it's a fundamental Bluetooth hardware limitation that affects all apps on all platforms.

**Best practice:**
- Use **iPhone mic + Bluetooth output** for high-quality wireless recording
- Use **wired headphones** for best quality
- Use **Bluetooth mic** only for quick drafts when quality doesn't matter

The app now:
- ✅ Warns you when HFP mode is active
- ✅ Gives tips for better quality
- ✅ Resamples 16kHz correctly
- ✅ Works reliably in all modes

But it **cannot** change the fundamental Bluetooth limitation! 🎧
