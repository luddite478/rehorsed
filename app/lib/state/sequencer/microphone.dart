import 'package:flutter/foundation.dart';
import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart' as ffi;
import 'package:permission_handler/permission_handler.dart';
import '../../utils/log.dart';

/// Represents an audio device (input or output)
class AudioDevice {
  final String uid;
  final String name;
  final String type;
  final bool isSelected;
  
  AudioDevice({
    required this.uid,
    required this.name,
    required this.type,
    this.isSelected = false,
  });
  
  bool get isBluetooth => type.contains('Bluetooth');
  bool get isBuiltIn => type.contains('BuiltIn');
  
  @override
  String toString() => '$name ($type)${isSelected ? " [ACTIVE]" : ""}';
  
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AudioDevice &&
          runtimeType == other.runtimeType &&
          uid == other.uid;
  
  @override
  int get hashCode => uid.hashCode;
}

// FFI bindings for microphone input
typedef MicInputInitNative = ffi.Int32 Function();
typedef MicInputInit = int Function();

typedef MicInputStartNative = ffi.Int32 Function();
typedef MicInputStart = int Function();

typedef MicInputStopNative = ffi.Void Function();
typedef MicInputStop = void Function();

typedef MicInputIsActiveNative = ffi.Int32 Function();
typedef MicInputIsActive = int Function();

typedef MicInputGetLevelNative = ffi.Float Function();
typedef MicInputGetLevel = double Function();

typedef MicInputSetVolumeNative = ffi.Void Function(ffi.Float volume);
typedef MicInputSetVolume = void Function(double volume);

typedef MicInputGetVolumeNative = ffi.Float Function();
typedef MicInputGetVolume = double Function();

typedef MicInputIsBluetoothNative = ffi.Int32 Function();
typedef MicInputIsBluetooth = int Function();

typedef MicInputGetRouteNameNative = ffi.Int32 Function(ffi.Pointer<ffi.Char> buffer, ffi.Int32 bufferSize);
typedef MicInputGetRouteName = int Function(ffi.Pointer<ffi.Char> buffer, int bufferSize);

typedef MicInputCleanupNative = ffi.Void Function();
typedef MicInputCleanup = void Function();

typedef MicInputIsHeadphonesConnectedNative = ffi.Int32 Function();
typedef MicInputIsHeadphonesConnected = int Function();

// FFI bindings for device management
typedef MicInputGetAvailableInputsCountNative = ffi.Int32 Function();
typedef MicInputGetAvailableInputsCount = int Function();

typedef MicInputGetAvailableInputInfoNative = ffi.Int32 Function(
  ffi.Int32 index,
  ffi.Pointer<ffi.Char> uidBuffer,
  ffi.Int32 uidBufferSize,
  ffi.Pointer<ffi.Char> nameBuffer,
  ffi.Int32 nameBufferSize,
  ffi.Pointer<ffi.Char> typeBuffer,
  ffi.Int32 typeBufferSize
);
typedef MicInputGetAvailableInputInfo = int Function(
  int index,
  ffi.Pointer<ffi.Char> uidBuffer,
  int uidBufferSize,
  ffi.Pointer<ffi.Char> nameBuffer,
  int nameBufferSize,
  ffi.Pointer<ffi.Char> typeBuffer,
  int typeBufferSize
);

typedef MicInputSetPreferredInputNative = ffi.Int32 Function(ffi.Pointer<ffi.Char> uid);
typedef MicInputSetPreferredInput = int Function(ffi.Pointer<ffi.Char> uid);

typedef MicInputGetCurrentInputUidNative = ffi.Int32 Function(ffi.Pointer<ffi.Char> buffer, ffi.Int32 bufferSize);
typedef MicInputGetCurrentInputUid = int Function(ffi.Pointer<ffi.Char> buffer, int bufferSize);

typedef MicInputGetAvailableOutputsCountNative = ffi.Int32 Function();
typedef MicInputGetAvailableOutputsCount = int Function();

typedef MicInputGetAvailableOutputInfoNative = ffi.Int32 Function(
  ffi.Int32 index,
  ffi.Pointer<ffi.Char> uidBuffer,
  ffi.Int32 uidBufferSize,
  ffi.Pointer<ffi.Char> nameBuffer,
  ffi.Int32 nameBufferSize,
  ffi.Pointer<ffi.Char> typeBuffer,
  ffi.Int32 typeBufferSize
);
typedef MicInputGetAvailableOutputInfo = int Function(
  int index,
  ffi.Pointer<ffi.Char> uidBuffer,
  int uidBufferSize,
  ffi.Pointer<ffi.Char> nameBuffer,
  int nameBufferSize,
  ffi.Pointer<ffi.Char> typeBuffer,
  int typeBufferSize
);

typedef MicInputGetCurrentOutputTypeNative = ffi.Int32 Function(ffi.Pointer<ffi.Char> buffer, ffi.Int32 bufferSize);
typedef MicInputGetCurrentOutputType = int Function(ffi.Pointer<ffi.Char> buffer, int bufferSize);

typedef MicInputSetOutputRouteNative = ffi.Int32 Function(ffi.Pointer<ffi.Char> routeType);
typedef MicInputSetOutputRoute = int Function(ffi.Pointer<ffi.Char> routeType);

// NOTE: SunVox Input module bindings removed - mic recording now bypasses SunVox entirely
// Mic audio is captured directly to WAV file without going through SunVox
// See docs/features/microphone_dual_output_architecture.md for archived approach

/// State management for microphone input
/// Handles microphone permissions, native mic capture, and SunVox Input module
class MicrophoneState extends ChangeNotifier {
  // FFI library
  late final ffi.DynamicLibrary _lib;
  
  // Native function bindings
  late final MicInputInit _micInputInit;
  late final MicInputStart _micInputStart;
  late final MicInputStop _micInputStop;
  late final MicInputIsActive _micInputIsActive;
  late final MicInputGetLevel _micInputGetLevel;
  late final MicInputSetVolume _micInputSetVolume;
  late final MicInputGetVolume _micInputGetVolume;
  late final MicInputIsBluetooth _micInputIsBluetooth;
  late final MicInputGetRouteName _micInputGetRouteName;
  late final MicInputCleanup _micInputCleanup;
  late final MicInputIsHeadphonesConnected _micInputIsHeadphonesConnected;
  
  // Device management function bindings
  late final MicInputGetAvailableInputsCount _micInputGetAvailableInputsCount;
  late final MicInputGetAvailableInputInfo _micInputGetAvailableInputInfo;
  late final MicInputSetPreferredInput _micInputSetPreferredInput;
  late final MicInputGetCurrentInputUid _micInputGetCurrentInputUid;
  late final MicInputGetAvailableOutputsCount _micInputGetAvailableOutputsCount;
  late final MicInputGetAvailableOutputInfo _micInputGetAvailableOutputInfo;
  late final MicInputGetCurrentOutputType _micInputGetCurrentOutputType;
  late final MicInputSetOutputRoute _micInputSetOutputRoute;
  
  bool _isMicEnabled = false;
  bool _isMicActive = false;
  bool _isInitialized = false;
  double _micVolume = 1.0; // Default to full volume
  String? _errorMessage;
  
  // Value notifiers for UI binding
  final ValueNotifier<bool> isMicEnabledNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isMicActiveNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<double> micVolumeNotifier = ValueNotifier<double>(1.0);
  final ValueNotifier<String?> errorMessageNotifier = ValueNotifier<String?>(null);
  
  // Getters
  bool get isMicEnabled => _isMicEnabled;
  bool get isMicActive => _isMicActive;
  bool get isInitialized => _isInitialized;
  double get micVolume => _micVolume;
  String? get errorMessage => _errorMessage;
  
  MicrophoneState() {
    _loadLibrary();
  }
  
  void _loadLibrary() {
    try {
      _lib = ffi.DynamicLibrary.process();
      
      // Load microphone input functions
      _micInputInit = _lib.lookupFunction<MicInputInitNative, MicInputInit>('mic_input_init');
      _micInputStart = _lib.lookupFunction<MicInputStartNative, MicInputStart>('mic_input_start');
      _micInputStop = _lib.lookupFunction<MicInputStopNative, MicInputStop>('mic_input_stop');
      _micInputIsActive = _lib.lookupFunction<MicInputIsActiveNative, MicInputIsActive>('mic_input_is_active');
      _micInputGetLevel = _lib.lookupFunction<MicInputGetLevelNative, MicInputGetLevel>('mic_input_get_level');
      _micInputSetVolume = _lib.lookupFunction<MicInputSetVolumeNative, MicInputSetVolume>('mic_input_set_volume');
      _micInputGetVolume = _lib.lookupFunction<MicInputGetVolumeNative, MicInputGetVolume>('mic_input_get_volume');
      _micInputIsBluetooth = _lib.lookupFunction<MicInputIsBluetoothNative, MicInputIsBluetooth>('mic_input_is_bluetooth');
      _micInputGetRouteName = _lib.lookupFunction<MicInputGetRouteNameNative, MicInputGetRouteName>('mic_input_get_route_name');
      _micInputCleanup = _lib.lookupFunction<MicInputCleanupNative, MicInputCleanup>('mic_input_cleanup');
      _micInputIsHeadphonesConnected = _lib.lookupFunction<MicInputIsHeadphonesConnectedNative, MicInputIsHeadphonesConnected>('mic_input_is_headphones_connected');
      
      // Load device management functions
      _micInputGetAvailableInputsCount = _lib.lookupFunction<MicInputGetAvailableInputsCountNative, MicInputGetAvailableInputsCount>('mic_input_get_available_inputs_count');
      _micInputGetAvailableInputInfo = _lib.lookupFunction<MicInputGetAvailableInputInfoNative, MicInputGetAvailableInputInfo>('mic_input_get_available_input_info');
      _micInputSetPreferredInput = _lib.lookupFunction<MicInputSetPreferredInputNative, MicInputSetPreferredInput>('mic_input_set_preferred_input');
      _micInputGetCurrentInputUid = _lib.lookupFunction<MicInputGetCurrentInputUidNative, MicInputGetCurrentInputUid>('mic_input_get_current_input_uid');
      _micInputGetAvailableOutputsCount = _lib.lookupFunction<MicInputGetAvailableOutputsCountNative, MicInputGetAvailableOutputsCount>('mic_input_get_available_outputs_count');
      _micInputGetAvailableOutputInfo = _lib.lookupFunction<MicInputGetAvailableOutputInfoNative, MicInputGetAvailableOutputInfo>('mic_input_get_available_output_info');
      _micInputGetCurrentOutputType = _lib.lookupFunction<MicInputGetCurrentOutputTypeNative, MicInputGetCurrentOutputType>('mic_input_get_current_output_type');
      _micInputSetOutputRoute = _lib.lookupFunction<MicInputSetOutputRouteNative, MicInputSetOutputRoute>('mic_input_set_output_route');
      
      Log.d('Microphone FFI bindings loaded successfully', 'MICROPHONE_STATE');
    } catch (e) {
      Log.e('Failed to load microphone FFI bindings', 'MICROPHONE_STATE', e);
      _errorMessage = 'Failed to load microphone library: $e';
      errorMessageNotifier.value = _errorMessage;
    }
  }
  
  /// Enable microphone (request permissions, initialize, and create Input module)
  Future<bool> enableMicrophone() async {
    if (_isMicEnabled) {
      Log.d('Microphone already enabled', 'MICROPHONE_STATE');
      return true;
    }
    
    try {
      // Check current permission status
      Log.d('Checking microphone permission...', 'MICROPHONE_STATE');
      var status = await Permission.microphone.status;
      Log.d('Current permission status: $status (isGranted: ${status.isGranted}, isDenied: ${status.isDenied}, isPermanentlyDenied: ${status.isPermanentlyDenied}, isRestricted: ${status.isRestricted})', 'MICROPHONE_STATE');
      
      // Request permission if not granted (will show iOS dialog on first request)
      if (!status.isGranted) {
        Log.d('Requesting microphone permission (will show iOS dialog)...', 'MICROPHONE_STATE');
        status = await Permission.microphone.request();
        Log.d('After request - permission status: $status (isGranted: ${status.isGranted}, isDenied: ${status.isDenied}, isPermanentlyDenied: ${status.isPermanentlyDenied})', 'MICROPHONE_STATE');
        
        if (!status.isGranted) {
          if (status.isPermanentlyDenied) {
            // Only open settings if truly permanently denied (user denied twice)
            _errorMessage = 'Microphone access denied. Opening Settings to enable it...';
            errorMessageNotifier.value = _errorMessage;
            Log.w('Microphone permanently denied - opening Settings', 'MICROPHONE_STATE');
            await Future.delayed(const Duration(milliseconds: 500)); // Brief delay before opening
            await openAppSettings();
          } else if (status.isRestricted) {
            _errorMessage = 'Microphone access is restricted. Check Screen Time settings.';
            errorMessageNotifier.value = _errorMessage;
            Log.w('Microphone is restricted (parental controls?)', 'MICROPHONE_STATE');
          } else {
            // User denied but can try again
            _errorMessage = 'Microphone permission denied. Please allow access to record.';
            errorMessageNotifier.value = _errorMessage;
            Log.w('Microphone denied - user can try again', 'MICROPHONE_STATE');
          }
          return false;
        }
      }
      
      Log.i('✅ Microphone permission granted!', 'MICROPHONE_STATE');
      
      // Initialize native microphone input (always call - native handles "already initialized")
      final initResult = _micInputInit();
      if (initResult != 0) {
        _errorMessage = 'Failed to initialize microphone (code: $initResult)';
        errorMessageNotifier.value = _errorMessage;
        Log.e('Failed to initialize microphone (code: $initResult)', 'MICROPHONE_STATE');
        _isInitialized = false;
        return false;
      }
      _isInitialized = true;
      Log.d('Microphone input initialized', 'MICROPHONE_STATE');
      
      // NOTE: SunVox Input module removed - mic recording now bypasses SunVox entirely
      // Mic audio is captured directly to WAV file without going through SunVox
      
      // Start microphone capture
      Log.d('Calling native mic_input_start()...', 'MICROPHONE_STATE');
      final startResult = _micInputStart();
      Log.d('native mic_input_start() returned: $startResult', 'MICROPHONE_STATE');
      if (startResult != 0) {
        _errorMessage = 'Failed to start microphone capture (code: $startResult)';
        errorMessageNotifier.value = _errorMessage;
        Log.e('Failed to start microphone capture (code: $startResult)', 'MICROPHONE_STATE');
        return false;
      }
      
      _isMicEnabled = true;
      _isMicActive = true;
      _errorMessage = null;
      
      isMicEnabledNotifier.value = _isMicEnabled;
      isMicActiveNotifier.value = _isMicActive;
      errorMessageNotifier.value = _errorMessage;
      notifyListeners();
      
      Log.i('🎙️ Microphone enabled and active', 'MICROPHONE_STATE');
      return true;
      
    } catch (e) {
      _errorMessage = 'Error enabling microphone: $e';
      errorMessageNotifier.value = _errorMessage;
      Log.e('Error enabling microphone', 'MICROPHONE_STATE', e);
      return false;
    }
  }
  
  /// Disable microphone (stop capture)
  Future<void> disableMicrophone() async {
    if (!_isMicEnabled) {
      return;
    }
    
    try {
      Log.d('Disabling microphone...', 'MICROPHONE_STATE');
      
      // Stop microphone capture (native side will reset its state)
      _micInputStop();
      
      _isMicEnabled = false;
      _isMicActive = false;
      _isInitialized = false; // Reset so next enable reinitializes
      _errorMessage = null;
      
      isMicEnabledNotifier.value = _isMicEnabled;
      isMicActiveNotifier.value = _isMicActive;
      errorMessageNotifier.value = _errorMessage;
      notifyListeners();
      
      Log.i('🎙️ Microphone disabled', 'MICROPHONE_STATE');
      
    } catch (e) {
      Log.e('Error disabling microphone', 'MICROPHONE_STATE', e);
    }
  }
  
  /// Toggle microphone on/off
  Future<bool> toggleMicrophone() async {
    if (_isMicEnabled) {
      await disableMicrophone();
      return false;
    } else {
      return await enableMicrophone();
    }
  }
  
  /// Check if microphone is currently active (native check)
  bool checkMicActive() {
    try {
      final active = _micInputIsActive();
      _isMicActive = (active == 1);
      isMicActiveNotifier.value = _isMicActive;
      return _isMicActive;
    } catch (e) {
      Log.e('Error checking mic active state', 'MICROPHONE_STATE', e);
      return false;
    }
  }
  
  /// Get current audio level (0.0 - 1.0) for visualization
  double getAudioLevel() {
    if (!_isMicEnabled) return 0.0;
    try {
      return _micInputGetLevel();
    } catch (e) {
      return 0.0;
    }
  }
  
  // NOTE: Monitoring and mic-only recording functions removed
  // Mic recording now bypasses SunVox - raw mic audio goes directly to WAV file
  
  /// Check if headphones (wired or Bluetooth) are connected
  /// Returns true if headphones connected, false if using built-in speaker/mic
  bool isHeadphonesConnected() {
    try {
      return _micInputIsHeadphonesConnected() == 1;
    } catch (e) {
      Log.e('Error checking headphones', 'MICROPHONE_STATE', e);
      return false;
    }
  }
  
  /// Set microphone input volume (0.0 - 1.0)
  /// This controls the gain applied to the microphone input
  void setMicVolume(double volume) {
    if (!_isMicEnabled) {
      Log.w('Cannot set volume - microphone not enabled', 'MICROPHONE_STATE');
      return;
    }
    
    try {
      final clampedVolume = volume.clamp(0.0, 1.0);
      _micInputSetVolume(clampedVolume);
      _micVolume = clampedVolume;
      micVolumeNotifier.value = _micVolume;
      notifyListeners();
      Log.d('Mic volume set to ${(_micVolume * 100).toStringAsFixed(0)}%', 'MICROPHONE_STATE');
    } catch (e) {
      Log.e('Error setting mic volume', 'MICROPHONE_STATE', e);
    }
  }
  
  /// Get current microphone input volume from native side
  double getMicVolumeFromNative() {
    try {
      return _micInputGetVolume();
    } catch (e) {
      Log.e('Error getting mic volume from native', 'MICROPHONE_STATE', e);
      return 1.0;
    }
  }
  
  /// Check if currently using Bluetooth microphone
  /// Returns true if Bluetooth device (AirPods, etc.), false if built-in iPhone mic
  bool isBluetoothMicrophone() {
    if (!_isMicEnabled) return false;
    try {
      return _micInputIsBluetooth() == 1;
    } catch (e) {
      Log.e('Error checking Bluetooth status', 'MICROPHONE_STATE', e);
      return false;
    }
  }
  
  /// Get current audio input route name (e.g., "AirPods Pro", "iPhone Microphone")
  String getAudioRouteName() {
    if (!_isMicEnabled) return 'Not Active';
    try {
      final buffer = ffi.calloc<ffi.Char>(256);
      try {
        final result = _micInputGetRouteName(buffer, 256);
        if (result == 0) {
          return buffer.cast<ffi.Utf8>().toDartString();
        }
        return 'Unknown';
      } finally {
        ffi.calloc.free(buffer);
      }
    } catch (e) {
      Log.e('Error getting audio route name', 'MICROPHONE_STATE', e);
      return 'Unknown';
    }
  }
  
  // NOTE: setRecordingState removed - mic recording now bypasses SunVox
  // Raw mic audio goes directly to WAV file during recording
  
  /// Get list of available input devices (microphones)
  List<AudioDevice> getAvailableInputs() {
    try {
      final count = _micInputGetAvailableInputsCount();
      final devices = <AudioDevice>[];
      
      for (int i = 0; i < count; i++) {
        final uidBuffer = ffi.calloc<ffi.Char>(256);
        final nameBuffer = ffi.calloc<ffi.Char>(256);
        final typeBuffer = ffi.calloc<ffi.Char>(256);
        
        try {
          final result = _micInputGetAvailableInputInfo(
            i, uidBuffer, 256, nameBuffer, 256, typeBuffer, 256
          );
          
          if (result == 0) {
            devices.add(AudioDevice(
              uid: uidBuffer.cast<ffi.Utf8>().toDartString(),
              name: nameBuffer.cast<ffi.Utf8>().toDartString(),
              type: typeBuffer.cast<ffi.Utf8>().toDartString(),
            ));
          }
        } finally {
          ffi.calloc.free(uidBuffer);
          ffi.calloc.free(nameBuffer);
          ffi.calloc.free(typeBuffer);
        }
      }

      // Keep currently selected wired input visible even if availableInputs is transiently stale.
      final currentUid = getCurrentInputUid();
      if (currentUid != null &&
          currentUid.isNotEmpty &&
          !devices.any((d) => d.uid == currentUid)) {
        final routeName = getAudioRouteName();
        final routeLower = routeName.toLowerCase();
        final isWiredRoute = routeLower.contains('headset') ||
            routeLower.contains('earpods') ||
            routeLower.contains('line in') ||
            routeLower.contains('usb');
        if (isWiredRoute) {
          devices.insert(
            0,
            AudioDevice(
              uid: currentUid,
              name: routeName == 'Unknown' ? 'Wired Mic' : routeName,
              type: 'HeadsetMic',
            ),
          );
        }
      }

      return devices;
    } catch (e) {
      Log.e('Error getting available inputs', 'MICROPHONE_STATE', e);
      return [];
    }
  }
  
  /// Set preferred input device by UID
  bool setPreferredInput(String uid) {
    try {
      final uidPtr = uid.toNativeUtf8();
      try {
        final result = _micInputSetPreferredInput(uidPtr.cast());
        if (result == 0) {
          notifyListeners();
          return true;
        }
        return false;
      } finally {
        ffi.calloc.free(uidPtr);
      }
    } catch (e) {
      Log.e('Error setting preferred input', 'MICROPHONE_STATE', e);
      return false;
    }
  }
  
  /// Get current input device UID
  String? getCurrentInputUid() {
    try {
      final buffer = ffi.calloc<ffi.Char>(256);
      try {
        final result = _micInputGetCurrentInputUid(buffer, 256);
        if (result == 0) {
          return buffer.cast<ffi.Utf8>().toDartString();
        }
        return null;
      } finally {
        ffi.calloc.free(buffer);
      }
    } catch (e) {
      Log.e('Error getting current input UID', 'MICROPHONE_STATE', e);
      return null;
    }
  }

  /// Get current input device info by matching current UID against available inputs.
  AudioDevice? getCurrentInputDevice() {
    final currentUid = getCurrentInputUid();
    if (currentUid == null || currentUid.isEmpty) return null;
    final devices = getAvailableInputs();
    for (final device in devices) {
      if (device.uid == currentUid) return device;
    }
    return null;
  }

  /// Returns a short user-facing label for currently active mic source.
  /// Expected values: "WIRED", "BUILT-IN", "UNKNOWN".
  String getCurrentInputKindLabel() {
    final device = getCurrentInputDevice();
    if (device != null) {
      final t = device.type;
      if (t.contains('HeadsetMic') || t.contains('USBAudio') || t.contains('LineIn')) {
        return 'WIRED';
      }
      if (t.contains('BuiltInMic')) return 'BUILT-IN';
    }

    // Fallback to active route name for cases where available input list is transiently stale.
    final routeName = getAudioRouteName().toLowerCase();
    if (routeName.contains('headset') ||
        routeName.contains('earpods') ||
        routeName.contains('line in') ||
        routeName.contains('usb')) {
      return 'WIRED';
    }
    if (routeName.contains('iphone') || routeName.contains('built')) return 'BUILT-IN';
    return 'UNKNOWN';
  }
  
  /// Get current output type
  String? getCurrentOutputType() {
    try {
      final buffer = ffi.calloc<ffi.Char>(256);
      try {
        final result = _micInputGetCurrentOutputType(buffer, 256);
        if (result == 0) {
          return buffer.cast<ffi.Utf8>().toDartString();
        }
        return null;
      } finally {
        ffi.calloc.free(buffer);
      }
    } catch (e) {
      Log.e('Error getting current output type', 'MICROPHONE_STATE', e);
      return null;
    }
  }
  
  /// Get list of available output devices
  List<AudioDevice> getAvailableOutputs() {
    try {
      final count = _micInputGetAvailableOutputsCount();
      final devices = <AudioDevice>[];
      final currentOutputType = getCurrentOutputType();
      
      for (int i = 0; i < count; i++) {
        final uidBuffer = ffi.calloc<ffi.Char>(256);
        final nameBuffer = ffi.calloc<ffi.Char>(256);
        final typeBuffer = ffi.calloc<ffi.Char>(256);
        
        try {
          final result = _micInputGetAvailableOutputInfo(
            i, uidBuffer, 256, nameBuffer, 256, typeBuffer, 256
          );
          
          if (result == 0) {
            final deviceType = typeBuffer.cast<ffi.Utf8>().toDartString();
            // Mark as selected if this device's type matches the current output type
            final isSelected = currentOutputType != null && deviceType == currentOutputType;
            
            devices.add(AudioDevice(
              uid: uidBuffer.cast<ffi.Utf8>().toDartString(),
              name: nameBuffer.cast<ffi.Utf8>().toDartString(),
              type: deviceType,
              isSelected: isSelected,
            ));
          }
        } finally {
          ffi.calloc.free(uidBuffer);
          ffi.calloc.free(nameBuffer);
          ffi.calloc.free(typeBuffer);
        }
      }
      
      return devices;
    } catch (e) {
      Log.e('Error getting available outputs', 'MICROPHONE_STATE', e);
      return [];
    }
  }
  
  /// Set output route (speaker/bluetooth/default)
  bool setOutputRoute(String routeType) {
    try {
      final routePtr = routeType.toNativeUtf8();
      try {
        final result = _micInputSetOutputRoute(routePtr.cast());
        if (result == 0) {
          notifyListeners();
          return true;
        }
        return false;
      } finally {
        ffi.calloc.free(routePtr);
      }
    } catch (e) {
      Log.e('Error setting output route', 'MICROPHONE_STATE', e);
      return false;
    }
  }
  
  @override
  void dispose() {
    // Clean up microphone if active
    if (_isMicEnabled) {
      _micInputStop();
    }
    
    if (_isInitialized) {
      _micInputCleanup();
    }
    
    isMicEnabledNotifier.dispose();
    isMicActiveNotifier.dispose();
    micVolumeNotifier.dispose();
    errorMessageNotifier.dispose();
    
    super.dispose();
  }
}
