class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, {this.statusCode});

  bool get isRateLimited => statusCode == 429;
  bool get isEmailNotVerified => statusCode == 403 && message.toLowerCase().contains('verif');

  @override
  String toString() => message;
}

String errorText(Object e) => e is ApiException ? e.message : 'Something went wrong. ($e)';