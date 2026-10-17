import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:quorum_app/models/token_model.dart';

class TokenStorage {
  static const _storage = FlutterSecureStorage();
  static const _accessToken = 'access_token';
  static const _refreshTolen = 'refresh_token';

  Future<void> saveTokens(TokenModel token) async{
    await _storage.write(key: _accessToken, value: token.accessToken);
    await _storage.write(key: _refreshTolen, value: token.refreshToken);
  }

  Future<String?> getAccessToken() async{
    return await _storage.read(key: _accessToken);
  }

  Future<String?> getRefreshToken() async{
    return await _storage.read(key: _refreshTolen);
  }

  Future<void> clearTokens() async{
    await _storage.delete(key: _accessToken);
    await _storage.delete(key: _refreshTolen);
  }
}