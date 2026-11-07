import 'package:flutter/material.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/screens/organization_screen/organization_widgets.dart';
import 'github_widgets.dart';

class GithubPagedList<T> extends StatefulWidget {
  const GithubPagedList({
    super.key,
    required this.fetch,
    required this.itemBuilder,
    required this.emptyText,
    this.pageSize = 20,
    this.bottomPadding = 24,
  });

  final Future<List<T>> Function(int page, int perPage) fetch;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final String emptyText;
  final int pageSize;
  final double bottomPadding;

  @override
  State<GithubPagedList<T>> createState() => GithubPagedListState<T>();
}

class GithubPagedListState<T> extends State<GithubPagedList<T>> {
  final _scroll = ScrollController();
  List<T> _items = [];
  int _page = 1;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _token = 0;

  List<T> get items => _items;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    reload();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 240) _loadMore();
  }

  Future<void> reload({bool silent = false}) async {
    final token = ++_token;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final list = await widget.fetch(1, widget.pageSize);
      if (!mounted || token != _token) return;
      setState(() {
        _items = list;
        _page = 1;
        _hasMore = list.length >= widget.pageSize;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _loading = false;
        if (!silent || _items.isEmpty) _error = errorText(e);
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    final token = _token;
    setState(() => _loadingMore = true);
    try {
      final list = await widget.fetch(_page + 1, widget.pageSize);
      if (!mounted || token != _token) return;
      setState(() {
        _items = [..._items, ...list];
        _page += 1;
        _hasMore = list.length >= widget.pageSize;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() => _loadingMore = false);
      orgToast(context, errorText(e), error: true);
    }
  }

  void updateWhere(bool Function(T item) test, T Function(T item) update) {
    setState(() => _items = [for (final item in _items) test(item) ? update(item) : item]);
  }

  void removeWhere(bool Function(T item) test) {
    setState(() => _items = _items.where((item) => !test(item)).toList());
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: orgTeal));
    if (_error != null) {
      return GithubMessageView(
        icon: Icons.error_outline_rounded,
        message: _error!,
        actionLabel: 'Retry',
        onAction: reload,
      );
    }
    return RefreshIndicator(
      color: orgTeal,
      backgroundColor: orgCard,
      onRefresh: () => reload(silent: true),
      child: _items.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 80),
                Center(child: Text(widget.emptyText, style: const TextStyle(color: orgMuted))),
              ],
            )
          : ListView.separated(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(16, 12, 16, widget.bottomPadding),
              itemCount: _items.length + (_loadingMore ? 1 : 0),
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                if (index >= _items.length) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: orgTeal),
                      ),
                    ),
                  );
                }
                return widget.itemBuilder(context, _items[index]);
              },
            ),
    );
  }
}