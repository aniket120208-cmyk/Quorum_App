import 'dart:async';
import 'package:flutter/material.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/whiteboard_repository.dart';
import 'package:quorum_app/models/organization_models.dart';
import 'package:quorum_app/models/whiteboard_models.dart';
import 'package:quorum_app/screens/organization_screen/organization_sheets.dart';
import 'package:quorum_app/screens/organization_screen/organization_widgets.dart';
import 'whiteboard_screen.dart';
import 'whiteboard_sheets.dart';

String whiteboardAgo(DateTime? time) {
  if (time == null) return '';
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'Updated just now';
  if (diff.inMinutes < 60) return 'Updated ${diff.inMinutes}m ago';
  if (diff.inHours < 24) return 'Updated ${diff.inHours}h ago';
  if (diff.inDays < 30) return 'Updated ${diff.inDays}d ago';
  return 'Updated ${time.day}/${time.month}/${time.year}';
}

class WhiteboardListScreen extends StatefulWidget {
  const WhiteboardListScreen({super.key, required this.organization});
  final Organization organization;

  @override
  State<WhiteboardListScreen> createState() => _WhiteboardListScreenState();
}

class _WhiteboardListScreenState extends State<WhiteboardListScreen> {
  final _repo = WhiteboardRepository.instance;
  final _searchController = TextEditingController();
  final _scroll = ScrollController();
  final List<Whiteboard> _items = [];
  Timer? _debounce;
  String _query = '';
  int _page = 1;
  int _seq = 0;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 240) _more();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (value.trim() == _query) return;
      _query = value.trim();
      setState(() => _loading = true);
      _reload();
    });
  }

  Future<void> _reload() async {
    final seq = ++_seq;
    try {
      final page = await _repo.list(widget.organization.id, page: 1, search: _query);
      if (!mounted || seq != _seq) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _page = 1;
        _hasMore = page.hasMore;
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _loading = false;
        if (_items.isEmpty) _error = errorText(e);
      });
      if (_items.isNotEmpty) orgToast(context, errorText(e), error: true);
    }
  }

  Future<void> _more() async {
    if (_loadingMore || !_hasMore || _loading) return;
    final seq = _seq;
    setState(() => _loadingMore = true);
    try {
      final page = await _repo.list(widget.organization.id, page: _page + 1, search: _query);
      if (!mounted || seq != _seq) return;
      final known = _items.map((b) => b.id).toSet();
      setState(() {
        _items.addAll(page.items.where((b) => !known.contains(b.id)));
        _page = page.page;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() => _loadingMore = false);
      orgToast(context, errorText(e), error: true);
    }
  }

  Future<void> _open(Whiteboard board) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => WhiteboardScreen(boardId: board.id, name: board.name)),
    );
    if (mounted) _reload();
  }

  Future<void> _create() async {
    final name = await showOrgSheet<String>(
      context,
      const WhiteboardNameSheet(title: 'New whiteboard', action: 'Create'),
    );
    if (name == null || !mounted) return;
    try {
      final board = await _repo.create(name: name, organizationId: widget.organization.id);
      if (!mounted) return;
      await _open(board.copyWith(name: name));
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    }
  }

  Future<void> _rename(Whiteboard board) async {
    final name = await showOrgSheet<String>(
      context,
      WhiteboardNameSheet(title: 'Rename whiteboard', action: 'Save', initialName: board.name),
    );
    if (name == null || name == board.name) return;
    try {
      await _repo.rename(board.id, name);
      if (!mounted) return;
      setState(() {
        final i = _items.indexWhere((b) => b.id == board.id);
        if (i != -1) _items[i] = _items[i].copyWith(name: name);
      });
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    }
  }

  Future<void> _delete(Whiteboard board) async {
    final ok = await orgConfirm(
      context,
      title: 'Delete whiteboard',
      body: 'Delete "${board.name}" for everyone in ${widget.organization.name}? This cannot be undone.',
      action: 'Delete',
    );
    if (!ok) return;
    try {
      await _repo.delete(board.id);
      if (!mounted) return;
      setState(() => _items.removeWhere((b) => b.id == board.id));
      orgToast(context, 'Whiteboard deleted');
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: orgBg,
      appBar: AppBar(
        backgroundColor: orgBg,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text('Whiteboards', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        backgroundColor: orgAccent,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New board', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search whiteboards',
                hintStyle: const TextStyle(color: orgMuted),
                prefixIcon: const Icon(Icons.search_rounded, color: orgMuted),
                filled: true,
                fillColor: orgField,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: orgTeal));
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: orgMuted, size: 42),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: orgMuted)),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _error = null;
                  });
                  _reload();
                },
                child: const Text('Retry', style: TextStyle(color: orgTeal, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      color: orgTeal,
      backgroundColor: orgCard,
      onRefresh: _reload,
      child: _items.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 80),
                Center(
                  child: Text(
                    _query.isEmpty ? 'No whiteboards yet' : 'No whiteboards match your search',
                    style: const TextStyle(color: orgMuted),
                  ),
                ),
              ],
            )
          : ListView.separated(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 96),
              itemCount: _items.length + (_loadingMore ? 1 : 0),
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                if (index >= _items.length) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator(color: orgTeal, strokeWidth: 2.5)),
                  );
                }
                return _tile(_items[index]);
              },
            ),
    );
  }

  Widget _tile(Whiteboard board) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _open(board),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        decoration: BoxDecoration(
          color: orgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: orgBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: const Color(0xFF16302F), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.draw_rounded, color: orgTeal, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    board.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w700),
                  ),
                  if (board.updatedAt != null)
                    Text(whiteboardAgo(board.updatedAt), style: const TextStyle(color: orgMuted, fontSize: 12)),
                ],
              ),
            ),
            PopupMenuButton<String>(
              color: orgCard,
              icon: const Icon(Icons.more_vert_rounded, color: orgMuted, size: 20),
              onSelected: (v) {
                if (v == 'rename') _rename(board);
                if (v == 'delete') _delete(board);
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'rename', child: Text('Rename', style: TextStyle(color: Colors.white))),
                PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Color(0xFFEF4444)))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}