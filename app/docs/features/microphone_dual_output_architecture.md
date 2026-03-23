# Microphone Dual-Output Architecture (Archived)

> **Status**: ARCHIVED - This approach was replaced with simplified direct mixing.
> **Date**: 2026-01-25
> **Reason**: Sample cancellation bug when samples placed before recording started.

This document preserves the dual-output microphone recording architecture for future reference.

---

## Overview

The dual-output system was designed to allow **independent control** of:
1. **Monitor volume** - what the user hears through speakers (can be 0 for no feedback)
2. **Recording volume** - what gets written to the WAV file (always full quality)

This enabled recording vocals without hearing yourself (monitor=0) while still capturing full-quality audio (recording=256).

---

## Architecture

### Components

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        AUDIO CALLBACK FLOW                               │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌──────────────┐     ┌─────────────────┐                               │
│  │ AVAudioEngine│────▶│ Circular Buffer │                               │
│  │   (iOS)      │     │  g_mic_buffer   │                               │
│  └──────────────┘     └────────┬────────┘                               │
│                                │                                         │
│                    mic_input_read_frames()                               │
│                                │                                         │
│                                ▼                                         │
│                       ┌────────────────┐                                │
│                       │   mic_buffer   │ (local in audio_callback)      │
│                       └────────┬───────┘                                │
│                                │                                         │
│                                ▼                                         │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │              sv_audio_callback2(pOutput, mic_buffer)             │    │
│  │                                                                   │    │
│  │  ┌─────────────────────────────────────────────────────────┐     │    │
│  │  │                    SunVox Engine                         │     │    │
│  │  │                                                          │     │    │
│  │  │   ┌────────────┐      ┌────────────┐                    │     │    │
│  │  │   │  Sampler   │──┐   │  Sampler   │──┐                 │     │    │
│  │  │   │  Module 0  │  │   │  Module 1  │  │  ... (samples)  │     │    │
│  │  │   └────────────┘  │   └────────────┘  │                 │     │    │
│  │  │                   │                   │                 │     │    │
│  │  │   ┌───────────────────────────────────────────────┐    │     │    │
│  │  │   │           Input Module (psynths_input.cpp)     │    │     │    │
│  │  │   │                                                │    │     │    │
│  │  │   │  pnet->in_buf (mic_buffer from callback2)      │    │     │    │
│  │  │   │            │                                   │    │     │    │
│  │  │   │            ▼                                   │    │     │    │
│  │  │   │  ┌─────────────────┐  ┌──────────────────┐    │    │     │    │
│  │  │   │  │  channels_out   │  │ recording_output │    │    │     │    │
│  │  │   │  │ (monitor_vol)   │  │  (recording_vol) │    │    │     │    │
│  │  │   │  │   e.g., 0       │  │    e.g., 256     │    │    │     │    │
│  │  │   │  └────────┬────────┘  └────────┬─────────┘    │    │     │    │
│  │  │   │           │                    │              │    │     │    │
│  │  │   └───────────│────────────────────│──────────────┘    │     │    │
│  │  │               │                    │                   │     │    │
│  │  │               ▼                    │                   │     │    │
│  │  │         ┌───────────┐              │                   │     │    │
│  │  │         │  Output   │◀─────────────┼───────────────────┘     │    │
│  │  │         │  Module   │              │                         │    │
│  │  │         └─────┬─────┘              │                         │    │
│  │  │               │                    │                         │    │
│  │  └───────────────│────────────────────│─────────────────────────┘    │
│  │                  │                    │                              │
│  └──────────────────│────────────────────│──────────────────────────────┘
│                     │                    │                               │
│                     ▼                    │                               │
│               ┌──────────┐               │                               │
│               │ pOutput  │               │  sv_get_input_module_         │
│               │ (samples │               │  recording_output()           │
│               │  + mic   │               │                               │
│               │ @mon_vol)│               ▼                               │
│               └────┬─────┘         ┌───────────┐                        │
│                    │               │input_rec_L│                        │
│                    │               │input_rec_R│                        │
│                    │               └─────┬─────┘                        │
│                    │                     │                               │
│                    │    Recording Mix    │                               │
│                    └─────────┬───────────┘                               │
│                              │                                           │
│                              ▼                                           │
│                    ┌───────────────────┐                                │
│                    │ recording_mix_buf │                                │
│                    │ = pOutput + rec_L │                                │
│                    └─────────┬─────────┘                                │
│                              │                                           │
│                              ▼                                           │
│                    ┌───────────────────┐                                │
│                    │    WAV File       │                                │
│                    └───────────────────┘                                │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Key Files

### 1. microphone_input.mm - AVAudioEngine Capture

```cpp
// Circular buffer for mic samples
#define MIC_BUFFER_SIZE (48000 * 2 * 2) // 2 seconds stereo float32 @ 48kHz
static float g_mic_buffer[MIC_BUFFER_SIZE];

// AVAudioEngine tap writes to circular buffer
[g_input_node installTapOnBus:0 bufferSize:1024 format:inputFormat 
    block:^(AVAudioPCMBuffer* buffer, AVAudioTime* when) {
        // Write to g_mic_buffer with resampling if needed
    }];

// Audio callback reads from circular buffer
int mic_input_read_frames(float* buffer, int frame_count) {
    // Copy from g_mic_buffer to output buffer
    // Thread-safe with mutex
}
```

### 2. playback_sunvox.mm - Audio Callback

```cpp
static void audio_callback(ma_device* device, void* output, const void* input, ma_uint32 frameCount) {
    float* pOutput = (float*)output;
    
    if (mic_input_is_active()) {
        // Read mic frames
        static float mic_buffer[8192];
        int frames_read = mic_input_read_frames(mic_buffer, frameCount);
        
        // Pass mic to SunVox via callback2
        // This feeds mic_buffer to Input module's pnet->in_buf
        result = sv_audio_callback2(pOutput, frameCount, 0, sv_get_ticks(), 1, 2, mic_buffer);
    } else {
        // No mic - regular callback
        result = sv_audio_callback(pOutput, frameCount, 0, sv_get_ticks());
    }
    
    // Recording logic
    if (recording_is_active()) {
        // Get Input module's recording output (full volume mic)
        float* input_rec_L = sv_get_input_module_recording_output(SUNVOX_SLOT, g_input_module_id, 0);
        float* input_rec_R = sv_get_input_module_recording_output(SUNVOX_SLOT, g_input_module_id, 1);
        
        if (input_rec_L && input_rec_R) {
            // Dual output mode: Mix samples (pOutput) + full-volume mic (recording_output)
            for (ma_uint32 i = 0; i < frameCount; i++) {
                recording_mix_buffer[i * 2 + 0] = pOutput[i * 2 + 0] + input_rec_L[i];
                recording_mix_buffer[i * 2 + 1] = pOutput[i * 2 + 1] + input_rec_R[i];
            }
            recording_write_frames_from_callback(recording_mix_buffer, frameCount);
        } else {
            // Single output: what you hear is recorded
            recording_write_frames_from_callback(pOutput, frameCount);
        }
    }
}
```

### 3. psynths_input.cpp - SunVox Input Module (Modified)

```cpp
struct MODULE_DATA {
    PS_CTYPE   ctl_volume;         // Recording volume (Controller 0)
    PS_CTYPE   ctl_monitor_volume; // Monitor volume (Controller 1) - ADDED
    PS_CTYPE   ctl_stereo;         // Channels (Controller 2)
    
    // REHORSED: Secondary output for recording
    PS_STYPE*  recording_output[MODULE_OUTPUTS];
    int        recording_output_allocated;
};

case PS_CMD_RENDER_REPLACE:
    if (pnet->in_buf) {
        int monitor_vol = data->ctl_monitor_volume;
        int recording_vol = data->ctl_volume;
        bool need_dual_output = (monitor_vol != recording_vol);
        
        // Allocate recording_output if needed
        if (need_dual_output) {
            // Allocate buffers...
        }
        
        // Process each channel
        for (int ch = 0; ch < outputs_num; ch++) {
            PS_STYPE* out = outputs[ch] + offset;           // Main output (monitor)
            PS_STYPE* rec_out = recording_output[ch] + offset;  // Recording output
            
            // For float32 input:
            for (int i = 0; i < frames; i++) {
                float fv = *in;
                in += pnet->in_buf_channels;
                
                // Monitor volume → speakers
                out[i] = (fv * monitor_vol) / 256.0f;
                
                // Recording volume → file
                rec_out[i] = (fv * recording_vol) / 256.0f;
            }
        }
    }
```

### 4. sunvox_lib.cpp - Custom API

```cpp
// Get recording output buffer pointer
SUNVOX_EXPORT void* sv_get_input_module_recording_output(int slot, int mod_num, int channel) {
    // Returns data->recording_output[channel] from Input module
    // Allows playback to access full-volume mic data
}

// Set monitor volume (Controller 1)
SUNVOX_EXPORT int sv_set_input_monitor_volume(int slot, int mod_num, int volume) {
    // Sets ctl_monitor_volume
}

// Set recording volume (Controller 0)
SUNVOX_EXPORT int sv_set_input_recording_volume(int slot, int mod_num, int volume) {
    // Sets ctl_volume
}
```

---

## Volume Controllers

| Controller | Name | Range | Purpose |
|------------|------|-------|---------|
| 0 | Recording Volume | 0-1024 | Volume for WAV file (usually 256 = 100%) |
| 1 | Monitor Volume | 0-1024 | Volume for speakers (0 = silent, 256 = 100%) |
| 2 | Channels | 0-1 | Mono (0) or Stereo (1) |

### Dual-Output Activation

Dual-output mode activates when `monitor_vol != recording_vol`:
- `monitor_vol = 0, recording_vol = 256` → Silent monitoring, full recording
- `monitor_vol = 256, recording_vol = 256` → Single output (no dual buffers)

---

## Known Issues

### 1. Sample Cancellation Bug (Primary Issue)

**Symptom**: When samples are placed in Layer 1 BEFORE recording starts in Layer 2, sample audio drops to ~2% volume in the recording.

**Evidence from debug logs**:
```
# Input module writes full mic data
DUAL_WRITE_F32 max_input=0.917

# But playback reads attenuated samples
MIX #100: samples_max=0.0185 rec_L_max=0.1914
# Expected: samples_max ~0.5-1.0
```

**Order Dependency**:
- Record first, add samples later → Works
- Add samples first, then record → Fails (samples nearly silent)

**Suspected Causes**:
1. Phase cancellation between Input module output and sampler outputs
2. Buffer state corruption when switching from `sv_audio_callback` to `sv_audio_callback2`
3. Render order issues in SunVox when Input module activates mid-playback

### 2. Offset Mismatch (Investigated, Not Root Cause)

The Input module writes at `recording_output[ch] + offset`, but playback reads from base pointer. Investigation showed `offset` was always 0, so this wasn't the cause.

### 3. Timing Issues with Async Volume Control

`sv_set_input_monitor_volume()` originally used async events. Fixed by creating `sv_set_input_monitor_volume_direct()` for immediate controller access.

---

## Why This Approach Was Abandoned

1. **Complexity** - 3 files modified, custom SunVox APIs, dual-buffer management
2. **Order-dependent bug** - Samples vs recording order affected output
3. **Debugging difficulty** - Multiple points of failure in the audio path
4. **Phase cancellation risk** - Mic data in SunVox could interfere with samples

---

## Replacement: Simple Direct Mixing

The simplified approach keeps mic completely separate from SunVox:

```cpp
// Always use sv_audio_callback (no mic data to SunVox)
result = sv_audio_callback(pOutput, frameCount, 0, sv_get_ticks());

// Mix mic directly for recording
if (recording_is_active() && mic_input_is_active()) {
    mic_input_read_frames(mic_buffer, frameCount);
    for (int i = 0; i < frameCount * 2; i++) {
        recording_mix_buffer[i] = pOutput[i] + mic_buffer[i];
    }
    recording_write_frames_from_callback(recording_mix_buffer, frameCount);
}
```

Benefits:
- No SunVox modifications needed
- No interference between mic and samples
- Order-independent (samples can be added before or after recording)
- Simpler debugging

---

## References

- [microphone_integration.md](microphone_integration.md) - Debug history and findings
- `native/playback_sunvox.mm` - Audio callback implementation
- `native/sunvox_lib/lib_sunvox/psynth/psynths_input.cpp` - Input module source
- `native/sunvox_wrapper.mm` - SunVox wrapper with Input module management
