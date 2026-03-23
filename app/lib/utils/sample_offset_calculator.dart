/// Calculate sample-accurate offsets for precise positioning
/// 
/// This utility provides conversions between time durations and frame offsets
/// at 48kHz sample rate, as well as splitting offsets into coarse/fine components
/// for SunVox's 09xx and 07xx offset effects.
class SampleOffsetCalculator {
  static const int sampleRate = 48000;
  static const int coarseMultiplier = 256;
  static const int fineMax = 255;
  static const int maxOffset = 16777215; // (65535 * 256) + 255
  
  /// Convert time to frame offset
  /// 
  /// At 48kHz sample rate:
  /// - 1ms = 48 frames
  /// - 1 frame = ~0.02ms precision
  static int timeToFrames(Duration time) {
    return (time.inMicroseconds * sampleRate / 1000000).round();
  }
  
  /// Split frame offset into coarse (09xx) and fine (07xx) components
  /// 
  /// SunVox offset effects:
  /// - 09xx: Coarse offset, multiplied by 256 (0-255 range = 0-65280 frames)
  /// - 07xx: Fine offset, direct frame count (0-255 frames)
  /// 
  /// Combined: (coarse * 256) + fine = total offset in frames
  static ({int coarse, int fine}) splitOffset(int frames) {
    final clamped = frames.clamp(0, maxOffset);
    final coarse = clamped ~/ coarseMultiplier;
    final fine = clamped % coarseMultiplier;
    return (coarse: coarse, fine: fine);
  }
  
  /// Convert frames back to time duration
  static Duration framesToTime(int frames) {
    return Duration(microseconds: (frames * 1000000 / sampleRate).round());
  }
  
  /// Combine coarse and fine offsets back to total frames
  static int combineOffsets(int coarse, int fine) {
    return (coarse * coarseMultiplier) + fine;
  }
}
