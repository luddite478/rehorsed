/// Local-only pattern model (replaces Thread)
/// Represents a music pattern with its checkpoints
class Pattern {
  final String id; // UUID for local identification
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<String> checkpointIds;
  final Map<String, dynamic>? metadata;

  const Pattern({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.checkpointIds,
    this.metadata,
  });

  factory Pattern.fromJson(Map<String, dynamic> json) {
    return Pattern(
      id: json['id'] as String,
      name: json['name'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      checkpointIds: (json['checkpoint_ids'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'checkpoint_ids': checkpointIds,
        if (metadata != null) 'metadata': metadata,
      };

  Pattern copyWith({
    String? id,
    String? name,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<String>? checkpointIds,
    Map<String, dynamic>? metadata,
  }) {
    return Pattern(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      checkpointIds: checkpointIds ?? this.checkpointIds,
      metadata: metadata ?? this.metadata,
    );
  }
}
