import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:quorum_app/models/chat_models.dart';
import 'chat_widgets.dart';

String formatVoiceDuration(int seconds) {
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

List<double> resampleWaveform(List<double> samples, int bars) {
  if (samples.isEmpty) return List<double>.filled(bars, 0.12);
  if (samples.length <= bars) return samples;
  final out = <double>[];
  final step = samples.length / bars;
  for (var i = 0; i < bars; i++) {
    final from = (i * step).floor();
    final to = ((i + 1) * step).ceil().clamp(from + 1, samples.length);
    var sum = 0.0;
    for (var j = from; j < to; j++) {
      sum += samples[j];
    }
    out.add(sum / (to - from));
  }
  return out;
}

class WaveformBars extends StatelessWidget {
  const WaveformBars({
    super.key,
    required this.samples,
    required this.activeColor,
    required this.inactiveColor,
    this.progress = 0,
    this.bars = 34,
    this.height = 28,
  });

  final List<double> samples;
  final Color activeColor;
  final Color inactiveColor;
  final double progress;
  final int bars;
  final double height;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(double.infinity, height),
      painter: _WaveformPainter(
        samples: resampleWaveform(samples, bars),
        activeColor: activeColor,
        inactiveColor: inactiveColor,
        progress: progress.clamp(0.0, 1.0),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.samples,
    required this.activeColor,
    required this.inactiveColor,
    required this.progress,
  });

  final List<double> samples;
  final Color activeColor;
  final Color inactiveColor;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;
    const gap = 2.0;
    final barWidth = ((size.width - gap * (samples.length - 1)) / samples.length).clamp(1.5, 4.0);
    final total = barWidth * samples.length + gap * (samples.length - 1);
    final startX = (size.width - total) / 2;
    final paint = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < samples.length; i++) {
      final h = (samples[i].clamp(0.0, 1.0) * size.height).clamp(3.0, size.height);
      final x = startX + i * (barWidth + gap);
      final played = (i + 0.5) / samples.length <= progress;
      paint.color = played ? activeColor : inactiveColor;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, (size.height - h) / 2, barWidth, h),
          Radius.circular(barWidth / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) =>
      old.progress != progress || old.samples != samples || old.activeColor != activeColor;
}

class VoiceMessageView extends StatefulWidget {
  const VoiceMessageView({super.key, required this.message, required this.isMe});

  final ChatMessage message;
  final bool isMe;

  @override
  State<VoiceMessageView> createState() => _VoiceMessageViewState();
}

class _VoiceMessageViewState extends State<VoiceMessageView> {
  static _VoiceMessageViewState? _active;

  AudioPlayer? _player;
  final List<StreamSubscription<dynamic>> _subs = [];
  bool _playing = false;
  bool _loading = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  int get _declaredSeconds => widget.message.audioDuration ?? 0;

  Duration get _total {
    if (_duration > Duration.zero) return _duration;
    return Duration(seconds: _declaredSeconds);
  }

  double get _progress {
    final total = _total.inMilliseconds;
    if (total <= 0) return 0;
    return (_position.inMilliseconds / total).clamp(0.0, 1.0);
  }

  Source? get _source {
    final url = widget.message.fileUrl;
    if (url != null && url.isNotEmpty) return UrlSource(url);
    final local = widget.message.localPath;
    if (local != null && File(local).existsSync()) return DeviceFileSource(local);
    return null;
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    if (identical(_active, this)) _active = null;
    _player?.dispose();
    super.dispose();
  }

  AudioPlayer _ensurePlayer() {
    final existing = _player;
    if (existing != null) return existing;
    final p = AudioPlayer();
    _subs.add(p.onPositionChanged.listen((d) {
      if (mounted) setState(() => _position = d);
    }));
    _subs.add(p.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    }));
    _subs.add(p.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _playing = state == PlayerState.playing);
    }));
    _subs.add(p.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _playing = false;
          _position = Duration.zero;
        });
      }
    }));
    _player = p;
    return p;
  }

  void _pauseFromOutside() {
    _player?.pause();
  }

  Future<void> _toggle() async {
    final source = _source;
    if (source == null) {
      showErrorSnack(context, 'This voice message is not available');
      return;
    }
    final player = _ensurePlayer();
    if (_playing) {
      await player.pause();
      return;
    }
    if (_active != null && !identical(_active, this)) _active!._pauseFromOutside();
    _active = this;
    setState(() => _loading = true);
    try {
      if (_position > Duration.zero && player.state == PlayerState.paused) {
        await player.resume();
      } else {
        await player.play(source);
      }
    } catch (_) {
      if (mounted) showErrorSnack(context, 'Could not play this voice message');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _seek(double fraction) async {
    final total = _total;
    if (total <= Duration.zero) return;
    final target = Duration(milliseconds: (total.inMilliseconds * fraction.clamp(0.0, 1.0)).round());
    if (_player == null || (!_playing && _position == Duration.zero)) {
      await _toggle();
    }
    await _player?.seek(target);
    if (mounted) setState(() => _position = target);
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    final uploading = m.status == MessageStatus.uploading;
    final active = widget.isMe ? Colors.white : AppColors.primaryLight;
    final inactive = widget.isMe ? Colors.white38 : AppColors.textSecondary.withValues(alpha: 0.5);
    final shownSeconds = _playing || _position > Duration.zero ? _position.inSeconds : _total.inSeconds;

    return SizedBox(
      width: 230,
      child: Row(
        children: [
          GestureDetector(
            onTap: uploading ? null : _toggle,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: widget.isMe ? Colors.white.withValues(alpha: 0.2) : AppColors.primary.withValues(alpha: 0.25),
                shape: BoxShape.circle,
              ),
              child: uploading || _loading
                  ? Padding(
                      padding: const EdgeInsets.all(10),
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                        value: uploading && (m.uploadProgress ?? 0) > 0 ? m.uploadProgress : null,
                      ),
                    )
                  : Icon(
                      _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, c) => GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: uploading ? null : (d) => _seek(d.localPosition.dx / c.maxWidth),
                    child: WaveformBars(
                      samples: m.audioWaveform,
                      activeColor: active,
                      inactiveColor: inactive,
                      progress: _progress,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  formatVoiceDuration(shownSeconds),
                  style: TextStyle(
                    color: widget.isMe ? Colors.white70 : AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class VoiceRecording {
  final String path;
  final int durationSeconds;
  final int sizeBytes;
  final List<double> waveform;

  const VoiceRecording({
    required this.path,
    required this.durationSeconds,
    required this.sizeBytes,
    required this.waveform,
  });
}

class VoiceRecorderController extends ChangeNotifier {
  final AudioRecorder _recorder = AudioRecorder();
  final List<double> _samples = [];
  StreamSubscription<Amplitude>? _ampSub;
  Timer? _ticker;
  DateTime? _startedAt;
  String? _path;
  bool _recording = false;
  int _elapsedMs = 0;

  bool get recording => _recording;
  int get elapsedMs => _elapsedMs;
  List<double> get samples => _samples;

  Future<bool> start() async {
    if (_recording) return true;
    if (!await _recorder.hasPermission()) return false;
    final path = '${Directory.systemTemp.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 44100),
      path: path,
    );
    _path = path;
    _samples.clear();
    _startedAt = DateTime.now();
    _elapsedMs = 0;
    _recording = true;
    _ampSub = _recorder.onAmplitudeChanged(const Duration(milliseconds: 100)).listen((a) {
      _samples.add(((a.current + 45) / 45).clamp(0.0, 1.0).toDouble());
    });
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _elapsedMs = DateTime.now().difference(_startedAt!).inMilliseconds;
      notifyListeners();
    });
    notifyListeners();
    return true;
  }

  Future<void> _halt() async {
    _ticker?.cancel();
    _ticker = null;
    await _ampSub?.cancel();
    _ampSub = null;
    _recording = false;
  }

  Future<VoiceRecording?> stop() async {
    if (!_recording) return null;
    final elapsed = _startedAt == null ? _elapsedMs : DateTime.now().difference(_startedAt!).inMilliseconds;
    await _halt();
    final path = await _recorder.stop() ?? _path;
    notifyListeners();
    if (path == null) return null;
    final file = File(path);
    if (elapsed < 1000 || !await file.exists()) {
      if (await file.exists()) await file.delete();
      return null;
    }
    final waveform = resampleWaveform(List<double>.of(_samples), 64)
        .map((v) => double.parse(v.toStringAsFixed(2)))
        .toList();
    return VoiceRecording(
      path: path,
      durationSeconds: (elapsed / 1000).round().clamp(1, 24 * 3600),
      sizeBytes: await file.length(),
      waveform: waveform,
    );
  }

  Future<void> cancel() async {
    if (!_recording) return;
    await _halt();
    try {
      await _recorder.cancel();
    } catch (_) {}
    final path = _path;
    if (path != null) {
      final f = File(path);
      if (await f.exists()) await f.delete();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _ampSub?.cancel();
    _recorder.dispose();
    super.dispose();
  }
}

class VoiceRecorderBar extends StatelessWidget {
  const VoiceRecorderBar({super.key, required this.controller, required this.onCancel, required this.onSend});

  final VoiceRecorderController controller;
  final VoidCallback onCancel;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final recent = controller.samples.length > 60
            ? controller.samples.sublist(controller.samples.length - 60)
            : controller.samples;
        return Row(
          children: [
            IconButton(
              tooltip: 'Discard',
              onPressed: onCancel,
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
            ),
            const _PulsingDot(),
            const SizedBox(width: 8),
            Text(
              formatVoiceDuration(controller.elapsedMs ~/ 1000),
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: WaveformBars(
                samples: recent,
                bars: 40,
                height: 26,
                progress: 1,
                activeColor: AppColors.primaryLight,
                inactiveColor: AppColors.primaryLight,
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Send voice message',
              onPressed: onSend,
              icon: const Icon(Icons.send_rounded, color: AppColors.primary),
            ),
          ],
        );
      },
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.3, end: 1).animate(_c),
      child: Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
      ),
    );
  }
}