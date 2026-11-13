import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/recording_repository.dart';
import 'package:quorum_app/models/recording_models.dart';
import 'package:quorum_app/screens/organization_screen/organization_widgets.dart';
import 'markdown_view.dart';
import 'recording_widgets.dart';

class RecordingDetailScreen extends StatefulWidget {
  const RecordingDetailScreen({super.key, required this.recording, this.canDelete = false});
  final MeetingRecording recording;
  final bool canDelete;

  @override
  State<RecordingDetailScreen> createState() => _RecordingDetailScreenState();
}

class _RecordingDetailScreenState extends State<RecordingDetailScreen> {
  final _repo = RecordingRepository.instance;
  late MeetingRecording _recording = widget.recording;
  VideoPlayerController? _player;
  bool _loading = true;
  bool _playerLoading = false;
  String? _error;
  String? _playerError;
  bool _summarizing = false;
  String? _summaryError;
  bool _refreshedOnce = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _player?.removeListener(_onPlayerTick);
    _player?.dispose();
    super.dispose();
  }

  void _onPlayerTick() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _repo.get(widget.recording.id);
      if (!mounted) return;
      setState(() {
        _recording = r;
        _loading = false;
      });
      if (r.isPlayable && r.playbackUrl != null) await _initPlayer(r.playbackUrl!);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = errorText(e);
      });
    }
  }

  Future<void> _initPlayer(String url) async {
    final old = _player;
    old?.removeListener(_onPlayerTick);
    setState(() {
      _player = null;
      _playerLoading = true;
      _playerError = null;
    });
    await old?.dispose();
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      controller.addListener(_onPlayerTick);
      setState(() {
        _player = controller;
        _playerLoading = false;
      });
    } catch (_) {
      await controller.dispose();
      if (!mounted) return;
      if (!_refreshedOnce) {
        _refreshedOnce = true;
        await _refreshPlaybackUrl();
        return;
      }
      setState(() {
        _playerLoading = false;
        _playerError = 'This recording could not be played.';
      });
    }
  }

  Future<void> _refreshPlaybackUrl() async {
    try {
      final r = await _repo.get(_recording.id);
      if (!mounted) return;
      setState(() => _recording = r);
      if (r.playbackUrl != null) {
        await _initPlayer(r.playbackUrl!);
        return;
      }
      setState(() {
        _playerLoading = false;
        _playerError = 'This recording could not be played.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _playerLoading = false;
        _playerError = errorText(e);
      });
    }
  }

  Future<void> _summarize({bool regenerate = false}) async {
    if (_summarizing) return;
    setState(() {
      _summarizing = true;
      _summaryError = null;
    });
    try {
      final result = await _repo.summarize(_recording.id, regenerate: regenerate);
      if (!mounted) return;
      setState(() => _recording = _recording.copyWith(summary: result.summary));
      if (regenerate || !result.isCached) orgToast(context, 'AI summary ready');
    } catch (e) {
      if (mounted) setState(() => _summaryError = errorText(e));
    } finally {
      if (mounted) setState(() => _summarizing = false);
    }
  }

  Future<void> _copySummary() async {
    final text = _recording.summary;
    if (text == null) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) orgToast(context, 'Summary copied');
  }

  Future<void> _delete() async {
    final ok = await orgConfirm(
      context,
      title: 'Delete recording?',
      body: 'The video, thumbnail and transcript will be permanently removed for everyone.',
      action: 'Delete',
    );
    if (!ok) return;
    try {
      await _repo.delete(_recording.id);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _recording;
    return Scaffold(
      backgroundColor: orgBg,
      appBar: AppBar(
        backgroundColor: orgBg,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Text(
          r.meetingTitle ?? 'Recording',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        actions: [
          if (widget.canDelete)
            IconButton(
              tooltip: 'Delete recording',
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: orgTeal))
          : _error != null
              ? _errorView()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                  children: [
                    _playerArea(r),
                    const SizedBox(height: 14),
                    _meta(r),
                    const SizedBox(height: 18),
                    _summarySection(r),
                  ],
                ),
    );
  }

  Widget _playerArea(MeetingRecording r) {
    final player = _player;
    Widget child;
    if (!r.isPlayable) {
      child = _playerMessage(
        r.status == RecordingStatus.failed ? Icons.error_outline_rounded : Icons.hourglass_top_rounded,
        r.status == RecordingStatus.failed
            ? 'This recording failed to process.'
            : r.status == RecordingStatus.recording
                ? 'This meeting is still being recorded.'
                : 'Processing video... This can take a few minutes.',
        action: r.status == RecordingStatus.failed ? null : ('Refresh', _load),
      );
    } else if (_playerLoading) {
      child = const Center(child: CircularProgressIndicator(color: orgTeal));
    } else if (_playerError != null) {
      child = _playerMessage(Icons.error_outline_rounded, _playerError!, action: ('Try again', _refreshPlaybackUrl));
    } else if (player != null && player.value.isInitialized) {
      child = Stack(
        alignment: Alignment.center,
        children: [
          VideoPlayer(player),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => player.value.isPlaying ? player.pause() : player.play(),
            child: AnimatedOpacity(
              opacity: player.value.isPlaying ? 0 : 1,
              duration: const Duration(milliseconds: 200),
              child: Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 34),
              ),
            ),
          ),
          Positioned(
            left: 8,
            right: 8,
            bottom: 4,
            child: Row(
              children: [
                Text(
                  recDuration(player.value.position.inSeconds),
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: VideoProgressIndicator(
                    player,
                    allowScrubbing: true,
                    colors: const VideoProgressColors(
                      playedColor: orgTeal,
                      bufferedColor: Colors.white24,
                      backgroundColor: Colors.white12,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  recDuration(player.value.duration.inSeconds),
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      );
    } else {
      child = _playerMessage(Icons.play_disabled_rounded, 'Video is not available.', action: ('Refresh', _load));
    }
    final aspect = player != null && player.value.isInitialized && player.value.aspectRatio > 0
        ? player.value.aspectRatio
        : 16 / 9;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: aspect,
        child: ColoredBox(color: Colors.black, child: child),
      ),
    );
  }

  Widget _playerMessage(IconData icon, String text, {(String, VoidCallback)? action}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: orgMuted, size: 34),
            const SizedBox(height: 10),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(color: orgMuted, fontSize: 13)),
            if (action != null)
              TextButton(
                onPressed: action.$2,
                child: Text(action.$1, style: const TextStyle(color: orgTeal, fontWeight: FontWeight.w700)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _meta(MeetingRecording r) {
    final expiry = recExpiry(r.expiresAt);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: orgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: orgBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              RecStatusChip(status: r.status),
              const Spacer(),
              if (expiry.isNotEmpty) Text(expiry, style: const TextStyle(color: orgMuted, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 12),
          _metaRow(Icons.event_rounded, recDate(r.startedAt)),
          _metaRow(Icons.timer_outlined, recDuration(r.durationSeconds)),
          if (r.fileSizeBytes != null) _metaRow(Icons.storage_rounded, recSize(r.fileSizeBytes)),
          if (r.recordedBy != null) _metaRow(Icons.fiber_manual_record_rounded, 'Recorded by ${r.recordedBy!.name}'),
        ],
      ),
    );
  }

  Widget _metaRow(IconData icon, String text) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: orgMuted),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 13.5))),
        ],
      ),
    );
  }

  Widget _summarySection(MeetingRecording r) {
    final summary = r.summary;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: orgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: orgBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_rounded, color: Color(0xFFA78BFA), size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'AI summary',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
              if (summary != null) ...[
                IconButton(
                  tooltip: 'Copy',
                  visualDensity: VisualDensity.compact,
                  onPressed: _copySummary,
                  icon: const Icon(Icons.copy_rounded, color: orgMuted, size: 18),
                ),
                IconButton(
                  tooltip: 'Regenerate',
                  visualDensity: VisualDensity.compact,
                  onPressed: _summarizing || !r.isPlayable ? null : () => _summarize(regenerate: true),
                  icon: const Icon(Icons.refresh_rounded, color: orgMuted, size: 20),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          if (_summarizing)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(color: orgTeal, strokeWidth: 2.5),
                    SizedBox(height: 12),
                    Text('Summarizing the meeting...', style: TextStyle(color: orgMuted, fontSize: 13)),
                  ],
                ),
              ),
            )
          else if (summary != null)
            MarkdownView(data: summary)
          else ...[
            Text(
              r.isPlayable
                  ? 'Get an executive summary, key topics, decisions and action items from this meeting.'
                  : 'The summary will be available once the recording has finished processing.',
              style: const TextStyle(color: orgMuted, fontSize: 13.5, height: 1.4),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: FilledButton.icon(
                onPressed: r.isPlayable ? () => _summarize() : null,
                icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                label: const Text('Generate AI Summary', style: TextStyle(fontWeight: FontWeight.w700)),
                style: FilledButton.styleFrom(
                  backgroundColor: orgAccent,
                  disabledBackgroundColor: orgField,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
          if (_summaryError != null) ...[
            const SizedBox(height: 10),
            Text(_summaryError!, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12.5)),
          ],
        ],
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
              onPressed: _load,
              child: const Text('Retry', style: TextStyle(color: orgTeal, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}