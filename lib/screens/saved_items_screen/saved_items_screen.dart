import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/chat_repository.dart';
import 'package:quorum_app/api/community_repository.dart';
import 'package:quorum_app/api/current_user.dart';
import 'package:quorum_app/api/saved_items_repository.dart';
import 'package:quorum_app/api/saved_items_store.dart';
import 'package:quorum_app/models/community_models.dart';
import 'package:quorum_app/models/saved_item_models.dart';
import 'package:quorum_app/screens/chat_screen/attachment_widgets.dart';
import 'package:quorum_app/screens/chat_screen/chat_room_screen.dart';
import 'package:quorum_app/screens/community_screen/communtiy_details_screen.dart';
import 'package:quorum_app/screens/community_screen/post_comments_screen.dart';
import 'package:quorum_app/screens/organization_screen/organization_widgets.dart';

class SavedItemsScreen extends StatefulWidget {
  const SavedItemsScreen({super.key});

  @override
  State<SavedItemsScreen> createState() => _SavedItemsScreenState();
}

class _SavedItemsScreenState extends State<SavedItemsScreen> {
  static const List<Color> _palette = [
    Color(0xFF3388FF),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
    Color(0xFF8B5CF6),
    Color(0xFFEC4899),
    Color(0xFF14B8A6),
    Color(0xFF64748B),
  ];

  final _repo = SavedItemsRepository.instance;
  final _scroll = ScrollController();
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  List<SavedItem> _items = [];
  List<SavedCollection> _collections = [];
  String? _cursor;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  SavedItemType? _type;
  String? _collectionId;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadCollections();
    _reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 300) _loadMore();
  }

  Future<void> _loadCollections() async {
    try {
      final list = await _repo.collections();
      if (!mounted) return;
      setState(() {
        _collections = list;
        if (_collectionId != null && !list.any((c) => c.id == _collectionId)) _collectionId = null;
      });
    } catch (_) {}
  }

  Future<void> _reload({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final page = await _repo.list(type: _type, collectionId: _collectionId, search: _search);
      if (!mounted) return;
      for (final item in page.items) {
        SavedItemsStore.instance.remember(item);
      }
      setState(() {
        _items = page.items;
        _cursor = page.cursor;
        _hasMore = page.hasMore;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent || _items.isEmpty) _error = errorText(e);
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _cursor == null) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _repo.list(
        type: _type,
        collectionId: _collectionId,
        search: _search,
        cursor: _cursor,
      );
      if (!mounted) return;
      final known = _items.map((e) => e.id).toSet();
      setState(() {
        _items = [..._items, ...page.items.where((e) => !known.contains(e.id))];
        _cursor = page.cursor;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      orgToast(context, errorText(e), error: true);
    }
  }

  Future<void> _refreshAll() async {
    await Future.wait([_loadCollections(), _reload(silent: true)]);
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      final q = value.trim();
      if (q == _search) return;
      _search = q;
      _reload();
    });
  }

  void _setType(SavedItemType? type) {
    if (_type == type) return;
    setState(() => _type = type);
    _reload();
  }

  void _setCollection(String? id) {
    if (_collectionId == id) return;
    setState(() => _collectionId = id);
    _reload();
  }

  Future<void> _editNote(SavedItem item) async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => _NoteDialog(initial: item.note ?? ''),
    );
    if (text == null || !mounted) return;
    final value = text.trim();
    if (value == (item.note ?? '')) return;
    try {
      await _repo.update(item.id, note: value, clearNote: value.isEmpty);
      if (!mounted) return;
      _replace(item.id, (x) => x.copyWith(note: value, clearNote: value.isEmpty));
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    }
  }

  void _replace(String id, SavedItem Function(SavedItem) change) {
    final i = _items.indexWhere((e) => e.id == id);
    if (i == -1) return;
    setState(() => _items[i] = change(_items[i]));
  }

  Future<void> _moveItem(SavedItem item) async {
    final picked = await showModalBottomSheet<Object>(
      context: context,
      backgroundColor: orgCard,
      shape: orgSheetShape,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text('Move to collection',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            ListTile(
              leading: const Icon(Icons.folder_off_outlined, color: orgMuted),
              title: const Text('No collection', style: TextStyle(color: Colors.white)),
              trailing: item.collection == null ? const Icon(Icons.check_rounded, color: orgTeal) : null,
              onTap: () => Navigator.pop(ctx, false),
            ),
            for (final c in _collections)
              ListTile(
                leading: Icon(Icons.folder_rounded, color: parseHexColor(c.color) ?? orgTeal),
                title: Text(c.name, style: const TextStyle(color: Colors.white)),
                trailing: item.collection?.id == c.id ? const Icon(Icons.check_rounded, color: orgTeal) : null,
                onTap: () => Navigator.pop(ctx, c),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    try {
      if (picked is SavedCollection) {
        await _repo.update(item.id, collectionId: picked.id);
        if (!mounted) return;
        if (_collectionId != null && _collectionId != picked.id) {
          setState(() => _items = _items.where((e) => e.id != item.id).toList());
        } else {
          _replace(
            item.id,
            (x) => x.copyWith(
              collection: SavedCollectionRef(id: picked.id, name: picked.name, color: picked.color),
            ),
          );
        }
      } else {
        await _repo.update(item.id, clearCollection: true);
        if (!mounted) return;
        if (_collectionId != null) {
          setState(() => _items = _items.where((e) => e.id != item.id).toList());
        } else {
          _replace(item.id, (x) => x.copyWith(clearCollection: true));
        }
      }
      _loadCollections();
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    }
  }

  Future<void> _removeItem(SavedItem item) async {
    final ok = await orgConfirm(
      context,
      title: 'Remove saved item?',
      body: 'This only removes your bookmark. The original content is not affected.',
      action: 'Remove',
    );
    if (!ok || !mounted) return;
    try {
      await _repo.remove(item.id);
      SavedItemsStore.instance.forget(item.id);
      if (!mounted) return;
      setState(() => _items = _items.where((e) => e.id != item.id).toList());
      _loadCollections();
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    }
  }

  Future<void> _createCollection() async {
    final result = await showDialog<_CollectionInput>(
      context: context,
      builder: (_) => _CollectionDialog(title: 'New collection', action: 'Create', palette: _palette),
    );
    if (result == null || !mounted) return;
    try {
      final c = await _repo.createCollection(result.name, description: result.description, color: result.color);
      if (!mounted) return;
      setState(() => _collections = [..._collections, c]);
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    }
  }

  Future<void> _collectionActions(SavedCollection c) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: orgCard,
      shape: orgSheetShape,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: orgTeal),
              title: const Text('Edit collection', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
              title: const Text('Delete collection', style: TextStyle(color: Colors.redAccent)),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'edit') {
      final result = await showDialog<_CollectionInput>(
        context: context,
        builder: (_) => _CollectionDialog(
          title: 'Edit collection',
          action: 'Save',
          palette: _palette,
          initialName: c.name,
          initialDescription: c.description ?? '',
          initialColor: c.color,
        ),
      );
      if (result == null || !mounted) return;
      try {
        await _repo.updateCollection(
          c.id,
          name: result.name,
          description: result.description,
          clearDescription: result.description == null,
          color: result.color,
          clearColor: result.color == null,
        );
        await _loadCollections();
        await _reload(silent: true);
      } catch (e) {
        if (mounted) orgToast(context, errorText(e), error: true);
      }
    } else {
      final ok = await orgConfirm(
        context,
        title: 'Delete collection?',
        body: 'Items in "${c.name}" stay in your saved list and become unassigned.',
        action: 'Delete',
      );
      if (!ok || !mounted) return;
      try {
        await _repo.deleteCollection(c.id);
        if (_collectionId == c.id) _collectionId = null;
        await _loadCollections();
        await _reload(silent: true);
      } catch (e) {
        if (mounted) orgToast(context, errorText(e), error: true);
      }
    }
  }

  Future<void> _open(SavedItem item) async {
    if (!item.isAccessible || item.content == null) return;
    final c = item.content!;
    String s(String key) => (c[key] ?? '').toString();
    try {
      switch (item.type) {
        case SavedItemType.file:
          final url = s('fileUrl');
          if (url.isEmpty) return;
          if (s('fileType') == 'image') {
            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ImageViewerScreen(url: url)));
          } else {
            await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
          }
        case SavedItemType.message:
        case SavedItemType.chat:
          final convId = item.type == SavedItemType.chat
              ? (s('conversationId').isNotEmpty ? s('conversationId') : item.itemId)
              : s('conversationId');
          if (convId.isEmpty) return;
          final conv = await ChatRepository.instance.conversationById(convId, CurrentUser.id);
          if (conv == null) {
            if (mounted) orgToast(context, 'This conversation is no longer available.', error: true);
            return;
          }
          if (!mounted) return;
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ChatRoomScreen(
                conversation: conv,
                currentUserId: CurrentUser.id,
                currentUserName: CurrentUser.name,
                initialMessageId: item.type == SavedItemType.message ? item.itemId : null,
              ),
            ),
          );
        case SavedItemType.document:
        case SavedItemType.resource:
          final communityId = s('communityId');
          if (communityId.isNotEmpty) {
            final detail = await CommunityRepository.instance.detail(communityId);
            CommunityPost? post;
            try {
              post = await CommunityRepository.instance.getPost(item.itemId);
            } catch (_) {}
            post ??= _postFromSaved(item);
            if (!mounted) return;
            if (post != null) {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PostCommentsScreen(
                    post: post!,
                    myId: CurrentUser.id,
                    role: detail.role,
                    onCountChanged: (_) {},
                  ),
                ),
              );
            } else {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CommunityDetailScreen(
                    communityId: communityId,
                    initialName: detail.name,
                    initialRole: detail.role,
                  ),
                ),
              );
            }
          } else if (s('fileUrl').isNotEmpty) {
            await launchUrl(Uri.parse(s('fileUrl')), mode: LaunchMode.externalApplication);
          }
      }
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    }
  }

  CommunityPost? _postFromSaved(SavedItem item) {
    final c = item.content;
    if (c == null) return null;
    try {
      return CommunityPost.fromJson({
        ...c,
        'id': item.itemId,
        'communityId': (c['communityId'] ?? '').toString(),
      });
    } catch (_) {
      return null;
    }
  }

  IconData _iconFor(SavedItemType t) {
    switch (t) {
      case SavedItemType.message:
        return Icons.chat_bubble_outline_rounded;
      case SavedItemType.file:
        return Icons.attach_file_rounded;
      case SavedItemType.chat:
        return Icons.forum_outlined;
      case SavedItemType.document:
        return Icons.description_outlined;
      case SavedItemType.resource:
        return Icons.link_rounded;
    }
  }

  String _origin(SavedItem item) {
    final c = item.content;
    if (c == null) return '';
    String name(dynamic v) => v is Map ? (v['name'] ?? '').toString() : '';
    final who = name(c['sender']).isNotEmpty ? name(c['sender']) : name(c['author']);
    final where = (c['conversationName'] ?? c['communityName'] ?? '').toString();
    return [who, where].where((e) => e.isNotEmpty).join(' · ');
  }

  String _snippet(SavedItem item) {
    final c = item.content;
    if (c == null) return '';
    return (c['content'] ?? c['description'] ?? '').toString().trim();
  }

  String _dateLabel(DateTime d) => '${d.day}/${d.month}/${d.year}';

  Widget _typeChips() {
    Widget chip(String label, bool selected, VoidCallback onTap) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? orgTeal.withAlpha(36) : orgCard,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: selected ? orgTeal : orgBorder),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? orgTeal : orgMuted,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          chip('All', _type == null, () => _setType(null)),
          for (final t in SavedItemType.values) chip(t.label, _type == t, () => _setType(t)),
        ],
      ),
    );
  }

  Widget _collectionChips() {
    Widget chip({
      required Widget leading,
      required String label,
      required bool selected,
      required VoidCallback onTap,
      VoidCallback? onLongPress,
    }) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: selected ? orgAccent.withAlpha(70) : orgCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? orgAccent : orgBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                leading,
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? Colors.white : orgMuted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          chip(
            leading: const Icon(Icons.folder_open_rounded, size: 15, color: orgMuted),
            label: 'All collections',
            selected: _collectionId == null,
            onTap: () => _setCollection(null),
          ),
          for (final c in _collections)
            chip(
              leading: Icon(Icons.folder_rounded, size: 15, color: parseHexColor(c.color) ?? orgTeal),
              label: '${c.name} (${c.itemCount})',
              selected: _collectionId == c.id,
              onTap: () => _setCollection(c.id),
              onLongPress: () => _collectionActions(c),
            ),
          chip(
            leading: const Icon(Icons.add_rounded, size: 15, color: orgTeal),
            label: 'New',
            selected: false,
            onTap: _createCollection,
          ),
        ],
      ),
    );
  }

  Widget _card(SavedItem item) {
    final accessible = item.isAccessible && item.content != null;
    final origin = _origin(item);
    final snippet = _snippet(item);
    final color = parseHexColor(item.collection?.color) ?? orgTeal;
    final title = accessible
        ? (item.title.isNotEmpty ? item.title : item.type.label)
        : 'Content no longer available or deleted';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: orgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: orgBorder),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: accessible ? () => _open(item) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: (accessible ? orgTeal : orgMuted).withAlpha(30),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  accessible ? _iconFor(item.type) : Icons.link_off_rounded,
                  color: accessible ? orgTeal : orgMuted,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: accessible ? Colors.white : orgMuted,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        fontStyle: accessible ? FontStyle.normal : FontStyle.italic,
                      ),
                    ),
                    if (accessible && origin.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        origin,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: orgMuted, fontSize: 12),
                      ),
                    ],
                    if (accessible && snippet.isNotEmpty && snippet != item.title) ...[
                      const SizedBox(height: 6),
                      Text(
                        snippet,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13, height: 1.35),
                      ),
                    ],
                    if (item.note != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: orgField,
                          borderRadius: BorderRadius.circular(10),
                          border: Border(left: BorderSide(color: orgTeal.withAlpha(170), width: 3)),
                        ),
                        child: Text(
                          item.note!,
                          style: const TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.35),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          item.type.label,
                          style: const TextStyle(color: orgMuted, fontSize: 11.5, fontWeight: FontWeight.w600),
                        ),
                        if (item.collection != null)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.folder_rounded, size: 12, color: color),
                              const SizedBox(width: 4),
                              Text(item.collection!.name, style: TextStyle(color: color, fontSize: 11.5)),
                            ],
                          ),
                        if (item.createdAt != null)
                          Text(
                            _dateLabel(item.createdAt!),
                            style: const TextStyle(color: orgMuted, fontSize: 11.5),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                color: orgCard,
                icon: const Icon(Icons.more_vert, color: orgMuted, size: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                onSelected: (v) {
                  if (v == 'note') _editNote(item);
                  if (v == 'move') _moveItem(item);
                  if (v == 'remove') _removeItem(item);
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'note',
                    child: Text(
                      item.note == null ? 'Add note' : 'Edit note',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'move',
                    child: Text('Move to collection', style: TextStyle(color: Colors.white)),
                  ),
                  const PopupMenuItem(
                    value: 'remove',
                    child: Text('Remove', style: TextStyle(color: Colors.redAccent)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty() {
    final filtered = _type != null || _collectionId != null || _search.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 60),
      child: Column(
        children: [
          const Icon(Icons.bookmark_border_rounded, size: 48, color: orgMuted),
          const SizedBox(height: 12),
          Text(
            filtered ? 'Nothing matches your filters' : 'No saved items yet',
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            filtered ? 'Try a different search, type or collection.' : 'Long-press a chat message, or tap the bookmark on a community post, to save it here.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: orgMuted, fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(child: CircularProgressIndicator(color: orgTeal)),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 50, horizontal: 24),
        child: Column(
          children: [
            const Icon(Icons.cloud_off_rounded, size: 44, color: orgMuted),
            const SizedBox(height: 10),
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: orgMuted)),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _reload,
              style: OutlinedButton.styleFrom(side: const BorderSide(color: orgBorder)),
              child: const Text('Retry', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }
    if (_items.isEmpty) return _empty();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          for (final item in _items) _card(item),
          if (_loadingMore)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: orgTeal),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: orgBg,
      appBar: AppBar(
        backgroundColor: orgBg,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text('Saved items', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      body: RefreshIndicator(
        color: orgTeal,
        backgroundColor: orgCard,
        onRefresh: _refreshAll,
        child: ListView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: TextField(
                controller: _searchCtrl,
                onChanged: _onSearchChanged,
                style: const TextStyle(color: Colors.white),
                decoration: orgInputDecoration('Search saved items', hint: 'Search notes and content').copyWith(
                  prefixIcon: const Icon(Icons.search_rounded, color: orgMuted),
                ),
              ),
            ),
            _typeChips(),
            const SizedBox(height: 10),
            _collectionChips(),
            const SizedBox(height: 14),
            _body(),
          ],
        ),
      ),
    );
  }
}

class _NoteDialog extends StatefulWidget {
  const _NoteDialog({required this.initial});
  final String initial;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late final TextEditingController _ctrl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: orgCard,
      title: const Text('Personal note', style: TextStyle(color: Colors.white)),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        minLines: 2,
        maxLines: 5,
        style: const TextStyle(color: Colors.white),
        decoration: orgInputDecoration('Note', hint: 'Why did you save this?'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(context, _ctrl.text),
          child: const Text('Save', style: TextStyle(color: orgTeal)),
        ),
      ],
    );
  }
}

class _CollectionInput {
  final String name;
  final String? description;
  final String? color;
  const _CollectionInput(this.name, this.description, this.color);
}

class _CollectionDialog extends StatefulWidget {
  const _CollectionDialog({
    required this.title,
    required this.action,
    required this.palette,
    this.initialName = '',
    this.initialDescription = '',
    this.initialColor,
  });

  final String title;
  final String action;
  final List<Color> palette;
  final String initialName;
  final String initialDescription;
  final String? initialColor;

  @override
  State<_CollectionDialog> createState() => _CollectionDialogState();
}

class _CollectionDialogState extends State<_CollectionDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.initialName);
  late final TextEditingController _desc = TextEditingController(text: widget.initialDescription);
  late Color? _color = parseHexColor(widget.initialColor);
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty || name.length > 100) {
      setState(() => _error = 'Name must be 1 to 100 characters.');
      return;
    }
    final desc = _desc.text.trim();
    if (desc.length > 500) {
      setState(() => _error = 'Description can be 500 characters at most.');
      return;
    }
    Navigator.pop(
      context,
      _CollectionInput(name, desc.isEmpty ? null : desc, _color == null ? null : toHexColor(_color!)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: orgCard,
      title: Text(widget.title, style: const TextStyle(color: Colors.white)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              maxLength: 100,
              textCapitalization: TextCapitalization.words,
              style: const TextStyle(color: Colors.white),
              decoration: orgInputDecoration('Name').copyWith(counterText: ''),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _desc,
              minLines: 2,
              maxLines: 4,
              style: const TextStyle(color: Colors.white),
              decoration: orgInputDecoration('Description (optional)'),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final c in widget.palette)
                  GestureDetector(
                    onTap: () => setState(() => _color = _color == c ? null : c),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _color == c ? Colors.white : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: _color == c ? const Icon(Icons.check_rounded, size: 16, color: Colors.white) : null,
                    ),
                  ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: _submit,
          child: Text(widget.action, style: const TextStyle(color: orgTeal)),
        ),
      ],
    );
  }
}