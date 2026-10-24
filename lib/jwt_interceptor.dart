import 'package:dio/dio.dart';
import 'token_storage.dart';
import 'package:quorum_app/models/token_model.dart';

class JwtInterceptor extends QueuedInterceptor{
  final Dio dio;
  final TokenStorage tokenStorage;
  final String refreshPath;

  JwtInterceptor({
    required this.dio,
    required this.tokenStorage,
    this.refreshPath = '/api/auth/refresh-token',
  });

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async{
    final isRefreshRequest = options.path.contains(refreshPath);
    if(!isRefreshRequest){
      final accessToken = await tokenStorage.getAccessToken();
      if(accessToken!= null && accessToken.isNotEmpty){
        options.headers['Authorization'] = 'Bearer $accessToken';
      }
    }
    return handler.next(options);
  }
  @override 
    Future<void> onError(
      DioException err,
      ErrorInterceptorHandler handler,
    ) async{
      final isUnauthorized = err.response?.statusCode == 401;
      final isRefreshRequest = err.requestOptions.path.contains(refreshPath);
      final path = err.requestOptions.path;
      if (path.contains('/api/auth/login') || path.contains('/api/auth/register') || path.contains('/api/otp/')) {
        return handler.next(err);
      }
      if(isUnauthorized && !isRefreshRequest){
        final refreshToken = await tokenStorage.getRefreshToken();
        if(refreshToken !=null && refreshToken.isNotEmpty){
          try{
            final refreshDio = Dio(BaseOptions(
              baseUrl: dio.options.baseUrl,
              headers: {'x-client-platform': 'mobile'},
              ));
            final response = await refreshDio.post(
              refreshPath,
              data: {'refreshToken' : refreshToken},
            );
            final newTokens = TokenModel.fromJson(response.data['data']);
            await tokenStorage.saveTokens(newTokens);
            final RequestOptions = err.requestOptions;
            RequestOptions.headers['Authorization'] = 'Bearer ${newTokens.accessToken}';
            final retryResponse = await dio.fetch(RequestOptions);
            return handler.resolve(retryResponse);
          } on DioException catch (e) {
              if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
              await tokenStorage.clearTokens();
            }
            return handler.next(err);
          }  catch (e) {
              return handler.next(err);
            }
        }
      }
      return handler.next(err);  
    }
}