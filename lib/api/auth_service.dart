import 'package:dio/dio.dart';
import 'api_client.dart';
import 'package:quorum_app/models/token_model.dart';
import 'api_exception.dart';
import 'package:quorum_app/api/current_user.dart';
import 'package:quorum_app/api/notification_service.dart';
import 'package:quorum_app/api/saved_items_store.dart';
import 'package:quorum_app/api/socket_service.dart';

class AuthResult {
  final bool authenticated;
  final Map<String, dynamic> user;
  const AuthResult({required this.authenticated, required this.user});
  bool get isOnboarded => user['isOnboarded'] == true;
}

class AuthService {
  final ApiClient apiClient;
  AuthService(this.apiClient);
  static final AuthService instance = AuthService(ApiClient.instance);

  ApiException _toApiException(DioException e) {
    final data = e.response?.data;
    final status = e.response?.statusCode;
    final fallback = status == 429 ? 'Too many attempts. Please try again later.' : 'Cannot reach the server. Try again.';
    final message = (data is Map && data['message'] != null) ? data['message'].toString() : fallback;
    return ApiException(message, statusCode: status);
  }

  static Map<String, dynamic> userFrom(dynamic data) {
    if (data is! Map) return {};
    final map = Map<String, dynamic>.from(data);
    if (map['user'] is Map) return Map<String, dynamic>.from(map['user']);
    return map;
  }

  Future<AuthResult> _completeAuth(dynamic data) async {
    final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    final hasTokens = map['accessToken'] != null && map['refreshToken'] != null;
    if (!hasTokens) {
      return AuthResult(authenticated: false, user: userFrom(map));
    }
    await apiClient.tokenStorage.saveTokens(TokenModel.fromJson(map));
    SocketService.instance.disconnect();
    SavedItemsStore.instance.clear();
    CurrentUser.clear();
    var user = userFrom(map);
    if (!user.containsKey('isOnboarded')) {
      user = userFrom(await getUserProfile());
    }
    return AuthResult(authenticated: true, user: user);
  }

  Future<AuthResult> login({
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
      return await _completeAuth(response.data['data']);
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  Future<void> register({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      await apiClient.dio.post(
        '/api/auth/register',
        data: {
          'name': name,
          'email': email,
          'password': password,
        },
      );
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  Future<void> sendVerificationOtp(String email) async {
    try {
      await apiClient.dio.post(
        '/api/otp/send-otp',
        data: {'email': email, 'type': 'verification'},
      );
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  Future<AuthResult> verifyEmail({
    required String email,
    required String otp,
  }) async {
    try {
      final response = await apiClient.dio.post(
        '/api/otp/verify-email',
        data: {
          'email': email,
          'otp': otp,
        },
      );
      return await _completeAuth(response.data['data']);
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  Future<void> forgotPassword(String email) async {
    try {
      await apiClient.dio.post(
        '/api/otp/forgot-password',
        data: {'email': email},
      );
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  Future<void> resetPassword({
    required String email,
    required String otp,
    required String newPassword,
  }) async {
    try {
      await apiClient.dio.post(
        '/api/otp/reset-password',
        data: {
          'email': email,
          'otp': otp,
          'newPassword': newPassword,
        },
      );
      SocketService.instance.disconnect();
      SavedItemsStore.instance.clear();
      CurrentUser.clear();
      await apiClient.tokenStorage.clearTokens();
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  Future<Map<String, dynamic>> saveOnboarding(List<String> useCases) async {
    try {
      final response = await apiClient.dio.patch(
        '/api/users/onboarding',
        data: {'useCases': useCases},
      );
      return userFrom(response.data['data']);
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
    await NotificationService.instance.stop();
    try {
      await apiClient.dio.post('/api/auth/logout');
    } finally {
      SocketService.instance.disconnect();
      SavedItemsStore.instance.clear();
      CurrentUser.clear();
      await apiClient.tokenStorage.clearTokens();
    }
  }

  Future<bool> hasStoredSession() async {
    final token = await apiClient.tokenStorage.getRefreshToken();
    return token != null && token.isNotEmpty;
  }
}