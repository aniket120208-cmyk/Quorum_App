class FormValidators {
  FormValidators._();

  static String? _range(String? value, int min, int max, String message) {
    final length = (value ?? '').trim().length;
    return (length < min || length > max) ? message : null;
  }

  static String? _maxLength(String? value, int max, String message) {
    return (value ?? '').trim().length > max ? message : null;
  }

  static String? communityName(String? value) =>
      _range(value, 2, 100, 'Community name must be between 2 and 100 characters');

  static String? communityDescription(String? value) =>
      _maxLength(value, 250, 'Community description cannot exceed 250 characters');

  static String? organizationName(String? value) =>
      _range(value, 2, 100, 'Organization name must be between 2 and 100 characters');

  static String? organizationDescription(String? value) =>
      _maxLength(value, 250, 'Organization description cannot exceed 250 characters');
}