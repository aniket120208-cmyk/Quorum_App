class CurrentUser {
  CurrentUser._();
  static String id = '';
  static String name = 'You';
  static String? avatar;
  static bool get isLoaded => id.isNotEmpty;

  static void setFromProfile(Map<String, dynamic> profile) {
    final u = profile['user'] is Map ? Map<String, dynamic>.from(profile['user']) : profile;
    id = (u['id'] ?? u['_id'] ?? '').toString();
    name = (u['name'] ?? u['username'] ?? 'You').toString();
    avatar = avatarFromJson(u);
  }

  static void clear() {
    id = '';
    name = 'You';
    avatar = null;
  }
}

String? avatarFromJson(Map j) {
  for (final key in const [
    'avatar',
    'avatarUrl',
    'profilePicture',
    'profileImage',
    'profilePic',
    'photoUrl',
    'photo',
    'picture',
    'imageUrl',
    'image',
  ]) {
    final v = j[key];
    if (v is String && v.trim().isNotEmpty) return v.trim();
  }
  return null;
}