import 'package:dio/dio.dart';
import 'api_client.dart';
import 'package:quorum_app/models/token_model.dart';
import 'api_exception.dart';

class AuthService {
  final ApiClient apiClient;
  AuthService(this.apiClient);
  static final AuthService instance = AuthService(ApiClient.instance);
  Future<TokenModel> login({
    required String email,
    required String password,
  }) async{
    try{
      final response = await apiClient.dio.post(
        '/api/auth/login',
        data: {
          'email' : email,
          'password' : password,
        }
      );
      final tokens = TokenModel.fromJson(response.data['data']);
      await apiClient.tokenStorage.saveTokens(tokens);
      return tokens;
    } on DioException catch (e) {
      final data = e.response?.data;
      final message = (data is Map && data['message'] != null)
        ? data['message'].toString()
        : 'Cannot reach the server. Try again.';
      throw ApiException(message, statusCode: e.response?.statusCode);
    }
  }
  Future<Map<String, dynamic>> getUserProfile() async{
    try{
      final response = await apiClient.dio.get('/api/auth/me');
      return response.data as Map<String, dynamic>;
    } on DioException catch(e){
      throw Exception(e.response?.data['message'] ?? 'Failed to load profile');
    }
  }
  Future<void> logout() async{
    try{
      final refreshToken = await apiClient.tokenStorage.getRefreshToken();
      if(refreshToken != null){
        await apiClient.dio.post(
          '/api/auth/logout',
          data: {'refreshToken': refreshToken},
        );
      } 
    } finally{
      await apiClient.tokenStorage.clearTokens();
    }
  }
  Future<bool> hasStoredSession() async {
    final token = await ApiClient.instance.tokenStorage.getRefreshToken();
    return token != null && token.isNotEmpty;
  }
}