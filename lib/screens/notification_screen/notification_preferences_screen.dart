import 'package:flutter/material.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/notification_repository.dart';
import 'package:quorum_app/models/notification_models.dart';

const _bg = Color(0xFF090A10);
const _card = Color(0xFF14151F);
const _border = Color(0x1AFFFFFF);
const _muted = Color(0xFF9EA3AE);
const _accent = Color(0xFF7F77FF);

class NotificationPreferencesScreen extends StatefulWidget {
  const NotificationPreferencesScreen({super.key});

  @override
  State<NotificationPreferencesScreen> createState() => _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState extends State<NotificationPreferencesScreen> {
  final _repo = NotificationRepository.instance;
  final Map<NotificationType, NotificationPreference> _prefs = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _repo.preferences();
      if (!mounted) return;
      setState(() {
        _prefs
          ..clear()
          ..addEntries(NotificationType.values.map((t) => MapEntry(t, NotificationPreference(type: t))))
          ..addEntries(list.map((p) => MapEntry(p.type, p)));
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

  Future<void> _update(NotificationPreference next) async {
    final previous = _prefs[next.type]!;
    setState(() => _prefs[next.type] = next);
    try {
      await _repo.updatePreference(next);
    } catch (e) {
      if (!mounted) return;
      setState(() => _prefs[next.type] = previous);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(errorText(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text('Preferences', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: _accent));
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: _muted)),
            TextButton(onPressed: _load, child: const Text('Retry', style: TextStyle(color: _accent))),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        for (final t in NotificationType.values) ...[
          _group(_prefs[t]!),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _group(NotificationPreference p) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(p.type.label, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          _row('In-app', p.inApp, (v) => _update(p.copyWith(inApp: v))),
          _row('Push', p.push, (v) => _update(p.copyWith(push: v))),
          _row('Email', p.email, (v) => _update(p.copyWith(email: v))),
        ],
      ),
    );
  }

  Widget _row(String label, bool value, ValueChanged<bool> onChanged) {
    return Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(color: _muted, fontSize: 14))),
        Switch(
          value: value,
          onChanged: onChanged,
          thumbColor: const WidgetStatePropertyAll(Colors.white),
          activeTrackColor: _accent,
        ),
      ],
    );
  }
}