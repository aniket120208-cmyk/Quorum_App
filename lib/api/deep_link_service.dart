import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:quorum_app/api/deep_link_router.dart';

class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService instance = DeepLinkService._();

  final AppLinks _links = AppLinks();
  StreamSubscription<Uri>? _sub;
  Uri? _pending;
  bool _started = false;
  bool _ready = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      final initial = await _links.getInitialLink();
      if (initial != null) _enqueue(initial);
    } catch (_) {}
    _sub = _links.uriLinkStream.listen(_enqueue, onError: (_) {});
  }

  void markReady() {
    _ready = true;
    _flush();
  }

  void markNotReady() {
    _ready = false;
  }

  void _enqueue(Uri uri) {
    if (!DeepLinkRouter.isQuorumUri(uri)) return;
    _pending = uri;
    if (_ready) _flush();
  }

  Future<void> _flush() async {
    final uri = _pending;
    if (uri == null) return;
    _pending = null;
    await Future<void>.delayed(const Duration(milliseconds: 350));
    await DeepLinkRouter.open(uri);
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    _started = false;
  }
}