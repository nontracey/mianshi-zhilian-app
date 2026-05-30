class Ticket {
  final String id;
  final String userId;
  final String type; // 'password_reset', 'feedback', 'question'
  final String subject;
  final String description;
  final List<String> imageUrls;
  final String status; // 'pending', 'processing', 'resolved', 'closed'
  final DateTime createdAt;
  final DateTime? resolvedAt;
  final String? adminReply;

  const Ticket({
    required this.id,
    required this.userId,
    required this.type,
    required this.subject,
    required this.description,
    this.imageUrls = const [],
    this.status = 'pending',
    required this.createdAt,
    this.resolvedAt,
    this.adminReply,
  });

  factory Ticket.fromJson(Map<String, dynamic> json) => Ticket(
    id: json['id'] as String,
    userId: json['user_id'] as String,
    type: json['type'] as String,
    subject: json['subject'] as String,
    description: json['description'] as String,
    imageUrls: (json['image_urls'] as List<dynamic>?)
        ?.map((e) => e.toString())
        .toList() ?? [],
    status: json['status'] as String? ?? 'pending',
    createdAt: DateTime.parse(json['created_at'] as String),
    resolvedAt: json['resolved_at'] != null
        ? DateTime.parse(json['resolved_at'] as String)
        : null,
    adminReply: json['admin_reply'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'type': type,
    'subject': subject,
    'description': description,
    'image_urls': imageUrls,
    'status': status,
    'created_at': createdAt.toIso8601String(),
    'resolved_at': resolvedAt?.toIso8601String(),
    'admin_reply': adminReply,
  };
}
