#ifndef RECORDING_H
#define RECORDING_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Original recording functions (output recording logic)
// Sample bank functions (forward declarations)
__attribute__((visibility("default"))) __attribute__((used))
int recording_start(const char* file_path);

__attribute__((visibility("default"))) __attribute__((used))
void recording_stop(void);

__attribute__((visibility("default"))) __attribute__((used))
int recording_is_active(void);

// Write audio frames from callback (called from playback_sunvox.mm audio callback)
__attribute__((visibility("default"))) __attribute__((used))
void recording_write_frames_from_callback(const float* frames, int frame_count);

// NEW: Waveform visualization function (added for Layer 5 visualization)
// Read WAV samples for visualization (downsampled if needed)
// Parameters:
//   wav_path: Path to WAV file
//   buffer: Output buffer for int16 samples
//   max_samples: Maximum number of samples to read
//   downsample_factor: Read every Nth sample (1 = no downsampling, 10 = every 10th sample)
// Returns: Number of samples read, or negative error code
__attribute__((visibility("default"))) __attribute__((used))
int recording_get_waveform_samples(const char* wav_path, 
                                   int16_t* buffer, 
                                   int max_samples,
                                   int downsample_factor);

#ifdef __cplusplus
}
#endif

#endif // RECORDING_H
