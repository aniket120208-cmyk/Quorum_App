import 'dart:async';
import 'package:flutter/material.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/current_user.dart';
import 'package:quorum_app/api/recording_repository.dart';
import 'package:quorum_app/api/recording_uploader.dart';
import 'package:quorum_app/models/recording_models.dart';
import 'package:quorum_app/screens/organization_screen/organization_widgets.dart';
import 'recording_detail_screen.dart';
import 'recording_widgets.dart';

class MeetingRecordingsScreen extends StatefulWidget {
  const MeetingRecordingsScreen({super.key, required this.meetingCode, this.title, this.isHost = false});
  final String meetingCode;
  final String? title;
  final bool isHost;

  @override
  State<MeetingRecordingsScreen> createState() => _MeetingRecordingsScreenState();
}

class _MeetingRecordingsScreenState extends State<MeetingRecordingsScreen> {
  final _repo = RecordingRepository.instance;
  final _uploader = RecordingUploader.instance;
  final _scroll = ScrollController();
  List<MeetingRecording> _items = [];
  int _page = 1;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  Timer? _poller;
  StreamSubscription<RecordingJob>? _finishedSub;

  @override
  void initState() {
    super.initState();
    _load();
    _scroll.addListener(_onScroll);
    _finishedSub = _uploader.finished.listen((job) {
      if (job.meetingCode == widget.meetingCode && job.stage == RecordingJobStage.done) _load(silent: true);
    });
    _poller = Timer.periodic(const Duration(seconds: 8), (_) {
      if (_items.any((r) => r.status == RecordingStatus.processing || r.status == RecordingStatus.recording)) {
        _load(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _poller?.cancel();
    _finishedSub?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) _loadMore();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final page = await _repo.list(widget.meetingCode, page: 1);
      if (!mounted) return;
      setState(() {
        _items = page.items;
        _page = page.page;
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
    if (_loadingMore || !_hasMore || _loading) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _repo.list(widget.meetingCode, page: _page + 1);
      if (!mounted) return;
      setState(() {
        final known = _items.map((r) => r.id).toSet();
        _items = [..._items, ...page.items.where((r) => !known.contains(r.id))];
        _page = page.page;
        _hasMore = page.hasMore;
      });
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  bool _canDelete(MeetingRecording r) => widget.isHost || r.recordedBy?.id == CurrentUser.id;

  Future<void> _delete(MeetingRecording r) async {
    final ok = await orgConfirm(
      context,
      title: 'Delete recording?',
      body: 'The video, thumbnail and transcript will be permanently removed for everyone.',
      action: 'Delete',
    );
    if (!ok) return;
    try {
      await _repo.delete(r.id);
      if (!mounted) return;
      setState(() => _items = _items.where((x) => x.id != r.id).toList());
      orgToast(context, 'Recording deleted');
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    }
  }

  Future<void> _open(MeetingRecording r) async {
    final deleted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => RecordingDetailScreen(recording: r, canDelete: _canDelete(r)),
      ),
    );
    if (!mounted) return;
    if (deleted == true) {
      setState(() => _items = _items.where((x) => x.id != r.id).toList());
    } else {
      _load(silent: true);
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Recordings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            Text(
              widget.title ?? widget.meetingCode,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: orgMuted),
            ),
          ],
        ),
      ),
      body: ListenableBuilder(
        listenable: _uploader,
        builder: (context, _) {
          final jobs = _uploader.jobsFor(widget.meetingCode);
          if (_loading) return const Center(child: CircularProgressIndicator(color: orgTeal));
          if (_error != null && _items.isEmpty && jobs.isEmpty) return _errorView();
          return RefreshIndicator(
            color: orgTeal,
            backgroundColor: orgCard,
            onRefresh: () => _load(silent: true),
            child: ListView(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                for (final job in jobs)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: RecUploadCard(
                      job: job,
                      onRetry: () => _uploader.retry(job),
                      onDismiss: () => _uploader.dismiss(job),
                    ),
                  ),
                if (_items.isEmpty && jobs.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 120),
                    child: Column(
                      children: [
                        Icon(Icons.videocam_off_outlined, color: orgMuted, size: 44),
                        SizedBox(height: 12),
                        Text('No recordings for this meeting', style: TextStyle(color: orgMuted)),
                      ],
                    ),
                  ),
                for (final r in _items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _RecordingTile(
                      recording: r,
                      onTap: () => _open(r),
                      onDelete: _canDelete(r) ? () => _delete(r) : null,
                    ),
                  ),
                if (_loadingMore)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator(color: orgTeal, strokeWidth: 2)),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: orgMuted, size: 42),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: orgMuted)),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => _load(),
              child: const Text('Retry', style: TextStyle(color: orgTeal, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordingTile extends StatelessWidget {
  const _RecordingTile({required this.recording, required this.onTap, this.onDelete});
  final MeetingRecording recording;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final r = recording;
    final expiry = recExpiry(r.expiresAt);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: orgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: orgBorder),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 96,
                height: 64,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (r.thumbnailUrl != null)
                      Image.network(
                        r.thumbnailUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const _ThumbPlaceholder(),
                      )
                    else
                      const _ThumbPlaceholder(),
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(6)),
                        child: Text(
                          recDuration(r.durationSeconds),
                          style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    recDate(r.startedAt),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  if (r.recordedBy != null)
                    Text(
                      'Recorded by ${r.recordedBy!.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: orgMuted, fontSize: 12),
                    ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      RecStatusChip(status: r.status),
                      if (r.summary != null)
                        const Icon(Icons.auto_awesome_rounded, color: Color(0xFFA78BFA), size: 14),
                      if (expiry.isNotEmpty) Text(expiry, style: const TextStyle(color: orgMuted, fontSize: 11)),
                    ],
                  ),
                ],
              ),
            ),
            if (onDelete != null)
              IconButton(
                tooltip: 'Delete',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 20),
              ),
          ],
        ),
      ),
    );
  }
}

class _ThumbPlaceholder extends StatelessWidget {
  const _ThumbPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: orgField,
      child: const Icon(Icons.play_circle_outline_rounded, color: orgMuted, size: 30),
    );
  }
}