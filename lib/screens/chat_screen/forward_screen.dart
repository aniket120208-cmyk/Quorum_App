import 'package:flutter/material.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/chat_repository.dart';
import 'package:quorum_app/models/chat_models.dart';
import 'chat_widgets.dart';

class ForwardScreen extends StatefulWidget {
  const ForwardScreen({super.key, required this.currentUserId, required this.messageCount});

  final String currentUserId;
  final int messageCount;

  @override
  State<ForwardScreen> createState() => _ForwardScreenState();
}

class _ForwardScreenState extends State<ForwardScreen> {
  static const Color darkBg = Color(0xFF0F101A);

  List<Conversation> _all = [];
  final List<String> _selected = [];
  final _search = TextEditingController();
  bool _loading = true;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await ChatRepository.instance.conversations(widget.currentUserId);
      if (!mounted) return;
      setState(() {
        _all = list..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
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

  void _toggle(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final visible = _all
        .where((c) => q.isEmpty || c.titleFor(widget.currentUserId).toLowerCase().contains(q))
        .toList();
    return Scaffold(
      backgroundColor: darkBg,
      appBar: AppBar(
        backgroundColor: darkBg,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: Text(
          widget.messageCount == 1 ? 'Forward message' : 'Forward ${widget.messageCount} messages',
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: (v) => setState(() => _query = v),
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search chats',
                hintStyle: const TextStyle(color: AppColors.textSecondary),
                prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary, size: 20),
                filled: true,
                fillColor: AppColors.surface,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.surfaceBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.surfaceBorder),
                ),
              ),
            ),
          ),
          Expanded(child: _body(visible)),
          SafeArea(
            top: false,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: AppColors.surfaceBorder)),
              ),
              child: FilledButton.icon(
                onPressed: _selected.isEmpty ? null : () => Navigator.pop(context, List<String>.of(_selected)),
                icon: const Icon(Icons.send_rounded, size: 18),
                label: Text(_selected.isEmpty ? 'Select chats' : 'Forward to ${_selected.length}'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(List<Conversation> visible) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (visible.isEmpty) {
      return const Center(child: Text('No chats found', style: TextStyle(color: AppColors.textSecondary)));
    }
    return ListView.builder(
      itemCount: visible.length,
      itemBuilder: (_, i) {
        final c = visible[i];
        final title = c.titleFor(widget.currentUserId);
        final selected = _selected.contains(c.id);
        return ListTile(
          onTap: () => _toggle(c.id),
          leading: ChatAvatar(
            name: title,
            isGroup: c.isGroup,
            imageUrl: c.isGroup ? c.avatar : null,
            radius: 20,
          ),
          title: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            c.isGroup ? 'Group' : 'Direct message',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          trailing: Icon(
            selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
            color: selected ? AppColors.primary : AppColors.textMuted,
          ),
        );
      },
    );
  }
}