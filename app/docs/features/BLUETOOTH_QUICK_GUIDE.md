# Bluetooth Audio Quick Guide

**TL;DR:** For best quality with Bluetooth earbuds, follow this exact sequence!

---

## 🎯 Recommended Setup (Best Quality)

### Step-by-Step

1. **Connect Bluetooth earbuds** (iOS Settings → Bluetooth)

2. **Open app** and play patterns
   - Should sound great (high quality A2DP mode)

3. **When ready to record:**
   - Tap microphone button
   - **Immediately select "iPhone Microphone"** in INPUT tab
   - ✅ Patterns stay high quality, mic records from phone

4. **Record!**
   - Patterns: High quality through Bluetooth
   - Voice: Clean from iPhone mic

---

## ⚠️ If You Started With Bluetooth Mic (Low Quality)

If patterns sound bad after enabling mic:

### Quick Fix

1. **Disable microphone** (tap mic button)
2. **iOS Settings → Bluetooth**
3. **Tap (i) next to your device**
4. **Tap "Disconnect"**
5. **Wait 2 seconds**
6. **Tap device name to reconnect**
7. **Return to app**
8. **Enable microphone**
9. **Select "iPhone Microphone"** in INPUT tab
10. ✅ **Done!** Should be high quality now

---

## 🤔 Why This Happens

### Bluetooth Has Two Modes

**A2DP (Music Mode):**
- ✅ High quality stereo
- ✅ Great for patterns/music
- ❌ No microphone

**HFP (Phone Mode):**
- ✅ Has microphone
- ❌ Low quality mono (phone call quality)
- ❌ Bad for music

**The Problem:**
- When you enable mic with Bluetooth earbuds, iOS switches to HFP
- When you switch to iPhone mic, Bluetooth device stays in HFP
- Bluetooth device firmware doesn't know how to switch back to A2DP
- **Not an app bug - it's how Bluetooth works!**

---

## 📊 Quality Comparison

| Setup | Pattern Quality | Mic Quality | Effort |
|-------|----------------|-------------|--------|
| **iPhone mic + BT output** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | Easy (if done right) |
| **Wired headphones** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | Zero effort |
| **BT mic + BT output** | ⭐⭐ | ⭐⭐⭐ | Easy (but poor quality) |

---

## 💡 Pro Tips

### Starting Fresh
- Always start with Bluetooth in A2DP mode (listen to patterns first)
- Select iPhone mic BEFORE recording starts
- This avoids the HFP mode completely

### Already Recording
- If you must use Bluetooth mic first, know you'll need to reconnect
- Or just accept low quality for drafts, re-record later

### Best Practice
- **Wired headphones** = Best quality, zero hassle
- **iPhone mic + Bluetooth output** = Good quality, some setup needed
- **Bluetooth mic + output** = Quick drafts only

---

## 🐛 Not Bugs (Expected Behavior)

❌ "Quality drops when I enable mic" 
- ✅ **Expected:** Bluetooth switches to HFP mode

❌ "Switching to iPhone mic doesn't restore quality"
- ✅ **Expected:** Bluetooth device firmware limitation

❌ "Have to reconnect Bluetooth manually"
- ✅ **Expected:** Only way to force profile switch

---

## ✅ What Works

- ✅ Bluetooth mic + output (low quality, but works)
- ✅ iPhone mic + Bluetooth output (high quality, with manual reconnect if needed)
- ✅ Wired headphones (always perfect)
- ✅ 16kHz resampling (correct speed, maintains quality)
- ✅ Generic resampler (handles any sample rate)
- ✅ Warning logs when in HFP mode

---

## 📝 Summary

**For best wireless recording:**
1. Connect Bluetooth
2. Play patterns (verify quality)
3. Enable mic
4. **Select iPhone mic immediately**
5. If quality is bad, disconnect/reconnect Bluetooth
6. Record!

**For zero hassle:**
- Use wired headphones

**For quick drafts:**
- Accept Bluetooth HFP low quality
- Re-record properly later

---

**Remember:** This isn't a bug - it's how Bluetooth works! Every app has the same limitation (FaceTime, Zoom, GarageBand, etc.). The workarounds above are the best we can do! 🎧
