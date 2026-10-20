class CurrentUser {
  CurrentUser._();
  static String id = '';
  static String name = 'You';
  static bool get isLoaded => id.isNotEmpty;

  static void setFromProfile(Map<String, dynamic> profile) {
    final u = profile['user'] is Map ? Map<String, dynamic>.from(profile['user']) : profile;
    id = (u['id'] ?? u['_id'] ?? '').toString();
    name = (u['name'] ?? u['username'] ?? 'You').toString();
  }

  static void clear() {
    id = '';
    name = 'You';
  }
}