#include "microphone_input.h"
#include "log.h"
#include <pthread.h>
#include <string.h>
#include <math.h>
#include <unistd.h>

#ifdef __APPLE__
#undef LOG_TAG
#define LOG_TAG "MIC_INPUT"
#define MIC_START_FAIL_LABEL "[MIC_START_FAIL]"
#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>

// Circular buffer for microphone samples
#define MIC_BUFFER_SIZE (48000 * 2 * 2) // 2 seconds of stereo float32 at 48kHz
static float g_mic_buffer[MIC_BUFFER_SIZE];
static int g_mic_write_pos = 0;
static int g_mic_read_pos = 0;
static pthread_mutex_t g_mic_mutex = PTHREAD_MUTEX_INITIALIZER;

// AVAudioEngine state
static AVAudioEngine* g_audio_engine = nil;
static AVAudioInputNode* g_input_node = nil;
static int g_is_initialized = 0;
static int g_is_active = 0;

// Microphone input volume (0.0 - 1.0)
static float g_mic_volume = 1.0f;

// Audio route information
static char g_current_audio_route[256] = "Unknown";
static int g_is_bluetooth_input = 0;

// Resampling state (for 16kHz -> 48kHz conversion)
static double g_input_sample_rate = 48000.0;
static float g_last_left_sample = 0.0f;
static float g_last_right_sample = 0.0f;

static BOOL mic_is_wired_input_port_type(NSString* portType) {
    if (!portType) return NO;
    return [portType isEqualToString:AVAudioSessionPortHeadsetMic] ||
           [portType isEqualToString:AVAudioSessionPortUSBAudio] ||
           [portType isEqualToString:AVAudioSessionPortLineIn];
}

static void mic_refresh_current_input_state(AVAudioSession* session) {
    if (!session) return;
    AVAudioSessionRouteDescription* route = [session currentRoute];
    if (!route || route.inputs.count == 0) return;

    AVAudioSessionPortDescription* input = route.inputs[0];
    if (!input) return;

    snprintf(g_current_audio_route, sizeof(g_current_audio_route), "%s",
             [input.portName UTF8String] ?: "Unknown");
    NSString* portType = input.portType;
    g_is_bluetooth_input = ([portType isEqualToString:AVAudioSessionPortBluetoothHFP] ||
                            [portType isEqualToString:AVAudioSessionPortBluetoothLE]) ? 1 : 0;
}

// Prefer wired headset mic when present, otherwise built-in mic.
// Bluetooth is intentionally deprioritized in the current simple path.
static void mic_try_force_builtin_input(AVAudioSession* session) {
    if (!session) return;
    @try {
        NSArray<AVAudioSessionPortDescription*>* availableInputs = [session availableInputs];
        if (!availableInputs || availableInputs.count == 0) {
            prnt("ℹ️ [MIC_INPUT] No available inputs while forcing built-in mic");
            return;
        }

        AVAudioSessionPortDescription* preferredInput = nil;
        // 1) Prefer wired microphone class (headset/USB/line-in).
        for (AVAudioSessionPortDescription* port in availableInputs) {
            if (mic_is_wired_input_port_type(port.portType)) {
                preferredInput = port;
                break;
            }
        }
        // 2) Fallback to built-in mic.
        if (!preferredInput) {
            for (AVAudioSessionPortDescription* port in availableInputs) {
                if ([port.portType isEqualToString:AVAudioSessionPortBuiltInMic]) {
                    preferredInput = port;
                    break;
                }
            }
        }

        if (!preferredInput) {
            prnt("ℹ️ [MIC_INPUT] No wired/built-in preferred input found, keeping current input");
            return;
        }

        NSError* prefErr = nil;
        BOOL ok = [session setPreferredInput:preferredInput error:&prefErr];
        if (!ok || prefErr) {
            prnt_err("⚠️ [MIC_INPUT] Could not set preferred wired/built-in mic: %{public}s",
                     prefErr ? [[prefErr localizedDescription] UTF8String] : "unknown");
            return;
        }

        mic_refresh_current_input_state(session);
        prnt("✅ [MIC_INPUT] Preferred input selected: %s (type: %s)",
             [preferredInput.portName UTF8String] ?: "Preferred Mic",
             [preferredInput.portType UTF8String] ?: "unknown");
    } @catch (NSException* e) {
        prnt_err("⚠️ [MIC_INPUT] Exception forcing built-in mic: %{public}s",
                 [[e reason] UTF8String] ?: "unknown");
    }
}

// SIMPLIFIED: Initialize microphone input system
int mic_input_init(void) {
    pthread_mutex_lock(&g_mic_mutex);
    
    if (g_is_initialized) {
        pthread_mutex_unlock(&g_mic_mutex);
        prnt("✅ [MIC_INPUT] Already initialized");
        return 0;
    }
    
    prnt("🎙️ [MIC_INPUT] Initializing microphone input system (simplified)");
    
    // Clear circular buffer
    memset(g_mic_buffer, 0, sizeof(g_mic_buffer));
    g_mic_write_pos = 0;
    g_mic_read_pos = 0;
    
    g_is_initialized = 1;
    pthread_mutex_unlock(&g_mic_mutex);
    
    prnt("✅ [MIC_INPUT] Microphone input system ready");
    return 0;
}

// SIMPLIFIED: Start capturing microphone input
// Just set up audio session once and start the tap - let iOS handle routing
int mic_input_start(void) {
    pthread_mutex_lock(&g_mic_mutex);
    prnt("🔎 [MIC_INPUT] %s Enter mic_input_start()", MIC_START_FAIL_LABEL);
    prnt("🧪 [MIC_INPUT] [MIC_DIAG_V2] Enhanced mic diagnostics build active");
    
    if (!g_is_initialized) {
        pthread_mutex_unlock(&g_mic_mutex);
        prnt_err("❌ [MIC_INPUT] Not initialized");
        return -1;
    }
    
    if (g_is_active) {
        pthread_mutex_unlock(&g_mic_mutex);
        prnt("⚠️ [MIC_INPUT] Already active");
        return -2;
    }
    
    prnt("🎙️ [MIC_INPUT] Starting microphone capture (simplified)");
    
    // Create engine if not already created
    if (!g_audio_engine) {
        // Ensure the session is record-capable before touching AVAudioInputNode.
        // If another subsystem switched category to Playback, input format can be 0 Hz.
        @try {
            AVAudioSession* session = [AVAudioSession sharedInstance];
            NSString* currentCategory = [session category];
            AVAudioSessionCategoryOptions currentOptions = [session categoryOptions];
            prnt("🎙️ [MIC_INPUT] Session on mic start: category=%s options=0x%lx",
                 [currentCategory UTF8String] ?: "unknown",
                 (unsigned long)currentOptions);

            BOOL isRecordCapable =
                [currentCategory isEqualToString:AVAudioSessionCategoryPlayAndRecord] ||
                [currentCategory isEqualToString:AVAudioSessionCategoryRecord] ||
                [currentCategory isEqualToString:AVAudioSessionCategoryMultiRoute];

            if (!isRecordCapable) {
                prnt("🔁 [MIC_INPUT] %s Session category is not record-capable (%s). Switching to PlayAndRecord.",
                     MIC_START_FAIL_LABEL, [currentCategory UTF8String] ?: "unknown");

                NSError* sessionErr = nil;
                BOOL categorySet = [session setCategory:AVAudioSessionCategoryPlayAndRecord
                                            withOptions:AVAudioSessionCategoryOptionMixWithOthers |
                                                       AVAudioSessionCategoryOptionDefaultToSpeaker
                                                  error:&sessionErr];
                if (!categorySet || sessionErr) {
                    prnt_err("❌ [MIC_INPUT] %s Pre-engine setCategory failed: %{public}s",
                             MIC_START_FAIL_LABEL,
                             sessionErr ? [[sessionErr localizedDescription] UTF8String] : "unknown");
                } else {
                    sessionErr = nil;
                    [session setPreferredSampleRate:48000.0 error:&sessionErr];
                    if (sessionErr) {
                        prnt_err("❌ [MIC_INPUT] %s Pre-engine setPreferredSampleRate warning: %{public}s",
                                 MIC_START_FAIL_LABEL, [[sessionErr localizedDescription] UTF8String]);
                    }

                    sessionErr = nil;
                    BOOL activated = [session setActive:YES error:&sessionErr];
                    if (!activated || sessionErr) {
                        prnt_err("❌ [MIC_INPUT] %s Pre-engine setActive failed: %{public}s",
                                 MIC_START_FAIL_LABEL,
                                 sessionErr ? [[sessionErr localizedDescription] UTF8String] : "unknown");
                    } else {
                        prnt("✅ [MIC_INPUT] %s Session switched to PlayAndRecord before engine init",
                             MIC_START_FAIL_LABEL);
                    }
                }

                currentCategory = [session category];
                currentOptions = [session categoryOptions];
                prnt("🎙️ [MIC_INPUT] Session after pre-engine ensure: category=%s options=0x%lx",
                     [currentCategory UTF8String] ?: "unknown",
                     (unsigned long)currentOptions);
            }

            // DON'T force speaker - let iOS route naturally based on what's connected.
            // This allows Bluetooth to work properly.
            AVAudioSessionRouteDescription* currentRoute = [session currentRoute];
            if (currentRoute.inputs.count > 0) {
                AVAudioSessionPortDescription* input = currentRoute.inputs[0];
                prnt("🎤 [MIC_INPUT] Current input: %s (type: %s)", 
                    [input.portName UTF8String] ?: "Unknown",
                    [input.portType UTF8String] ?: "Unknown");
                
                snprintf(g_current_audio_route, sizeof(g_current_audio_route), "%s", 
                        [input.portName UTF8String] ?: "Unknown");
                
                NSString* portType = input.portType;
                g_is_bluetooth_input = ([portType isEqualToString:AVAudioSessionPortBluetoothHFP] ||
                                       [portType isEqualToString:AVAudioSessionPortBluetoothLE]);
            }
            
            if (currentRoute.outputs.count > 0) {
                AVAudioSessionPortDescription* output = currentRoute.outputs[0];
                prnt("🔊 [MIC_INPUT] Current output: %s (type: %s)", 
                    [output.portName UTF8String] ?: "Unknown",
                    [output.portType UTF8String] ?: "Unknown");
                
                // Warn if using Bluetooth for both input and output (HFP mode = low quality)
                NSString* outputType = output.portType;
                if (g_is_bluetooth_input && 
                    ([outputType isEqualToString:AVAudioSessionPortBluetoothHFP] ||
                     [outputType isEqualToString:AVAudioSessionPortBluetoothLE])) {
                    prnt("⚠️ [MIC_INPUT] WARNING: Bluetooth bidirectional audio uses HFP (low quality ~16kHz)");
                    prnt("💡 [MIC_INPUT] TIP: For better quality, use iPhone mic + Bluetooth output");
                }
            }
            
        } @catch (NSException* e) {
            pthread_mutex_unlock(&g_mic_mutex);
            prnt_err("❌ [MIC_INPUT] %s Exception inspecting audio session: %{public}s",
                     MIC_START_FAIL_LABEL, [[e reason] UTF8String] ?: "unknown");
            return -4;
        }
        
        // Create audio engine
        g_audio_engine = [[AVAudioEngine alloc] init];
        if (!g_audio_engine) {
            pthread_mutex_unlock(&g_mic_mutex);
            prnt_err("❌ [MIC_INPUT] %s Failed to create AVAudioEngine", MIC_START_FAIL_LABEL);
            return -3;
        }
        
        g_input_node = [g_audio_engine inputNode];
        if (!g_input_node) {
            g_audio_engine = nil;
            pthread_mutex_unlock(&g_mic_mutex);
            prnt_err("❌ [MIC_INPUT] %s Failed to get input node", MIC_START_FAIL_LABEL);
            return -3;
        }
        prnt("✅ [MIC_INPUT] AVAudioEngine and input node created");
    }
    
    // Lightweight preference pass on every start to keep v1 path on built-in mic.
    // Keep this minimal: no extra session category/activation churn here.
    @try {
        AVAudioSession* session = [AVAudioSession sharedInstance];
        mic_try_force_builtin_input(session);
    } @catch (NSException* e) {
        prnt_err("⚠️ [MIC_INPUT] Built-in mic preference pass failed: %{public}s",
                 [[e reason] UTF8String] ?: "unknown");
    }

    // Use the input node's native format (simplest, most compatible)
    AVAudioFormat* inputFormat = [g_input_node outputFormatForBus:0];
    g_input_sample_rate = inputFormat ? inputFormat.sampleRate : 0.0;

    int inputChannels = inputFormat ? (int)inputFormat.channelCount : 0;

    // Some devices/routes can temporarily report 0Hz before the session is fully ready.
    // Recover by re-applying a record-capable session and re-priming AVAudioEngine.
    for (int attempt = 1; attempt <= 3; attempt++) {
        if (inputFormat && g_input_sample_rate > 1.0 && inputChannels > 0) {
            break;
        }

        prnt_err("❌ [MIC_INPUT] %s Invalid input format before tap (attempt %d/3): hasFormat=%d rate=%.2f channels=%d",
                 MIC_START_FAIL_LABEL, attempt, inputFormat ? 1 : 0, g_input_sample_rate, inputChannels);

        @try {
            AVAudioSession* session = [AVAudioSession sharedInstance];
            NSError* sessionErr = nil;
            BOOL categorySet = [session setCategory:AVAudioSessionCategoryPlayAndRecord
                                        withOptions:AVAudioSessionCategoryOptionMixWithOthers |
                                                   AVAudioSessionCategoryOptionDefaultToSpeaker
                                              error:&sessionErr];
            if (!categorySet || sessionErr) {
                prnt_err("❌ [MIC_INPUT] %s Format recovery setCategory failed: %{public}s",
                         MIC_START_FAIL_LABEL,
                         sessionErr ? [[sessionErr localizedDescription] UTF8String] : "unknown");
            }

            sessionErr = nil;
            [session setPreferredSampleRate:48000.0 error:&sessionErr];
            if (sessionErr) {
                prnt_err("❌ [MIC_INPUT] %s Format recovery setPreferredSampleRate warning: %{public}s",
                         MIC_START_FAIL_LABEL, [[sessionErr localizedDescription] UTF8String]);
            }

            sessionErr = nil;
            BOOL activated = [session setActive:YES error:&sessionErr];
            if (!activated || sessionErr) {
                prnt_err("❌ [MIC_INPUT] %s Format recovery setActive failed: %{public}s",
                         MIC_START_FAIL_LABEL,
                         sessionErr ? [[sessionErr localizedDescription] UTF8String] : "unknown");
            }
        } @catch (NSException* e) {
            prnt_err("❌ [MIC_INPUT] %s Format recovery exception: %{public}s",
                     MIC_START_FAIL_LABEL, [[e reason] UTF8String] ?: "unknown");
        }

        // Re-prime engine/input node because stale AVAudioInputNode can keep reporting 0Hz.
        @try {
            if (g_audio_engine) {
                [g_audio_engine stop];
            }
            g_audio_engine = [[AVAudioEngine alloc] init];
            g_input_node = g_audio_engine ? [g_audio_engine inputNode] : nil;
        } @catch (NSException* e) {
            g_audio_engine = nil;
            g_input_node = nil;
            prnt_err("❌ [MIC_INPUT] %s Engine re-prime exception: %{public}s",
                     MIC_START_FAIL_LABEL, [[e reason] UTF8String] ?: "unknown");
        }

        // Give CoreAudio a moment to finalize route/session state.
        usleep(50000);

        inputFormat = g_input_node ? [g_input_node outputFormatForBus:0] : nil;
        g_input_sample_rate = inputFormat ? inputFormat.sampleRate : 0.0;
        inputChannels = inputFormat ? (int)inputFormat.channelCount : 0;

        prnt("🔁 [MIC_INPUT] %s Format recovery result (attempt %d/3): hasFormat=%d rate=%.2f channels=%d",
             MIC_START_FAIL_LABEL, attempt, inputFormat ? 1 : 0, g_input_sample_rate, inputChannels);
    }

    prnt("🎙️ [MIC_INPUT] Input format: %.0f Hz, %d channels",
         g_input_sample_rate, inputChannels);
    
    // Check if we need resampling (target is always 48kHz)
    const double TARGET_RATE = 48000.0;
    double resampleRatio = (g_input_sample_rate > 1.0) ? (TARGET_RATE / g_input_sample_rate) : 0.0;
    
    if (fabs(g_input_sample_rate - TARGET_RATE) < 100.0) {
        prnt("✅ [MIC_INPUT] ~48kHz native - no resampling needed");
    } else if (g_input_sample_rate == 16000.0) {
        prnt("⚠️ [MIC_INPUT] 16kHz (Bluetooth HFP) - will resample 3x to 48kHz");
    } else if (g_input_sample_rate == 44100.0) {
        prnt("⚠️ [MIC_INPUT] 44.1kHz (CD quality) - will resample %.2fx to 48kHz", resampleRatio);
    } else if (g_input_sample_rate == 8000.0) {
        prnt("⚠️ [MIC_INPUT] 8kHz (low quality) - will resample 6x to 48kHz");
    } else if (g_input_sample_rate > 1.0) {
        prnt("⚠️ [MIC_INPUT] Unusual rate %.0f Hz - will resample %.2fx to 48kHz", 
            g_input_sample_rate, resampleRatio);
    } else {
        prnt_err("❌ [MIC_INPUT] %s Input sample rate still invalid after recovery (%.2f Hz)",
                 MIC_START_FAIL_LABEL, g_input_sample_rate);
    }
    
    // Reset resampling state
    g_last_left_sample = 0.0f;
    g_last_right_sample = 0.0f;
    
    // Record permission and format must be valid before installing a tap.
    AVAudioSessionRecordPermission recordPermission =
        [[AVAudioSession sharedInstance] recordPermission];
    const char* permissionLabel = "unknown";
    if (recordPermission == AVAudioSessionRecordPermissionGranted) {
        permissionLabel = "granted";
    } else if (recordPermission == AVAudioSessionRecordPermissionDenied) {
        permissionLabel = "denied";
    } else if (recordPermission == AVAudioSessionRecordPermissionUndetermined) {
        permissionLabel = "undetermined";
    }
    prnt("🔐 [MIC_INPUT] Record permission before tap: %s (%ld)",
         permissionLabel, (long)recordPermission);

    if (recordPermission != AVAudioSessionRecordPermissionGranted) {
        pthread_mutex_unlock(&g_mic_mutex);
        prnt_err("❌ [MIC_INPUT] %s [TAP_PERMISSION] Record permission is not granted (%s, %ld)",
                 MIC_START_FAIL_LABEL, permissionLabel, (long)recordPermission);
        return -3;
    }

    if (!inputFormat || g_input_sample_rate <= 1.0 || inputChannels <= 0) {
        pthread_mutex_unlock(&g_mic_mutex);
        prnt_err("❌ [MIC_INPUT] %s [TAP_FORMAT_INVALID] Cannot install tap with invalid format (hasFormat=%d rate=%.2f channels=%d)",
                 MIC_START_FAIL_LABEL, inputFormat ? 1 : 0, g_input_sample_rate, inputChannels);
        return -3;
    }

    // Remove any existing tap
    @try {
        [g_input_node removeTapOnBus:0];
        prnt("✅ [MIC_INPUT] Removed existing tap");
    } @catch (NSException* e) {
        prnt("ℹ️ [MIC_INPUT] No existing tap to remove");
    }
    
    // Install tap on input node with native format
    @try {
    [g_input_node installTapOnBus:0 bufferSize:1024 format:inputFormat block:^(AVAudioPCMBuffer* buffer, AVAudioTime* when) {
        pthread_mutex_lock(&g_mic_mutex);
        
            if (!g_is_active || !buffer.floatChannelData || buffer.frameLength == 0) {
            pthread_mutex_unlock(&g_mic_mutex);
            return;
        }
        
        // Get audio data (handle mono/stereo)
        float* leftChannel = buffer.floatChannelData[0];
        float* rightChannel = (buffer.format.channelCount > 1) ? buffer.floatChannelData[1] : leftChannel;
        int frameCount = (int)buffer.frameLength;
        
            // GENERIC RESAMPLER: Handle any input rate -> 48kHz output
            double inputRate = buffer.format.sampleRate;
            const double TARGET_RATE = 48000.0;
            double resampleRatio = (inputRate > 1.0) ? (TARGET_RATE / inputRate) : 0.0;
            
            // Determine if we need resampling
            if (inputRate <= 1.0) {
                // Invalid runtime rate - skip this buffer safely.
                pthread_mutex_unlock(&g_mic_mutex);
                return;
            } else if (fabs(inputRate - TARGET_RATE) < 100.0) {
                // Close enough to 48kHz - pass through without resampling
                for (int i = 0; i < frameCount; i++) {
                    g_mic_buffer[g_mic_write_pos++] = leftChannel[i] * g_mic_volume;
                    g_mic_buffer[g_mic_write_pos++] = rightChannel[i] * g_mic_volume;
                    
                    if (g_mic_write_pos >= MIC_BUFFER_SIZE) g_mic_write_pos = 0;
                    if (g_mic_write_pos == g_mic_read_pos) {
                        g_mic_read_pos += 2;
                        if (g_mic_read_pos >= MIC_BUFFER_SIZE) g_mic_read_pos = 0;
                    }
                }
            } else {
                // Need resampling - use linear interpolation
                // Calculate how many output samples we'll generate
                int outputFrames = (int)(frameCount * resampleRatio);
                
                // Safety check: Don't overflow buffer
                int maxOutputFrames = (MIC_BUFFER_SIZE / 2) / 4; // Conservative limit
                if (outputFrames > maxOutputFrames) {
                    outputFrames = maxOutputFrames;
                }
                
                // Generate output samples with linear interpolation
                for (int outIdx = 0; outIdx < outputFrames; outIdx++) {
                    // Calculate input position (with fractional part)
                    double inputPos = outIdx / resampleRatio;
                    int inputIdx = (int)inputPos;
                    double fraction = inputPos - inputIdx;
                    
                    // Bounds check
                    if (inputIdx >= frameCount - 1) {
                        inputIdx = frameCount - 2;
                        if (inputIdx < 0) inputIdx = 0;
                    }
                    
                    // Linear interpolation between samples
                    float left1 = leftChannel[inputIdx] * g_mic_volume;
                    float left2 = leftChannel[inputIdx + 1] * g_mic_volume;
                    float right1 = rightChannel[inputIdx] * g_mic_volume;
                    float right2 = rightChannel[inputIdx + 1] * g_mic_volume;
                    
                    float leftOut = left1 + (left2 - left1) * fraction;
                    float rightOut = right1 + (right2 - right1) * fraction;
                    
                    // Write to circular buffer
                    g_mic_buffer[g_mic_write_pos++] = leftOut;
                    g_mic_buffer[g_mic_write_pos++] = rightOut;
                    
                    if (g_mic_write_pos >= MIC_BUFFER_SIZE) g_mic_write_pos = 0;
                    if (g_mic_write_pos == g_mic_read_pos) {
                        g_mic_read_pos += 2;
                        if (g_mic_read_pos >= MIC_BUFFER_SIZE) g_mic_read_pos = 0;
                    }
                }
            }
        
        pthread_mutex_unlock(&g_mic_mutex);
    }];
    
    } @catch (NSException* e) {
        pthread_mutex_unlock(&g_mic_mutex);
        prnt_err("❌ [MIC_INPUT] %s [TAP_INSTALL_EXCEPTION] Exception installing tap (name=%{public}s reason=%{public}s)",
                 MIC_START_FAIL_LABEL,
                 [[e name] UTF8String] ?: "unknown",
                 [[e reason] UTF8String] ?: "unknown");
        return -3;
    }
    
    // Start audio engine
    if (![g_audio_engine isRunning]) {
        NSError* error = nil;
        BOOL success = [g_audio_engine startAndReturnError:&error];
        
        if (!success || error) {
            prnt_err("❌ [MIC_INPUT] %s First startAndReturnError failed: %{public}s",
                    MIC_START_FAIL_LABEL,
                    error ? [[error localizedDescription] UTF8String] : "unknown");

            // Recovery path: another subsystem may have changed AVAudioSession category.
            // Re-apply PlayAndRecord config and retry once.
            @try {
                AVAudioSession* session = [AVAudioSession sharedInstance];
                NSError* sessionErr = nil;
                BOOL categorySet = [session setCategory:AVAudioSessionCategoryPlayAndRecord
                                            withOptions:AVAudioSessionCategoryOptionMixWithOthers |
                                                       AVAudioSessionCategoryOptionDefaultToSpeaker
                                                  error:&sessionErr];
                if (!categorySet || sessionErr) {
                    prnt_err("❌ [MIC_INPUT] %s Recovery setCategory failed: %{public}s",
                             MIC_START_FAIL_LABEL,
                             sessionErr ? [[sessionErr localizedDescription] UTF8String] : "unknown");
                } else {
                    [session setPreferredSampleRate:48000.0 error:&sessionErr];
                    sessionErr = nil;
                    BOOL activated = [session setActive:YES error:&sessionErr];
                    if (!activated || sessionErr) {
                        prnt_err("❌ [MIC_INPUT] %s Recovery setActive failed: %{public}s",
                                 MIC_START_FAIL_LABEL,
                                 sessionErr ? [[sessionErr localizedDescription] UTF8String] : "unknown");
                    } else {
                        prnt("🔁 [MIC_INPUT] %s Recovery session applied, retrying audio engine start",
                             MIC_START_FAIL_LABEL);
                    }
                }
            } @catch (NSException* e) {
                prnt_err("❌ [MIC_INPUT] %s Recovery exception: %{public}s",
                         MIC_START_FAIL_LABEL, [[e reason] UTF8String] ?: "unknown");
            }

            error = nil;
            success = [g_audio_engine startAndReturnError:&error];
            if (!success || error) {
                [g_input_node removeTapOnBus:0];
                pthread_mutex_unlock(&g_mic_mutex);
                prnt_err("❌ [MIC_INPUT] %s Failed to start audio engine after recovery: %{public}s",
                        MIC_START_FAIL_LABEL,
                        error ? [[error localizedDescription] UTF8String] : "unknown");
                return -3;
            }
            prnt("✅ [MIC_INPUT] %s Audio engine started after session recovery", MIC_START_FAIL_LABEL);
        }
        prnt("✅ [MIC_INPUT] Audio engine started");
    } else {
        prnt("✅ [MIC_INPUT] Audio engine already running");
    }
    
    g_is_active = 1;
    @try {
        AVAudioSession* session = [AVAudioSession sharedInstance];
        mic_refresh_current_input_state(session);
    } @catch (NSException* e) {
        prnt_err("⚠️ [MIC_INPUT] Failed to refresh current route after start: %{public}s",
                 [[e reason] UTF8String] ?: "unknown");
    }
    pthread_mutex_unlock(&g_mic_mutex);
    
    prnt("✅ [MIC_INPUT] Microphone capture started successfully");
    return 0;
}

// SIMPLIFIED: Stop capturing microphone input
void mic_input_stop(void) {
    pthread_mutex_lock(&g_mic_mutex);
    
    if (!g_is_active) {
        pthread_mutex_unlock(&g_mic_mutex);
        prnt("⚠️ [MIC_INPUT] Stop called but not active");
        return;
    }
    
    prnt("⏹️ [MIC_INPUT] Stopping microphone capture");
    
    g_is_active = 0;
    
    // Remove tap
    @try {
        if (g_input_node) {
            [g_input_node removeTapOnBus:0];
            prnt("✅ [MIC_INPUT] Tap removed");
        }
    } @catch (NSException* e) {
        prnt_err("⚠️ [MIC_INPUT] Exception removing tap: %s", [[e reason] UTF8String]);
    }
    
    // Keep engine running for instant restart
    // Clear buffer
    g_mic_write_pos = 0;
    g_mic_read_pos = 0;
    
    pthread_mutex_unlock(&g_mic_mutex);
    
    prnt("✅ [MIC_INPUT] Microphone capture stopped");
}

// Check if microphone is currently active
int mic_input_is_active(void) {
    return g_is_active;
}

// Get current audio level (RMS) for visualization
float mic_input_get_level(void) {
    if (!g_is_active) return 0.0f;
    
    pthread_mutex_lock(&g_mic_mutex);
    
    // Sample last 100ms worth of data for level meter
    int samplesToCheck = 4800 * 2; // 100ms at 48kHz stereo
    if (samplesToCheck > MIC_BUFFER_SIZE) samplesToCheck = MIC_BUFFER_SIZE;
    
    float sum = 0.0f;
    int pos = g_mic_write_pos - samplesToCheck;
    if (pos < 0) pos += MIC_BUFFER_SIZE;
    
    for (int i = 0; i < samplesToCheck; i++) {
        float sample = g_mic_buffer[pos++];
        if (pos >= MIC_BUFFER_SIZE) pos = 0;
        sum += sample * sample;
    }
    
    pthread_mutex_unlock(&g_mic_mutex);
    
    float rms = sqrtf(sum / samplesToCheck);
    return fminf(rms * 3.0f, 1.0f); // Scale and clamp
}

// Read frames for audio callback (thread-safe)
int mic_input_read_frames(float* buffer, int frame_count) {
    if (!buffer || frame_count <= 0 || !g_is_active) {
        return 0;
    }
    
    pthread_mutex_lock(&g_mic_mutex);
    
    int samples_to_read = frame_count * 2; // stereo
    int samples_read = 0;
    
    while (samples_read < samples_to_read && g_mic_read_pos != g_mic_write_pos) {
        buffer[samples_read++] = g_mic_buffer[g_mic_read_pos++];
        
        if (g_mic_read_pos >= MIC_BUFFER_SIZE) {
            g_mic_read_pos = 0;
        }
    }
    
    // Fill remaining with silence if needed
    while (samples_read < samples_to_read) {
        buffer[samples_read++] = 0.0f;
    }
    
    pthread_mutex_unlock(&g_mic_mutex);
    
    return frame_count;
}

// Set microphone volume
void mic_input_set_volume(float volume) {
    pthread_mutex_lock(&g_mic_mutex);
    g_mic_volume = fmaxf(0.0f, fminf(volume, 1.0f));
        pthread_mutex_unlock(&g_mic_mutex);
    prnt("🎚️ [MIC_INPUT] Volume set to %.2f", g_mic_volume);
}

// Get microphone volume
float mic_input_get_volume(void) {
    return g_mic_volume;
}

// Check if currently using Bluetooth microphone
int mic_input_is_bluetooth(void) {
    return g_is_bluetooth_input;
}

// Get current audio route name
int mic_input_get_route_name(char* buffer, int buffer_size) {
    if (!buffer || buffer_size <= 0) return -1;
    
    pthread_mutex_lock(&g_mic_mutex);
    snprintf(buffer, buffer_size, "%s", g_current_audio_route);
    pthread_mutex_unlock(&g_mic_mutex);
    
        return 0;
}

// SIMPLIFIED: Device selection functions - just query, don't force anything
int mic_input_get_available_inputs_count(void) {
    @try {
        AVAudioSession* session = [AVAudioSession sharedInstance];
        NSArray<AVAudioSessionPortDescription*>* availableInputs = [session availableInputs];
        if (!availableInputs || availableInputs.count == 0) {
            NSError* err = nil;
            [session setActive:YES error:&err];
            availableInputs = [session availableInputs];
        }
        return (int)availableInputs.count;
    } @catch (NSException* e) {
        prnt_err("❌ [MIC_INPUT] Exception getting input count: %s", [[e reason] UTF8String]);
        return 0;
    }
}

int mic_input_get_available_input_info(int index, char* uid_buffer, int uid_buffer_size,
                                       char* name_buffer, int name_buffer_size,
                                       char* type_buffer, int type_buffer_size) {
    @try {
        AVAudioSession* session = [AVAudioSession sharedInstance];
        NSArray<AVAudioSessionPortDescription*>* availableInputs = [session availableInputs];
        if (!availableInputs || availableInputs.count == 0) {
            NSError* err = nil;
            [session setActive:YES error:&err];
            availableInputs = [session availableInputs];
        }
        
        if (index < 0 || index >= availableInputs.count) {
            return -1;
        }
        
        AVAudioSessionPortDescription* port = availableInputs[index];
        
        if (uid_buffer && uid_buffer_size > 0) {
            snprintf(uid_buffer, uid_buffer_size, "%s", [port.UID UTF8String] ?: "");
        }
        
        if (name_buffer && name_buffer_size > 0) {
            snprintf(name_buffer, name_buffer_size, "%s", [port.portName UTF8String] ?: "Unknown");
        }
        
        if (type_buffer && type_buffer_size > 0) {
            snprintf(type_buffer, type_buffer_size, "%s", [port.portType UTF8String] ?: "Unknown");
        }
        
        return 0;
    } @catch (NSException* e) {
        prnt_err("❌ [MIC_INPUT] Exception getting input info: %s", [[e reason] UTF8String]);
        return -1;
    }
}

// SIMPLIFIED: Set preferred input - let iOS do the work
int mic_input_set_preferred_input(const char* uid) {
    if (!uid) return -1;
    
    @try {
        AVAudioSession* session = [AVAudioSession sharedInstance];
        NSArray<AVAudioSessionPortDescription*>* availableInputs = [session availableInputs];
        
        NSString* targetUID = [NSString stringWithUTF8String:uid];
        
        for (AVAudioSessionPortDescription* port in availableInputs) {
            if ([port.UID isEqualToString:targetUID]) {
                NSError* error = nil;
                BOOL success = [session setPreferredInput:port error:&error];
                
                if (success && !error) {
                    prnt("✅ [MIC_INPUT] Set preferred input to: %s", [port.portName UTF8String] ?: "Unknown");
                    mic_refresh_current_input_state(session);
                    return 0;
                } else {
                    prnt_err("❌ [MIC_INPUT] Failed to set preferred input: %s",
                            error ? [[error localizedDescription] UTF8String] : "unknown");
                    return -1;
                }
            }
        }
        
        return -1; // UID not found
    } @catch (NSException* e) {
        prnt_err("❌ [MIC_INPUT] Exception setting preferred input: %s", [[e reason] UTF8String]);
        return -1;
    }
}

int mic_input_get_current_input_uid(char* buffer, int buffer_size) {
    if (!buffer || buffer_size <= 0) return -1;
    
    @try {
        AVAudioSession* session = [AVAudioSession sharedInstance];
        AVAudioSessionPortDescription* input = nil;

        // Prefer the active route input because it reflects the real capture source.
        if (session.currentRoute.inputs.count > 0) {
            input = session.currentRoute.inputs[0];
        }
        if (!input) {
            input = session.preferredInput;
        }
        
        if (input) {
            snprintf(buffer, buffer_size, "%s", [input.UID UTF8String] ?: "");
                return 0;
        }
        
        return -1;
    } @catch (NSException* e) {
        prnt_err("❌ [MIC_INPUT] Exception getting current input UID: %s", [[e reason] UTF8String]);
        return -1;
    }
}

// Stub implementations for features not needed for basic recording
void mic_input_set_echo_cancellation(int enabled) {
    prnt("ℹ️ [MIC_INPUT] Echo cancellation control not implemented in simplified version");
}

int mic_input_is_headphones_connected(void) {
    @try {
        AVAudioSession* session = [AVAudioSession sharedInstance];
        AVAudioSessionRouteDescription* route = [session currentRoute];
        
        for (AVAudioSessionPortDescription* output in route.outputs) {
            NSString* portType = output.portType;
            if ([portType isEqualToString:AVAudioSessionPortHeadphones] ||
                [portType isEqualToString:AVAudioSessionPortBluetoothHFP] ||
                [portType isEqualToString:AVAudioSessionPortBluetoothA2DP] ||
                [portType isEqualToString:AVAudioSessionPortBluetoothLE]) {
                return 1;
            }
        }
        return 0;
    } @catch (NSException* e) {
        return 0;
    }
}

// Output device functions - simplified
int mic_input_get_available_outputs_count(void) {
    @try {
        AVAudioSession* session = [AVAudioSession sharedInstance];
        AVAudioSessionRouteDescription* route = [session currentRoute];
        
        // Check if current output is external (Bluetooth/headphones)
        if (route.outputs.count > 0) {
            AVAudioSessionPortDescription* output = route.outputs[0];
            NSString* portType = output.portType;
            
            // If external device connected, show both Speaker and external device
            if ([portType isEqualToString:AVAudioSessionPortBluetoothHFP] ||
                [portType isEqualToString:AVAudioSessionPortBluetoothA2DP] ||
                [portType isEqualToString:AVAudioSessionPortBluetoothLE] ||
                [portType isEqualToString:AVAudioSessionPortHeadphones]) {
                return 2; // Speaker + external device
            }
        }
        
        // Only built-in output (Speaker or Receiver) - show only Speaker option
        return 1;
    } @catch (NSException* e) {
        return 1; // Default to just Speaker
    }
}

int mic_input_get_available_output_info(int index, char* uid_buffer, int uid_buffer_size,
                                        char* name_buffer, int name_buffer_size,
                                        char* type_buffer, int type_buffer_size) {
    @try {
        AVAudioSession* session = [AVAudioSession sharedInstance];
        AVAudioSessionRouteDescription* route = [session currentRoute];
        
        if (index == 0) {
            // Always show built-in speaker as first option
            if (uid_buffer && uid_buffer_size > 0) {
                snprintf(uid_buffer, uid_buffer_size, "Speaker");
            }
            if (name_buffer && name_buffer_size > 0) {
                snprintf(name_buffer, name_buffer_size, "Speaker");
            }
            if (type_buffer && type_buffer_size > 0) {
                snprintf(type_buffer, type_buffer_size, "%s", [AVAudioSessionPortBuiltInSpeaker UTF8String]);
            }
            return 0;
        } else if (index == 1 && route.outputs.count > 0) {
            // Only show current device if it's external (not Receiver)
            AVAudioSessionPortDescription* output = route.outputs[0];
            NSString* portType = output.portType;
            
            // Only return external devices (not built-in Receiver)
            if ([portType isEqualToString:AVAudioSessionPortBluetoothHFP] ||
                [portType isEqualToString:AVAudioSessionPortBluetoothA2DP] ||
                [portType isEqualToString:AVAudioSessionPortBluetoothLE] ||
                [portType isEqualToString:AVAudioSessionPortHeadphones]) {
                    
                    if (uid_buffer && uid_buffer_size > 0) {
                    snprintf(uid_buffer, uid_buffer_size, "%s", [output.UID UTF8String] ?: "External");
                    }
                    if (name_buffer && name_buffer_size > 0) {
                    snprintf(name_buffer, name_buffer_size, "%s", [output.portName UTF8String] ?: "External Device");
                    }
                    if (type_buffer && type_buffer_size > 0) {
                    snprintf(type_buffer, type_buffer_size, "%s", [output.portType UTF8String] ?: "Unknown");
                    }
                    return 0;
                }
            }
            
        return -1; // Index out of range or no external device
    } @catch (NSException* e) {
        return -1;
    }
}

int mic_input_get_current_output_type(char* type_buffer, int type_buffer_size) {
    @try {
        AVAudioSession* session = [AVAudioSession sharedInstance];
        AVAudioSessionRouteDescription* route = [session currentRoute];
        
        if (route.outputs.count > 0 && type_buffer && type_buffer_size > 0) {
            AVAudioSessionPortDescription* port = route.outputs[0];
                snprintf(type_buffer, type_buffer_size, "%s", [port.portType UTF8String] ?: "Unknown");
            return 0;
        }
        
        return -1;
    } @catch (NSException* e) {
        return -1;
    }
}

int mic_input_set_output_route(const char* route_type) {
    if (!route_type) return -1;
    
    @try {
        AVAudioSession* session = [AVAudioSession sharedInstance];
        NSError* error = nil;
        
        if (strcmp(route_type, "speaker") == 0) {
            // Force speaker
            BOOL success = [session overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:&error];
            if (success && !error) {
                prnt("✅ [MIC_INPUT] Output routed to speaker");
                return 0;
            }
        } else {
            // Default routing (Bluetooth/headphones if connected)
            BOOL success = [session overrideOutputAudioPort:AVAudioSessionPortOverrideNone error:&error];
            if (success && !error) {
                prnt("✅ [MIC_INPUT] Output routing set to default");
                return 0;
            }
        }
        
            prnt_err("❌ [MIC_INPUT] Failed to set output route: %s",
                error ? [[error localizedDescription] UTF8String] : "unknown");
            return -1;
    } @catch (NSException* e) {
        prnt_err("❌ [MIC_INPUT] Exception setting output route: %s", [[e reason] UTF8String]);
        return -1;
    }
}

void mic_input_cleanup(void) {
    prnt("🧹 [MIC_INPUT] Cleanup called");
    
    mic_input_stop();
    
    pthread_mutex_lock(&g_mic_mutex);
    
    if (g_audio_engine) {
        if ([g_audio_engine isRunning]) {
            [g_audio_engine stop];
        }
        g_audio_engine = nil;
        g_input_node = nil;
    }
    
    g_is_initialized = 0;
    pthread_mutex_unlock(&g_mic_mutex);
    
    prnt("✅ [MIC_INPUT] Cleanup complete");
}

#else
// Non-Apple platform stubs
int mic_input_init(void) { return 0; }
int mic_input_start(void) { return -1; }
void mic_input_stop(void) {}
int mic_input_is_active(void) { return 0; }
float mic_input_get_level(void) { return 0.0f; }
int mic_input_read_frames(float* buffer, int frame_count) {
    if (buffer && frame_count > 0) {
        memset(buffer, 0, frame_count * 2 * sizeof(float));
    }
    return 0;
}
void mic_input_set_volume(float volume) {}
float mic_input_get_volume(void) { return 1.0f; }
int mic_input_is_bluetooth(void) { return 0; }
int mic_input_get_route_name(char* buffer, int buffer_size) {
    if (buffer && buffer_size > 0) {
        strncpy(buffer, "Unknown", buffer_size - 1);
        buffer[buffer_size - 1] = '\0';
    }
    return -1;
}
void mic_input_set_echo_cancellation(int enabled) {}
int mic_input_is_headphones_connected(void) { return 0; }
int mic_input_get_available_inputs_count(void) { return 0; }
int mic_input_get_available_input_info(int index, char* uid_buffer, int uid_buffer_size,
                                       char* name_buffer, int name_buffer_size,
                                       char* type_buffer, int type_buffer_size) { return -1; }
int mic_input_set_preferred_input(const char* uid) { return -1; }
int mic_input_get_current_input_uid(char* buffer, int buffer_size) { return -1; }
int mic_input_get_available_outputs_count(void) { return 0; }
int mic_input_get_available_output_info(int index, char* uid_buffer, int uid_buffer_size,
                                        char* name_buffer, int name_buffer_size,
                                        char* type_buffer, int type_buffer_size) { return -1; }
int mic_input_get_current_output_type(char* buffer, int buffer_size) { return -1; }
int mic_input_set_output_route(const char* route_type) { return -1; }
void mic_input_cleanup(void) {}
#endif
