class User {
  final String id;
  final String username;
  final String nickname;
  final String? token;

  const User({
    required this.id,
    required this.username,
    required this.nickname,
    this.token,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      username: json['username'] as String,
      nickname: json['nickname'] as String? ?? json['username'] as String,
      token: json['token'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'nickname': nickname,
      if (token != null) 'token': token,
    };
  }
}
