import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:quorum_app/models/token_model.dart';
import 'package:quorum_app/token_storage.dart';
import 'package:quorum_app/jwt_interceptor.dart';
import 'package:flutter/foundation.dart';

class ApiClient {
  static const String _baseurl = 'https://api.newquorum.me';
  late final Dio dio;
  final TokenStorage tokenStorage = TokenStorage();
  static final ApiClient instance = ApiClient();

  Future<String?>? _refreshing;
  Future<String?> freshAccessToken({bool force = false}) async {
    final current = await tokenStorage.getAccessToken();
    if (!force && current != null && current.isNotEmpty && !_isExpiring(current)) {
      return current;
    }
    final inFlight = _refreshing ??= _refreshTokens().whenComplete(() => _refreshing = null);
    final refreshed = await inFlight;
    return refreshed ?? current;
  }

  Future<String?> _refreshTokens() async {
    final refreshToken = await tokenStorage.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) return null;
    try {
      final res = await Dio(BaseOptions(
        baseUrl: _baseurl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        headers: {'x-client-platform': 'mobile'},
      )).post('/api/auth/refresh-token', data: {'refreshToken': refreshToken});
      final tokens = TokenModel.fromJson(Map<String, dynamic>.from(res.data['data'] as Map));
      await tokenStorage.saveTokens(tokens);
      return tokens.accessToken;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401 || code == 403) await tokenStorage.clearTokens();
      return null;
    } catch (_) {
      return null;
    }
  }

  bool _isExpiring(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length != 3) return false;
      final payload = json.decode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1])))) as Map;
      final exp = payload['exp'];
      if (exp is! num) return false;
      final expiry = DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000);
      return DateTime.now().isAfter(expiry.subtract(const Duration(seconds: 30)));
    } catch (_) {
      return false;
    }
  }
  ApiClient(){
    dio = Dio(
      BaseOptions(
        baseUrl: _baseurl,
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 20),
        headers: {
          'Content-Type' : 'application/json',
          'Accept' : 'application/json',
          'x-client-platform' : 'mobile',
        }
      )
    );
    dio.interceptors.add(
      JwtInterceptor(
        dio: dio,
        tokenStorage: tokenStorage,
        refreshPath: '/api/auth/refresh-token',
      ),
    );

    if (kDebugMode) {
    dio.interceptors.add(
    LogInterceptor(
      requestHeader: true,
      requestBody: true,
      responseBody: true,
      error: true,
      ),
    );
  }
  }
}