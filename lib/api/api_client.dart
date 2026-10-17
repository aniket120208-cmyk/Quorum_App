import 'package:dio/dio.dart';
import 'package:quorum_app/token_storage.dart';
import 'package:quorum_app/jwt_interceptor.dart';

class ApiClient {
  static const String _baseurl = 'https://api.newquorum.me';
  late final Dio dio;
  final TokenStorage tokenStorage = TokenStorage();
  ApiClient(){
    dio = Dio(
      BaseOptions(
        baseUrl: _baseurl,
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 20),
        headers: {
          'Content-Type' : 'application/json',
          'Accept' : 'application/json',
        }
      )
    );
    dio.interceptors.addAll([
      JwtInterceptor(
        dio: dio, 
        tokenStorage: tokenStorage,
        refreshPath: '/auth/refresh'),
      LogInterceptor(
        requestHeader: true,
        requestBody: true,
        responseBody: true,
        error: true,
      )
    ]);
  }
}