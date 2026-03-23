/// Local-only library item model (replaces PlaylistItem)
/// Represents an audio file in the user's library
class LibraryItem {
  final String id; // UUID
  final String name;
  final String localPath; // Required - always local
  final String format;
  final double? duration;
  final int? sizeBytes;
  final String? sourcePatternId;
  final String? sourceCheckpointId;
  final DateTime createdAt;

  const LibraryItem({
    required this.id,
    required this.name,
    required this.localPath,
    required this.format,
    this.duration,
    this.sizeBytes,
    this.sourcePatternId,
    this.sourceCheckpointId,
    required this.createdAt,
  });

  factory LibraryItem.fromJson(Map<String, dynamic> json) {
    return LibraryItem(
      id: json['id'] as String,
      name: json['name'] as String,
      localPath: json['local_path'] as String,
      format: json['format'] as String,
      duration: json['duration'] as double?,
      sizeBytes: json['size_bytes'] as int?,
      sourcePatternId: json['source_pattern_id'] as String?,
      sourceCheckpointId: json['source_checkpoint_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'local_path': localPath,
        'format': format,
        if (duration != null) 'duration': duration,
        if (sizeBytes != null) 'size_bytes': sizeBytes,
        if (sourcePatternId != null) 'source_pattern_id': sourcePatternId,
        if (sourceCheckpointId != null) 'source_checkpoint_id': sourceCheckpointId,
        'created_at': createdAt.toIso8601String(),
      };

  LibraryItem copyWith({
    String? id,
    String? name,
    String? localPath,
    String? format,
    double? duration,
    int? sizeBytes,
    String? sourcePatternId,
    String? sourceCheckpointId,
    DateTime? createdAt,
  }) {
    return LibraryItem(
      id: id ?? this.id,
      name: name ?? this.name,
      localPath: localPath ?? this.localPath,
      format: format ?? this.format,
      duration: duration ?? this.duration,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      sourcePatternId: sourcePatternId ?? this.sourcePatternId,
      sourceCheckpointId: sourceCheckpointId ?? this.sourceCheckpointId,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
