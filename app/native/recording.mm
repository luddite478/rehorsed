#include "recording.h"
#include <pthread.h>
#include <unistd.h>
#include <stdio.h>
#include <stdint.h>

// Include SunVox for audio capture
#define SUNVOX_STATIC_LIB
#include "sunvox.h"

// Include miniaudio for WAV encoding (header only, no device needed)
#define MA_NO_DEVICE_IO
#include "miniaudio/miniaudio.h"

// Platform-specific logging
#ifdef __APPLE__
    #include "log.h"
    #undef LOG_TAG
    #define LOG_TAG "RECORDING"
#elif defined(__ANDROID__)
    #include "log.h"
    #undef LOG_TAG
    #define LOG_TAG "RECORDING"
#else
    #include "log.h"
    #undef LOG_TAG
    #define LOG_TAG "RECORDING"
#endif

// Recording state
static int g_is_output_recording = 0;
static int g_output_encoder_initialized = 0;
static ma_encoder g_output_encoder;
static pthread_mutex_t g_encoder_mutex = PTHREAD_MUTEX_INITIALIZER;

// Write audio frames from callback (thread-safe)
// Called from playback_sunvox.mm audio callback
void recording_write_frames_from_callback(const float* frames, int frame_count) {
    if (!g_is_output_recording || !g_output_encoder_initialized) {
        return;
    }
    
    pthread_mutex_lock(&g_encoder_mutex);
    
    // Write to encoder
    ma_uint64 frames_written = 0;
    ma_result result = ma_encoder_write_pcm_frames(&g_output_encoder, frames, frame_count, &frames_written);
    
    if (result != MA_SUCCESS) {
        prnt_err("❌ [RECORDING] Failed to write frames from callback: %d", result);
    }
    
    pthread_mutex_unlock(&g_encoder_mutex);
}

// Start recording output to WAV file
int recording_start(const char* file_path) {
    if (g_is_output_recording) {
        prnt_err("❌ [RECORDING] Already recording");
        return -2;
    }
    
    prnt("🎙️ [RECORDING] Starting recording to: %s", file_path);
    
    // Initialize encoder for WAV output
    // Use float32 format to match SunVox output
    ma_encoder_config encoder_config = ma_encoder_config_init(
        ma_encoding_format_wav,  // WAV format
        ma_format_f32,           // Float32 samples
        2,                       // Stereo
        48000                    // 48kHz (match SunVox)
    );
    
    ma_result result = ma_encoder_init_file(file_path, &encoder_config, &g_output_encoder);
    if (result != MA_SUCCESS) {
        prnt_err("❌ [RECORDING] Failed to initialize encoder: %d", result);
        return -3;
    }
    
    g_output_encoder_initialized = 1;
    g_is_output_recording = 1;
    
    prnt("✅ [RECORDING] Recording started → %s", file_path);
    return 0;
}

// Stop recording
void recording_stop(void) {
    if (!g_is_output_recording) return;
    
    prnt("⏹️ [RECORDING] Stopping recording");
    
    // Signal recording stopped
    g_is_output_recording = 0;
    
    // Close encoder (thread-safe)
    pthread_mutex_lock(&g_encoder_mutex);
    if (g_output_encoder_initialized) {
        ma_encoder_uninit(&g_output_encoder);
        g_output_encoder_initialized = 0;
    }
    pthread_mutex_unlock(&g_encoder_mutex);
    
    prnt("✅ [RECORDING] Recording stopped");
}

// Check if recording is active
int recording_is_active(void) {
    return g_is_output_recording;
}

// ========================================================================
// WAVEFORM VISUALIZATION FUNCTIONS (Added for Layer 5 visualization)
// ========================================================================

// Read WAV samples for visualization (downsampled if needed)
int recording_get_waveform_samples(const char* wav_path, 
                                   int16_t* buffer, 
                                   int max_samples,
                                   int downsample_factor) {
    if (!wav_path || !buffer || max_samples <= 0 || downsample_factor <= 0) {
        prnt("❌ [RECORDING] Invalid parameters for waveform reading");
        return -1;
    }
    
    FILE* fp = fopen(wav_path, "rb");
    if (!fp) {
        prnt("❌ [RECORDING] Failed to open WAV file: %s", wav_path);
        return -1;
    }
    
    // Read WAV header (44 bytes minimum for standard WAV)
    uint8_t header[44];
    if (fread(header, 1, 44, fp) != 44) {
        prnt("❌ [RECORDING] Failed to read WAV header");
        fclose(fp);
        return -1;
    }
    
    // Verify RIFF header
    if (header[0] != 'R' || header[1] != 'I' || header[2] != 'F' || header[3] != 'F') {
        prnt("❌ [RECORDING] Invalid WAV file (not RIFF)");
        fclose(fp);
        return -1;
    }
    
    // Verify WAVE format
    if (header[8] != 'W' || header[9] != 'A' || header[10] != 'V' || header[11] != 'E') {
        prnt("❌ [RECORDING] Invalid WAV file (not WAVE)");
        fclose(fp);
        return -1;
    }
    
    // Get number of channels (bytes 22-23)
    uint16_t num_channels = header[22] | (header[23] << 8);
    
    // Get sample rate (bytes 24-27)
    uint32_t sample_rate = header[24] | (header[25] << 8) | (header[26] << 16) | (header[27] << 24);
    
    // Get bits per sample (bytes 34-35)
    uint16_t bits_per_sample = header[34] | (header[35] << 8);
    
    prnt("📊 [RECORDING] WAV info: %d channels, %d Hz, %d bits", num_channels, sample_rate, bits_per_sample);
    
    // Skip to data chunk (header is 44 bytes for standard WAV)
    fseek(fp, 44, SEEK_SET);
    
    int samples_read = 0;
    
    // Handle float32 WAV (from our recording output)
    if (bits_per_sample == 32) {
        float temp_buffer[2]; // Stereo sample (float32)
        
        for (int i = 0; i < max_samples; i++) {
            // Skip downsample_factor - 1 samples
            for (int j = 0; j < downsample_factor - 1; j++) {
                if (num_channels == 2) {
                    if (fread(temp_buffer, sizeof(float), 2, fp) != 2) {
                        goto done; // End of file
                    }
                } else {
                    if (fread(temp_buffer, sizeof(float), 1, fp) != 1) {
                        goto done; // End of file
                    }
                }
            }
            
            // Read one sample
            if (num_channels == 2) {
                if (fread(temp_buffer, sizeof(float), 2, fp) != 2) {
                    goto done; // End of file
                }
                // Mix stereo to mono and convert float32 to int16
                float mixed = (temp_buffer[0] + temp_buffer[1]) / 2.0f;
                buffer[i] = (int16_t)(mixed * 32767.0f);
            } else {
                if (fread(temp_buffer, sizeof(float), 1, fp) != 1) {
                    goto done; // End of file
                }
                // Convert float32 to int16
                buffer[i] = (int16_t)(temp_buffer[0] * 32767.0f);
            }
            
            samples_read++;
        }
    }
    // Handle int16 WAV
    else if (bits_per_sample == 16) {
        int16_t temp_buffer[2]; // Stereo sample
        
        for (int i = 0; i < max_samples; i++) {
            // Skip downsample_factor - 1 samples
            for (int j = 0; j < downsample_factor - 1; j++) {
                if (num_channels == 2) {
                    if (fread(temp_buffer, sizeof(int16_t), 2, fp) != 2) {
                        goto done; // End of file
                    }
                } else {
                    if (fread(temp_buffer, sizeof(int16_t), 1, fp) != 1) {
                        goto done; // End of file
                    }
                }
            }
            
            // Read one sample
            if (num_channels == 2) {
                if (fread(temp_buffer, sizeof(int16_t), 2, fp) != 2) {
                    goto done; // End of file
                }
                // Mix stereo to mono
                buffer[i] = (temp_buffer[0] + temp_buffer[1]) / 2;
            } else {
                if (fread(temp_buffer, sizeof(int16_t), 1, fp) != 1) {
                    goto done; // End of file
                }
                buffer[i] = temp_buffer[0];
            }
            
            samples_read++;
        }
    }
    else {
        prnt("❌ [RECORDING] Unsupported bits per sample: %d", bits_per_sample);
        fclose(fp);
        return -1;
    }
    
done:
    fclose(fp);
    
    if (samples_read > 0) {
        prnt("✅ [RECORDING] Read %d waveform samples (downsample factor: %d)", samples_read, downsample_factor);
    }
    
    return samples_read;
}
