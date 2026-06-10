class User {
  final String id;
  final String phoneNumber;
  final String username;
  final String plan;
  final DateTime? planExpiresAt;

  User({
    required this.id,
    required this.phoneNumber,
    required this.username,
    this.plan = 'free',
    this.planExpiresAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'].toString(),
      phoneNumber: json['phone_number'] ?? '',
      username: json['username'] ?? json['phone_number'] ?? '',
      plan: json['plan'] ?? 'free',
      planExpiresAt: json['plan_expires_at'] != null 
          ? DateTime.parse(json['plan_expires_at']) 
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'phone_number': phoneNumber,
      'username': username,
      'plan': plan,
      'plan_expires_at': planExpiresAt?.toIso8601String(),
    };
  }
}