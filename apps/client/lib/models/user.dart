enum UserRole {
  guest,
  user,
  admin;

  /// 返回 l10n key，UI 层使用 l10n.get() 获取显示文本
  String get labelKey {
    switch (this) {
      case UserRole.guest:
        return 'guest';
      case UserRole.user:
        return 'general_open_user';
      case UserRole.admin:
        return 'management_member';
    }
  }

  /// 可选择的内容阶段
  List<String> get allowedContentEnvs {
    switch (this) {
      case UserRole.guest:
        return ['production'];
      case UserRole.user:
        return ['production', 'test'];
      case UserRole.admin:
        return ['production', 'test', 'draft'];
    }
  }
}

class User {
  final String id;
  final String username;
  final String nickname;
  final String? token;
  final UserRole role;

  const User({
    required this.id,
    required this.username,
    required this.nickname,
    this.token,
    this.role = UserRole.user,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      username: json['username'] as String,
      nickname: json['nickname'] as String? ?? json['username'] as String,
      token: json['token'] as String?,
      role: _parseRole(json['role'] as String?),
    );
  }

  static UserRole _parseRole(String? roleStr) {
    switch (roleStr) {
      case 'admin':
        return UserRole.admin;
      case 'guest':
        return UserRole.guest;
      default:
        return UserRole.user;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'nickname': nickname,
      if (token != null) 'token': token,
      'role': role.name,
    };
  }
}
