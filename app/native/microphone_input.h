#ifndef MICROPHONE_INPUT_H
#define MICROPHONE_INPUT_H

#ifdef __cplusplus
extern "C" {
#endif

// Initialize microphone input system
// Returns: 0 on success, negative error code on failure
__attribute__((visibility("default"))) __attribute__((used))
int mic_input_init(void);

// Start capturing microphone input
// Returns: 0 on success, negative error code on failure
//   -1: Not initialized
//   -2: Already active
//   -3: Failed to start audio engine
__attribute__((visibility("default"))) __attribute__((used))
int mic_input_start(void);

// Stop capturing microphone input
__attribute__((visibility("default"))) __attribute__((used))
void mic_input_stop(void);

// Check if microphone is currently active
// Returns: 1 if active, 0 if not
__attribute__((visibility("default"))) __attribute__((used))
int mic_input_is_active(void);

// Get current audio level (RMS) for visualization
// Returns: value 0.0 - 1.0 representing current audio level
__attribute__((visibility("default"))) __attribute__((used))
float mic_input_get_level(void);

// Read microphone frames for audio callback
// This is thread-safe and will only read if mic is active
// buffer: float32 interleaved stereo audio (LRLRLR...)
// frame_count: number of frames to read
// Returns: number of frames actually read (may be less if buffer underrun)
__attribute__((visibility("default"))) __attribute__((used))
int mic_input_read_frames(float* buffer, int frame_count);

// Set microphone input volume (0.0 - 1.0)
// This controls the gain applied to the microphone input
__attribute__((visibility("default"))) __attribute__((used))
void mic_input_set_volume(float volume);

// Get microphone input volume (0.0 - 1.0)
// Returns: current microphone volume
__attribute__((visibility("default"))) __attribute__((used))
float mic_input_get_volume(void);

// Check if currently using Bluetooth microphone
// Returns: 1 if Bluetooth device is being used, 0 if built-in or other
__attribute__((visibility("default"))) __attribute__((used))
int mic_input_is_bluetooth(void);

// Get current audio input route name (e.g., "AirPods Pro", "iPhone Microphone")
// buffer: destination buffer for route name
// buffer_size: size of destination buffer
// Returns: 0 on success, -1 on error
__attribute__((visibility("default"))) __attribute__((used))
int mic_input_get_route_name(char* buffer, int buffer_size);

// Enable/disable echo cancellation (iOS only)
// When enabled, iOS will digitally remove speaker output from microphone input
// enabled: 1 to enable AEC, 0 to disable
__attribute__((visibility("default"))) __attribute__((used))
void mic_input_set_echo_cancellation(int enabled);

// Check if headphones (wired or Bluetooth) are connected
// Returns: 1 if headphones connected, 0 if using built-in speaker/mic
__attribute__((visibility("default"))) __attribute__((used))
int mic_input_is_headphones_connected(void);

// Get number of available input devices
// Returns: number of available input devices
__attribute__((visibility("default"))) __attribute__((used))
int mic_input_get_available_inputs_count(void);

// Get available input device info by index
// index: 0-based index
// uid_buffer: buffer for device UID
// uid_buffer_size: size of UID buffer
// name_buffer: buffer for device name
// name_buffer_size: size of name buffer
// type_buffer: buffer for device type
// type_buffer_size: size of type buffer
// Returns: 0 on success, -1 on error
__attribute__((visibility("default"))) __attribute__((used))
int mic_input_get_available_input_info(int index, char* uid_buffer, int uid_buffer_size,
                                       char* name_buffer, int name_buffer_size,
                                       char* type_buffer, int type_buffer_size);

// Set preferred input device by UID
// uid: device UID to set as preferred
// Returns: 0 on success, -1 on error
__attribute__((visibility("default"))) __attribute__((used))
int mic_input_set_preferred_input(const char* uid);

// Get current input device UID
// buffer: destination buffer for device UID
// buffer_size: size of destination buffer
// Returns: 0 on success, -1 on error
__attribute__((visibility("default"))) __attribute__((used))
int mic_input_get_current_input_uid(char* buffer, int buffer_size);

// Get number of available output devices
// Returns: number of available output devices
__attribute__((visibility("default"))) __attribute__((used))
int mic_input_get_available_outputs_count(void);

// Get available output device info by index
// index: 0-based index
// uid_buffer: buffer for device UID
// uid_buffer_size: size of UID buffer
// name_buffer: buffer for device name
// name_buffer_size: size of name buffer
// type_buffer: buffer for device type
// type_buffer_size: size of type buffer
// Returns: 0 on success, -1 on error
__attribute__((visibility("default"))) __attribute__((used))
int mic_input_get_available_output_info(int index, char* uid_buffer, int uid_buffer_size,
                                        char* name_buffer, int name_buffer_size,
                                        char* type_buffer, int type_buffer_size);

// Get current output type (to determine if speaker or Bluetooth is active)
// buffer: destination buffer for output type
// buffer_size: size of destination buffer
// Returns: 0 on success, -1 on error
__attribute__((visibility("default"))) __attribute__((used))
int mic_input_get_current_output_type(char* buffer, int buffer_size);

// Set preferred output route (override)
// route_type: "speaker", "bluetooth", "default"
// Returns: 0 on success, -1 on error
__attribute__((visibility("default"))) __attribute__((used))
int mic_input_set_output_route(const char* route_type);

// Cleanup microphone input system
__attribute__((visibility("default"))) __attribute__((used))
void mic_input_cleanup(void);

#ifdef __cplusplus
}
#endif

#endif // MICROPHONE_INPUT_H
