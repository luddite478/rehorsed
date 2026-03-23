import 'package:flutter/material.dart';
import 'sequencer_screen_v2.dart';

/// Main sequencer screen - simplified to always use V2
/// V1 has been removed as part of offline transformation
class PatternScreen extends StatelessWidget {
  final Map<String, dynamic>? initialSnapshot;
  
  const PatternScreen({super.key, this.initialSnapshot});

  @override
  Widget build(BuildContext context) {
    return SequencerScreenV2(initialSnapshot: initialSnapshot);
  }
}
