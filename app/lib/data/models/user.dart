class AppUser {
  final String id;
  final String name;
  final String email;
  final String role;
  final String? phone;
  final String? branch;
  final bool isActive;

  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.phone,
    this.branch,
    required this.isActive,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['_id'] as String,
        name: json['name'] as String,
        email: json['email'] as String,
        role: json['role'] as String,
        phone: json['phone'] as String?,
        branch: json['branch'] as String?,
        isActive: json['isActive'] as bool? ?? true,
      );
}
