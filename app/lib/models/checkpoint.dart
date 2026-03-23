/// Local-only checkpoint model (replaces Message)
/// Represents a saved state of a pattern with optional audio recording
class Checkpoint {
  final String id; // UUID
  final DateTime createdAt;
  final String patternId;
  final Map<String, dynamic> snapshot;
  final Map<String, dynamic>? snapshotMetadata;
  final String? audioFilePath; // Local file path for recording
  final double? audioDuration;

  const Checkpoint({
    required this.id,
    required this.createdAt,
    required this.patternId,
    required this.snapshot,
    this.snapshotMetadata,
    this.audioFilePath,
    this.audioDuration,
  });

  factory Checkpoint.fromJson(Map<String, dynamic> json) {
    return Checkpoint(
      id: json['id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      patternId: json['pattern_id'] as String,
      snapshot: Map<String, dynamic>.from(json['snapshot'] as Map<String, dynamic>),
      snapshotMetadata: json['snapshot_metadata'] == null
          ? null
          : Map<String, dynamic>.from(json['snapshot_metadata'] as Map<String, dynamic>),
      audioFilePath: json['audio_file_path'] as String?,
      audioDuration: json['audio_duration'] as double?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'created_at': createdAt.toIso8601String(),
        'pattern_id': patternId,
        'snapshot': snapshot,
        if (snapshotMetadata != null) 'snapshot_metadata': snapshotMetadata,
        if (audioFilePath != null) 'audio_file_path': audioFilePath,
        if (audioDuration != null) 'audio_duration': audioDuration,
      };

  Checkpoint copyWith({
    String? id,
    DateTime? createdAt,
    String? patternId,
    Map<String, dynamic>? snapshot,
    Map<String, dynamic>? snapshotMetadata,
    String? audioFilePath,
    double? audioDuration,
  }) {
    return Checkpoint(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      patternId: patternId ?? this.patternId,
      snapshot: snapshot ?? this.snapshot,
      snapshotMetadata: snapshotMetadata ?? this.snapshotMetadata,
      audioFilePath: audioFilePath ?? this.audioFilePath,
      audioDuration: audioDuration ?? this.audioDuration,
    );
  }
}
