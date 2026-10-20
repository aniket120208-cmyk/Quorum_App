class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

String errorText(Object e) => e is ApiException ? e.message : 'Something went wrong. ($e)';