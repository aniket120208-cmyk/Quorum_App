import 'package:dio/dio.dart';
import 'api_client.dart';
import 'package:quorum_app/models/token_model.dart';
import 'api_exception.dart';
import 'package:quorum_app/api/current_user.dart';
import 'package:quorum_app/api/socket_service.dart';

class AuthService {
  final ApiClient apiClient;
  AuthService(this.apiClient);
  static final AuthService instance = AuthService(ApiClient.instance);

  ApiException _toApiException(DioException e) {
    final data = e.response?.data;
    final message = (data is Map && data['message'] != null) ? data['message'].toString() : 'Cannot reach the server. Try again.';
    return ApiException(message, statusCode: e.response?.statusCode);
  }

  Future<TokenModel> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await apiClient.dio.post(
        '/api/auth/login',
        data: {
          'email': email,
          'password': password,
        },
      );
      final tokens = TokenModel.fromJson(response.data['data']);
      await apiClient.tokenStorage.saveTokens(tokens);
      SocketService.instance.disconnect();
      CurrentUser.clear();
      return tokens;
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  Future<Map<String, dynamic>> getUserProfile() async {
    try {
      final response = await apiClient.dio.get('/api/auth/me');
      final body = response.data;
      if (body is Map<String, dynamic> && body['data'] is Map<String, dynamic>) {
        return body['data'] as Map<String, dynamic>;
      }
      throw ApiException('Unexpected response from server.');
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  Future<void> logout() async {
    try {
      await apiClient.dio.post('/api/auth/logout');
    } finally {
      SocketService.instance.disconnect();
      CurrentUser.clear();
      await apiClient.tokenStorage.clearTokens();
    }
  }

  Future<bool> hasStoredSession() async {
    final token = await apiClient.tokenStorage.getRefreshToken();
    return token != null && token.isNotEmpty;
  }
}