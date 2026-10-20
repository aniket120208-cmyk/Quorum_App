import 'dart:async';
import 'package:flutter/material.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/chat_repository.dart';
import 'package:quorum_app/models/chat_models.dart';
import 'chat_widgets.dart';

class UserPickerScreen extends StatefulWidget {
  const UserPickerScreen({
    super.key,
    required this.currentUserId,
    this.multi = false,
    this.title,
    this.excludeIds = const {},
  });

  final String currentUserId;
  final bool multi;
  final String? title;
  final Set<String> excludeIds;

  @override
  State<UserPickerScreen> createState() => _UserPickerScreenState();
}

class _UserPickerScreenState extends State<UserPickerScreen> {
  static const int _maxSelected = 99;
  final _ctrl = TextEditingController();
  Timer? _debounce;
  List<ChatUser> _results = [];
  final Map<String, ChatUser> _selected = {};
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    final q = text.trim();
    if (q.length < 2) {
      setState(() {
        _results = [];
        _error = null;
        _loading = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(q));
  }

  Future<void> _search(String q) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final users = await ChatRepository.instance.searchUsers(q);
      if (!mounted || _ctrl.text.trim() != q) return;
      setState(() {
        _results = users
            .where((u) =>
                u.id != widget.currentUserId &&
                !widget.excludeIds.contains(u.id))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = errorText(e);
      });
    }
  }

  void _tap(ChatUser u) {
    if (!widget.multi) {
      Navigator.pop(context, [u]);
      return;
    }
    if (!_selected.containsKey(u.id) && _selected.length >= _maxSelected) {
      showErrorSnack(context, 'You can select up to $_maxSelected people');
      return;
    }
    setState(() {
      if (_selected.containsKey(u.id)) {
        _selected.remove(u.id);
      } else {
        _selected[u.id] = u;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.title ?? (widget.multi ? 'New group' : 'New chat');
    return Scaffold(
      backgroundColor: const Color(0xFF0F101A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F101A),
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: Text(
          title,
          style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
        ),
        actions: [
          if (widget.multi)
            TextButton(
              onPressed: _selected.isEmpty ? null : () => Navigator.pop(context, _selected.values.toList()),
              child: Text('Next (${_selected.length})'),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              onChanged: _onChanged,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search people',
                hintStyle: const TextStyle(color: AppColors.textSecondary),
                prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
                filled: true,
                fillColor: const Color(0xFF1E293B),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: _results.length,
              itemBuilder: (context, i) {
                final u = _results[i];
                final picked = _selected.containsKey(u.id);
                final email = u.email;
                return ListTile(
                  onTap: () => _tap(u),
                  leading: ChatAvatar(
                      name: u.name, imageUrl: u.avatarUrl, radius: 20),
                  title: Text(u.name, style: const TextStyle(color: AppColors.textPrimary)),
                  subtitle: (email != null && email.isNotEmpty)
                      ? Text(email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)) : null,
                  trailing: widget.multi
                      ? Icon(
                          picked ? Icons.check_circle : Icons.radio_button_unchecked,
                          color: picked ? AppColors.primary : AppColors.textSecondary,
                        )
                      : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}