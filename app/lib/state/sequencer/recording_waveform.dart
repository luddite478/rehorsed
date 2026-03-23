import 'package:flutter/foundation.dart';
import 'dart:async';
import '../../utils/sample_offset_calculator.dart';
import 'playback.dart';
import 'table.dart';

class RecordingWaveformState extends ChangeNotifier {
  // NOTE: PlaybackBindings removed - waveform capture uses level provider only now
  // Mic recording bypasses SunVox entirely (simplified architecture)

  final Map<int, Map<int, List<List<int>>>> _linesByLayerSection = {};
  // Offset per layer/section (in frames at 48kHz)
  final Map<int, Map<int, int>> _offsetsByLayerSection = {};
  Timer? _captureTimer;
  // NOTE: _inputModuleId removed - mic recording bypasses SunVox (simplified architecture)

  bool _isRecording = false;
  bool _isActuallyRecording = false; // Track the actual record button state
  int _activeLayer = 0;
  int _activeSection = 0;
  int _lastSection = 0;
  int _lastStep = 0;
  int _lastLoopIndex = 0; // Track loop counter for line creation
  
  PlaybackState? _playbackState;
  TableState? _tableState;
  double Function()? _levelProvider;

  static const int _samplesCount = 512;
  static const int _sampleStride = 4;
  static const int _maxSamplesPerLine = 4096;

  bool get isRecording => _isRecording;
  int get activeLayer => _activeLayer;
  int get activeSection => _activeSection;

  List<List<int>> getLines(int layer, int section) {
    final lines = _linesByLayerSection[layer]?[section] ?? const <List<int>>[];
    return lines;
  }

  /// Check if there's any actual recorded waveform data for this layer/section
  bool hasRecordedData(int layer, int section) {
    final lines = _linesByLayerSection[layer]?[section];
    if (lines == null || lines.isEmpty) return false;
    // Check if any line has actual samples (not just empty arrays)
    return lines.any((line) => line.isNotEmpty);
  }

  void startCapture({
    required int layer,
    required int section,
    required PlaybackState playbackState,
    required TableState tableState,
    bool clearExisting = true, // Option to preserve existing data
  }) {
    _playbackState = playbackState;
    _tableState = tableState;
    _activeLayer = layer;
    _activeSection = section;
    
    // Clear existing lines only if requested (default true for new recordings)
    if (clearExisting) {
      clearLines(layer, section);
    }
    
    _lastSection = playbackState.currentSection;
    _lastStep = playbackState.currentStep;
    _lastLoopIndex = playbackState.currentSectionLoop;

    // NOTE: Waveform capture uses level provider only (simplified architecture)
    // Mic recording bypasses SunVox entirely - raw mic goes directly to WAV file

    _isRecording = true;
    _ensureLineExists(_activeLayer, _activeSection);

    _captureTimer?.cancel();
    _captureTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _captureLineSamples();
    });

    debugPrint('🎙️ [LINE_MIC] Started capture: layer=$layer, section=$section, loop=$_lastLoopIndex');
    notifyListeners();
  }

  void ensureCapture({
    required bool enabled,
    required int layer,
    required int section,
    required PlaybackState playbackState,
    required TableState tableState,
    required bool isActuallyRecording, // NEW: Track actual record button state
    double Function()? levelProvider,
  }) {
    _levelProvider = levelProvider;
    _isActuallyRecording = isActuallyRecording; // Update the actual recording state
    
    // If mic is disabled, stop capture if active
    if (!enabled) {
      if (_isRecording) {
        stopCapture();
      }
      return;
    }

    // If already recording, just update state references
    // DON'T automatically start capture - that's controlled by recording state listener
    if (_isRecording) {
      _playbackState = playbackState;
      _tableState = tableState;
      if (_activeLayer != layer || _activeSection != section) {
        _activeLayer = layer;
        _activeSection = section;
        _lastSection = playbackState.currentSection;
        _lastStep = playbackState.currentStep;
        _lastLoopIndex = playbackState.currentSectionLoop;
        _ensureLineExists(_activeLayer, _activeSection);
        notifyListeners();
      }
    }
    // If not recording, don't start - let the recording state listener control this
    // This preserves waveform data after recording stops
  }

  void stopCapture() {
    _captureTimer?.cancel();
    _captureTimer = null;
    _isRecording = false;
    
    // NOTE: Do NOT clear _linesByLayerSection here - waveform should persist!
    // Only clear when startCapture(clearExisting: true) is called
    
    final totalLines = _linesByLayerSection[_activeLayer]?[_activeSection]?.length ?? 0;
    debugPrint('⏹️ [LINE_MIC] Stopped capture (waveform preserved): lines=$totalLines');
    notifyListeners();
  }
  
  /// Clear recorded waveform for a specific layer/section
  /// Call this when user wants to explicitly clear the waveform
  void clearRecordedWaveform(int layer, int section) {
    clearLines(layer, section);
    debugPrint('🗑️ [LINE_MIC] Explicitly cleared waveform for layer=$layer section=$section');
  }

  void _captureLineSamples() {
    // NOTE: _inputModuleId check removed - we use _levelProvider now (simplified architecture)
    if (_playbackState == null) return;

    // Only capture and render waveform when actually recording
    if (!_isActuallyRecording) {
      return;
    }

    // Check if we need to advance to a new line BEFORE capturing samples
    final lineCountBefore = _linesByLayerSection[_activeLayer]?[_activeSection]?.length ?? 0;
    _advanceLineIfNeeded();
    final lineCountAfter = _linesByLayerSection[_activeLayer]?[_activeSection]?.length ?? 0;
    
    if (lineCountAfter > lineCountBefore) {
      debugPrint('✅ [LINE_MIC] New line created! Total lines: $lineCountAfter');
    }

    // Get the lines list for current layer/section
    final lines = _ensureLineExists(_activeLayer, _activeSection);
    
    // Safety check - should never be empty after _ensureLineExists
    if (lines.isEmpty) {
      debugPrint('⚠️ [LINE_MIC] Lines empty after ensureLineExists, adding initial line');
      lines.add(<int>[]);
    }
    
    final currentLine = lines.last;
    final currentLineIndex = lines.length;

    // SIMPLIFIED: No Input module, use level provider for waveform visualization
    // Mic recording bypasses SunVox entirely - raw mic goes directly to WAV file
    try {
      final level = _levelProvider?.call() ?? 0.0;
      
      // Add samples to current line
      for (int i = 0; i < _samplesCount; i += _sampleStride) {
        currentLine.add((level.clamp(0.0, 1.0) * 32767.0).round());
      }
      
      // Downsample if line gets too long
      if (currentLine.length > _maxSamplesPerLine) {
        lines[lines.length - 1] = _downsampleLine(currentLine);
      }
      
      // Log periodically (every 10 captures = 1 second)
      if (currentLine.length % 1280 == 0) {
        debugPrint('📊 [LINE_MIC] Capturing: line $currentLineIndex/${lines.length}, samples=${currentLine.length}, level=${level.toStringAsFixed(3)}');
      }
      
      notifyListeners();
    } catch (e) {
      debugPrint('❌ [LINE_MIC] Capture error: $e');
    }
  }

  void _advanceLineIfNeeded() {
    final playback = _playbackState;
    final tableState = _tableState;
    if (playback == null || tableState == null) return;
    
    if (!_isActuallyRecording) return; // Only advance lines when actively recording

    final currentSection = playback.currentSection;
    final currentStep = playback.currentStep;
    final currentLoop = playback.currentSectionLoop;
    final isSongMode = playback.songMode;
    
    // Handle section changes
    if (currentSection != _lastSection) {
      debugPrint('📍 [LINE_MIC] Section changed: $_lastSection → $currentSection');
      
      // Check if new section has REC mode for this layer
      final newSectionMode = tableState.getLayerMode(_activeLayer);
      
      if (newSectionMode == LayerMode.rec) {
        // Continue recording in new section - create new line with section marker
        _activeSection = currentSection;
        _lastSection = currentSection;
        _lastLoopIndex = currentLoop;
        _startNewLine(_activeLayer, _activeSection);
        debugPrint('✅ [LINE_MIC] Continuing recording in new section $currentSection');
      } else {
        // New section doesn't have REC mode - stop waveform capture
        debugPrint('⏹️ [LINE_MIC] New section $currentSection not in REC mode, stopping waveform capture');
        stopCapture();
      }
      
      _lastStep = currentStep;
      return;
    }
    
    // Check if loop counter changed (more reliable than step wraparound)
    if (currentLoop != _lastLoopIndex) {
      debugPrint('🔄 [LINE_MIC] Loop changed: $_lastLoopIndex → $currentLoop');
      _lastLoopIndex = currentLoop;
      
      // Get loops limit for song mode
      final loopsLimit = playback.getSectionLoopsNum(currentSection);
      final currentLineNumber = (_linesByLayerSection[_activeLayer]?[_activeSection]?.length ?? 0);
      
      // In song mode: check if we've reached the loop limit
      if (isSongMode && currentLineNumber >= loopsLimit) {
        debugPrint('⏹️ [LINE_MIC] Song mode: reached loop limit $loopsLimit (line $currentLineNumber), not creating new line');
        // Don't create new line, but keep recording (native WAV continues)
      } else {
        // Create new line for next loop iteration
        _startNewLine(_activeLayer, _activeSection);
        
        final totalLines = _linesByLayerSection[_activeLayer]?[_activeSection]?.length ?? 0;
        debugPrint('✅ [LINE_MIC] Loop iteration completed! Created line $totalLines (mode=${isSongMode ? "song" : "loop"})');
      }
    }
    
    // Also use wraparound detection as fallback for loop mode (where counter doesn't increment)
    if (currentStep != _lastStep) {
      final sectionStart = tableState.getSectionStartStep(currentSection);
      final sectionSteps = tableState.getSectionStepCount(currentSection);
      final sectionEnd = sectionStart + sectionSteps;
      
      // Detect if we wrapped around to start of section (loop completed)
      final isAtSectionStart = (currentStep >= sectionStart && currentStep < sectionStart + 2);
      final wasAtSectionEnd = (_lastStep >= sectionEnd - 2 && _lastStep < sectionEnd);
      final steppedBackwards = currentStep < _lastStep;
      
      if (isAtSectionStart && (wasAtSectionEnd || steppedBackwards)) {
        // Only create line if loop counter didn't change (means we're in loop mode)
        if (currentLoop == _lastLoopIndex) {
          final loopsLimit = playback.getSectionLoopsNum(currentSection);
          final currentLineNumber = (_linesByLayerSection[_activeLayer]?[_activeSection]?.length ?? 0);
          
          // In song mode: check if we've reached the loop limit
          if (isSongMode && currentLineNumber >= loopsLimit) {
            debugPrint('⏹️ [LINE_MIC] Song mode: reached loop limit $loopsLimit, not creating new line');
          } else {
            // Create new line for next loop iteration
            _startNewLine(_activeLayer, _activeSection);
            
            final totalLines = _linesByLayerSection[_activeLayer]?[_activeSection]?.length ?? 0;
            debugPrint('✅ [LINE_MIC] Loop wraparound detected (loop mode)! Created line $totalLines');
          }
        }
      }
      
      _lastStep = currentStep;
    }
  }

  List<List<int>> _ensureLineExists(int layer, int section) {
    final bySection = _linesByLayerSection.putIfAbsent(layer, () => <int, List<List<int>>>{});
    final lines = bySection.putIfAbsent(section, () => <List<int>>[]);
    if (lines.isEmpty) {
      lines.add(<int>[]);
    }
    return lines;
  }

  /// Clear all lines for a layer/section (call when starting new recording)
  void clearLines(int layer, int section) {
    final bySection = _linesByLayerSection[layer];
    final lineCountBefore = bySection?[section]?.length ?? 0;
    if (bySection != null) {
      bySection[section] = [];
    }
    debugPrint('🗑️ [LINE_MIC] Cleared $lineCountBefore lines for layer=$layer section=$section');
    notifyListeners();
  }

  void _startNewLine(int layer, int section) {
    final lines = _ensureLineExists(layer, section);
    final lineCountBefore = lines.length;
    lines.add(<int>[]);
    final lineCountAfter = lines.length;
    debugPrint('➕ [LINE_MIC] Started new line: $lineCountBefore → $lineCountAfter for layer=$layer section=$section');
    debugPrint('   Current lines in memory: ${lines.map((l) => l.length).toList()}');
    notifyListeners();
  }

  List<int> _downsampleLine(List<int> line) {
    if (line.length <= _maxSamplesPerLine) return line;
    final reduced = <int>[];
    for (int i = 0; i < line.length; i += 2) {
      reduced.add(line[i]);
    }
    return reduced.length > _maxSamplesPerLine ? _downsampleLine(reduced) : reduced;
  }

  /// Get offset for layer/section in frames
  int getOffset(int layer, int section) {
    return _offsetsByLayerSection[layer]?[section] ?? 0;
  }

  /// Set offset for layer/section in frames
  void setOffset(int layer, int section, int offsetFrames) {
    final bySection = _offsetsByLayerSection.putIfAbsent(layer, () => {});
    bySection[section] = offsetFrames.clamp(0, SampleOffsetCalculator.maxOffset);
    
    // Update pattern events
    _updatePatternOffset(layer, section);
    
    notifyListeners();
  }

  /// Nudge offset by delta milliseconds
  void nudgeOffset(int layer, int section, int deltaMs) {
    final currentFrames = getOffset(layer, section);
    final deltaFrames = SampleOffsetCalculator.timeToFrames(
      Duration(milliseconds: deltaMs)
    );
    setOffset(layer, section, currentFrames + deltaFrames);
  }

  /// Reset offset to zero
  void resetOffset(int layer, int section) {
    setOffset(layer, section, 0);
  }

  void _updatePatternOffset(int layer, int section) {
    // Re-generate pattern with new offset
    // This requires coordination with RecordingState
    // For now, this is a placeholder - full integration will be wired later
    debugPrint('🔄 [LINE_MIC] Updating pattern offset for layer=$layer section=$section offset=${getOffset(layer, section)}');
  }

  @override
  void dispose() {
    _captureTimer?.cancel();
    super.dispose();
  }
}
