class ChatMessage {
  final String id;
  final String role;
  final String content;
  final DateTime timestamp;
  final String? imagePath;

  ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    DateTime? timestamp,
    this.imagePath,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id, 'role': role, 'content': content,
    'timestamp': timestamp.toIso8601String(),
    'imagePath': imagePath,
  };

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
    id: j['id'], role: j['role'], content: j['content'],
    timestamp: DateTime.parse(j['timestamp']),
    imagePath: j['imagePath'],
  );
}
