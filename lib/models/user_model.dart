class AppUser {
  final String id;
  final String email;
  final String displayName;
  final DateTime createdAt;

  const AppUser({
    required this.id,
    required this.email,
    required this.displayName,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'email': email,
        'display_name': displayName,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory AppUser.fromMap(Map<String, dynamic> m) => AppUser(
        id: m['id'] as String,
        email: m['email'] as String,
        displayName: m['display_name'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
      );

  factory AppUser.fromSupabase(Map<String, dynamic> m) => AppUser(
        id: m['id'] as String,
        email: m['email'] as String,
        displayName: m['display_name'] as String,
        createdAt: m['created_at'] != null
            ? DateTime.parse(m['created_at'] as String)
            : DateTime.now(),
      );
}
