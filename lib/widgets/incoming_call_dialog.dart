import 'dart:async';
import 'package:flutter/material.dart';
import 'package:quorum_app/app_navigator.dart';

class IncomingCall {
  IncomingCall._();
  static bool _showing = false;

  static Future<void> show({
    required String hostName,
    required String title,
    required VoidCallback onAccept,
  }) async {
    final ctx = appNavigatorKey.currentState?.overlay?.context;
    if (ctx == null || _showing) return;
    _showing = true;
    var open = true;
    final timer = Timer(const Duration(seconds: 60), () {
      if (open) appNavigatorKey.currentState?.pop(false);
    });
    final accepted = await showDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => _IncomingCallDialog(hostName: hostName, title: title),
    );
    open = false;
    timer.cancel();
    _showing = false;
    if (accepted == true) onAccept();
  }
}

class _IncomingCallDialog extends StatelessWidget {
  const _IncomingCallDialog({required this.hostName, required this.title});
  final String hostName;
  final String title;

  static const Color _card = Color(0xFF14151F);
  static const Color _muted = Color(0xFF9EA3AE);
  static const Color _teal = Color(0xFF3DDCC4);
  static const Color _green = Color(0xFF22C55E);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _teal.withValues(alpha: 0.14),
                border: Border.all(color: _teal.withValues(alpha: 0.5)),
              ),
              child: const Icon(Icons.videocam_rounded, color: _teal, size: 30),
            ),
            const SizedBox(height: 16),
            const Text('Incoming call', style: TextStyle(color: _muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
              hostName,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _muted, fontSize: 13.5),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Color(0x33FFFFFF)),
                      minimumSize: const Size.fromHeight(46),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Dismiss', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(context, true),
                    icon: const Icon(Icons.videocam_rounded, size: 18),
                    label: const Text('Join', style: TextStyle(fontWeight: FontWeight.w700)),
                    style: FilledButton.styleFrom(
                      backgroundColor: _green,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(46),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}