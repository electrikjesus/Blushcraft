class PlayerInfo {
  const PlayerInfo({
    required this.id,
    required this.name,
    this.score = 0,
  });

  final String id;
  final String name;
  final int score;

  PlayerInfo copyWith({String? id, String? name, int? score}) {
    return PlayerInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      score: score ?? this.score,
    );
  }

  factory PlayerInfo.fromJson(Map<String, dynamic> json) {
    return PlayerInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      score: json['score'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'score': score,
      };
}
