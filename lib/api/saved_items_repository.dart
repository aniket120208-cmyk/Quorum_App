import 'package:dio/dio.dart';
import 'package:quorum_app/api/api_client.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/models/community_models.dart';
import 'package:quorum_app/models/saved_item_models.dart';

class SavedItemsRepository {
  SavedItemsRepository._(this.api);
  static final SavedItemsRepository instance = SavedItemsRepository._(ApiClient.instance);
  final ApiClient api;
  Dio get _dio => api.dio;

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final data = e.response?.data;
      var msg = data is Map ? data['message']?.toString() : null;
      if (msg == null || msg.isEmpty) {
        switch (status) {
          case null:
            msg = 'Cannot reach the server. Try again.';
          case 400:
            msg = 'That request was not valid.';
          case 401:
            msg = 'Please sign in again.';
          case 404:
            msg = 'That item was not found.';
          case 409:
            msg = 'A collection with this name already exists.';
          default:
            msg = 'Request failed ($status).';
        }
      }
      throw ApiException(msg, statusCode: status);
    }
  }

  dynamic _data(Response r) => r.data is Map ? r.data['data'] : null;
  Map<String, dynamic> _map(dynamic d) => Map<String, dynamic>.from(d as Map);

  Future<SavedItem> save({
    required SavedItemType type,
    required String itemId,
    String? note,
    String? collectionId,
  }) =>
      _guard(() async {
        final r = await _dio.post('/api/saved-items', data: {
          'itemType': type.value,
          'itemId': itemId,
          if (note != null && note.isNotEmpty) 'note': note,
          if (collectionId != null) 'collectionId': collectionId,
        });
        return SavedItem.fromJson(_map(_data(r)));
      });

  Future<PageResult<SavedItem>> list({
    SavedItemType? type,
    String? collectionId,
    String? search,
    String? cursor,
    int limit = 20,
  }) =>
      _guard(() async {
        final r = await _dio.get('/api/saved-items', queryParameters: {
          'limit': limit,
          if (type != null) 'itemType': type.value,
          if (collectionId != null) 'collectionId': collectionId,
          if (search != null && search.isNotEmpty) 'search': search,
          if (cursor != null) 'cursor': cursor,
        });
        final d = _data(r);
        final raw = d is Map && d['items'] is List ? d['items'] as List : const [];
        final items = raw.map((e) => SavedItem.fromJson(_map(e))).toList();
        final next = d is Map ? d['nextCursor']?.toString() : null;
        return PageResult<SavedItem>(
          items,
          next,
          d is Map && d['hasNextPage'] == true && next != null,
        );
      });

  Future<void> update(
    String id, {
    String? note,
    bool clearNote = false,
    String? collectionId,
    bool clearCollection = false,
  }) =>
      _guard(() async {
        await _dio.patch('/api/saved-items/$id', data: {
          if (clearNote) 'note': null else if (note != null) 'note': note,
          if (clearCollection) 'collectionId': null else if (collectionId != null) 'collectionId': collectionId,
        });
      });

  Future<void> remove(String id) => _guard(() async {
        await _dio.delete('/api/saved-items/$id');
      });

  Future<List<SavedCollection>> collections() => _guard(() async {
        final r = await _dio.get('/api/saved-items/collections');
        final d = _data(r);
        final raw = d is List ? d : const [];
        return raw.map((e) => SavedCollection.fromJson(_map(e))).toList();
      });

  Future<SavedCollection> createCollection(String name, {String? description, String? color}) =>
      _guard(() async {
        final r = await _dio.post('/api/saved-items/collections', data: {
          'name': name,
          if (description != null && description.isNotEmpty) 'description': description,
          if (color != null) 'color': color,
        });
        return SavedCollection.fromJson(_map(_data(r)));
      });

  Future<void> updateCollection(
    String id, {
    String? name,
    String? description,
    bool clearDescription = false,
    String? color,
    bool clearColor = false,
  }) =>
      _guard(() async {
        await _dio.patch('/api/saved-items/collections/$id', data: {
          if (name != null) 'name': name,
          if (clearDescription) 'description': null else if (description != null) 'description': description,
          if (clearColor) 'color': null else if (color != null) 'color': color,
        });
      });

  Future<void> deleteCollection(String id) => _guard(() async {
        await _dio.delete('/api/saved-items/collections/$id');
      });
}