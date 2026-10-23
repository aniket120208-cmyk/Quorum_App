import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/notification_repository.dart';
import 'package:quorum_app/api/notification_router.dart';
import 'package:quorum_app/api/notification_service.dart';
import 'package:quorum_app/models/notification_models.dart';
import 'package:quorum_app/screens/notification_screen/notification_banner.dart';
import 'package:quorum_app/screens/notification_screen/notification_preferences_screen.dart';

const _bg = Color(0xFF090A10);
const _card = Color(0xFF14151F);
const _border = Color(0x1AFFFFFF);
const _muted = Color(0xFF9EA3AE);
const _accent = Color(0xFF7F77FF);

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  final _repo = NotificationRepository.instance;
  final _service = NotificationService.instance;
  final _scroll = ScrollController();
  final List<NotificationItem> _items = [];
  StreamSubscription<NotificationItem>? _sub;

  bool _unreadOnly = false;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _page = 1;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _sub = _service.incoming.listen(_onIncoming);
    _load();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 240) _loadMore();
  }

  void _onIncoming(NotificationItem n) {
    if (!mounted) return;
    setState(() => _items.insert(0, n));
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _repo.fetch(page: 1, unreadOnly: _unreadOnly);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _page = page.page;
        _hasMore = page.hasMore;
        _loading = false;
      });
      _service.setUnread(page.unreadCount);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = errorText(e);
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _repo.fetch(page: _page + 1, unreadOnly: _unreadOnly);
      if (!mounted) return;
      final known = _items.map((e) => e.id).toSet();
      setState(() {
        _items.addAll(page.items.where((e) => !known.contains(e.id)));
        _page = page.page;
        _hasMore = page.hasMore;
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _setFilter(bool unreadOnly) {
    if (_unreadOnly == unreadOnly) return;
    _unreadOnly = unreadOnly;
    _load();
  }

  Future<void> _open(NotificationItem n) async {
    if (!n.isRead) {
      final index = _items.indexWhere((e) => e.id == n.id);
      if (index != -1) {
        setState(() => _items[index] = n.copyWith(isRead: true, readAt: DateTime.now()));
      }
      unawaited(_service.markRead(n));
    }
    await NotificationRouter.openItem(n);
  }

  Future<void> _markAll() async {
    if (_service.unreadCount.value == 0 && !_items.any((e) => !e.isRead)) return;
    final previous = List<NotificationItem>.of(_items);
    setState(() {
      for (var i = 0; i < _items.length; i++) {
        _items[i] = _items[i].copyWith(isRead: true, readAt: DateTime.now());
      }
      if (_unreadOnly) _items.clear();
    });
    _service.setUnread(0);
    try {
      await _repo.markAllRead();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(previous);
      });
      await _service.refreshUnread();
      _snack(errorText(e));
    }
  }

  Future<void> _delete(NotificationItem n) async {
    final index = _items.indexWhere((e) => e.id == n.id);
    if (index == -1) return;
    setState(() => _items.removeAt(index));
    if (!n.isRead) _service.setUnread(_service.unreadCount.value - 1);
    try {
      await _repo.delete(n.id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _items.insert(min(index, _items.length), n));
      await _service.refreshUnread();
      _snack(errorText(e));
    }
  }

  void _snack(String m) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text('Notifications', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: 'Mark all as read',
            icon: const Icon(Icons.done_all_rounded),
            onPressed: _markAll,
          ),
          IconButton(
            tooltip: 'Preferences',
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NotificationPreferencesScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                _chip('All', !_unreadOnly, () => _setFilter(false)),
                const SizedBox(width: 8),
                _chip('Unread', _unreadOnly, () => _setFilter(true)),
              ],
            ),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _accent : _card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? _accent : _border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : _muted,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _accent));
    }
    if (_error != null && _items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: _muted, size: 44),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: _muted)),
              const SizedBox(height: 12),
              TextButton(onPressed: _load, child: const Text('Retry', style: TextStyle(color: _accent))),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return RefreshIndicator(
        color: _accent,
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            Icon(Icons.notifications_none_rounded, color: _muted, size: 48),
            SizedBox(height: 12),
            Center(child: Text("You're all caught up", style: TextStyle(color: _muted, fontSize: 14))),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: _accent,
      onRefresh: _load,
      child: ListView.separated(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: _items.length + (_loadingMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          if (i >= _items.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator(color: _accent, strokeWidth: 2)),
            );
          }
          final n = _items[i];
          return Dismissible(
            key: ValueKey(n.id),
            direction: DismissDirection.endToStart,
            onDismissed: (_) => _delete(n),
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
            ),
            child: _tile(n),
          );
        },
      ),
    );
  }

  Widget _tile(NotificationItem n) {
    final avatar = n.actor?.avatar;
    return Material(
      color: n.isRead ? _card : const Color(0xFF1A1B2E),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _open(n),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: n.isRead ? _border : _accent.withValues(alpha: 0.35)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: const Color(0xFF2A2C4A),
                backgroundImage: avatar != null ? NetworkImage(avatar) : null,
                child: avatar == null ? Icon(notificationIcon(n.type), color: _accent, size: 20) : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            n.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: n.isRead ? FontWeight.w500 : FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(timeAgo(n.createdAt), style: const TextStyle(color: _muted, fontSize: 11.5)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      n.body,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _muted, fontSize: 13, height: 1.3),
                    ),
                  ],
                ),
              ),
              if (!n.isRead)
                Container(
                  margin: const EdgeInsets.only(left: 8, top: 4),
                  width: 9,
                  height: 9,
                  decoration: const BoxDecoration(color: _accent, shape: BoxShape.circle),
                ),
            ],
          ),
        ),
      ),
    );
  }
}