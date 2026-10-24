import 'package:quorum_app/api/saved_items_repository.dart';
import 'package:quorum_app/models/saved_item_models.dart';

class SavedItemsStore {
  SavedItemsStore._();
  static final SavedItemsStore instance = SavedItemsStore._();
  final Map<String, String> _ids = {};
  bool _loaded = false;
  Future<void>? _loading;
  String _key(SavedItemType type, String itemId) => '${type.value}:$itemId';

  Future<void> ensureLoaded() {
    if (_loaded) return Future.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      String? cursor;
      var pages = 0;
      do {
        final page = await SavedItemsRepository.instance.list(cursor: cursor, limit: 50);
        for (final item in page.items) {
          _ids[_key(item.type, item.itemId)] = item.id;
        }
        cursor = page.hasMore ? page.cursor : null;
        pages++;
      } while (cursor != null && pages < 20);
      _loaded = true;
    } catch (_) {
    } finally {
      _loading = null;
    }
  }

  bool isSaved(SavedItemType type, String itemId) => _ids.containsKey(_key(type, itemId));

  Future<bool> toggle(SavedItemType type, String itemId) async {
    await ensureLoaded();
    final key = _key(type, itemId);
    final existing = _ids[key];
    if (existing != null) {
      await SavedItemsRepository.instance.remove(existing);
      _ids.remove(key);
      return false;
    }
    final item = await SavedItemsRepository.instance.save(type: type, itemId: itemId);
    _ids[key] = item.id;
    return true;
  }

  void forget(String savedId) => _ids.removeWhere((_, v) => v == savedId);
  void remember(SavedItem item) => _ids[_key(item.type, item.itemId)] = item.id;

  void clear() {
    _ids.clear();
    _loaded = false;
    _loading = null;
  }
}