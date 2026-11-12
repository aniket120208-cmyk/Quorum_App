import 'dart:async';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'attachment_widgets.dart';
import 'chat_widgets.dart';

enum PreviewKind { image, pdf, video, audio, text, office, other }

const _bg = Color(0xFF0F101A);

PreviewKind previewKindFor(String name, String url) {
  String extOf(String v) {
    final clean = v.split('?').first;
    final dot = clean.lastIndexOf('.');
    if (dot == -1 || dot == clean.length - 1) return '';
    return clean.substring(dot + 1).toLowerCase();
  }

  var ext = extOf(name);
  if (ext.isEmpty) {
    final segments = Uri.tryParse(url)?.pathSegments;
    if (segments != null && segments.isNotEmpty) ext = extOf(segments.last);
  }
  if (const {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'}.contains(ext)) return PreviewKind.image;
  if (ext == 'pdf') return PreviewKind.pdf;
  if (const {'mp4', 'mov', 'm4v', 'webm', '3gp', 'mkv', 'avi'}.contains(ext)) return PreviewKind.video;
  if (const {'mp3', 'wav', 'm4a', 'aac', 'ogg', 'opus', 'flac'}.contains(ext)) return PreviewKind.audio;
  if (const {'txt', 'md', 'csv', 'json', 'log', 'xml', 'yaml', 'yml', 'html', 'css', 'js', 'dart', 'py', 'java', 'sql'}
      .contains(ext)) {
    return PreviewKind.text;
  }
  if (const {'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'odt', 'ods', 'odp', 'rtf'}.contains(ext)) {
    return PreviewKind.office;
  }
  return PreviewKind.other;
}

Future<void> openFilePreview(BuildContext context, String url, String? fileName) {
  return Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => FilePreviewScreen(url: url, fileName: fileName)),
  );
}

class FilePreviewScreen extends StatelessWidget {
  const FilePreviewScreen({super.key, required this.url, this.fileName});

  final String url;
  final String? fileName;

  String get _name {
    if (fileName != null && fileName!.trim().isNotEmpty) return fileName!;
    final segments = Uri.tryParse(url)?.pathSegments;
    if (segments == null || segments.isEmpty) return 'File';
    return Uri.decodeComponent(segments.last);
  }

  Widget _body() {
    switch (previewKindFor(_name, url)) {
      case PreviewKind.image:
        return Center(
          child: InteractiveViewer(
            child: Image.network(
              url,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return const CircularProgressIndicator();
              },
              errorBuilder: (context, error, stack) => _PreviewMessage(
                icon: Icons.broken_image_outlined,
                text: 'Could not load this image',
                url: url,
                name: _name,
              ),
            ),
          ),
        );
      case PreviewKind.pdf:
        return _PdfPreview(url: url, name: _name);
      case PreviewKind.video:
        return _VideoPreview(url: url, name: _name);
      case PreviewKind.audio:
        return _AudioPreview(url: url, name: _name);
      case PreviewKind.text:
        return _TextPreview(url: url, name: _name);
      case PreviewKind.office:
        return _WebPreview(url: url, name: _name);
      case PreviewKind.other:
        return _PreviewMessage(
          icon: Icons.insert_drive_file_outlined,
          text: 'Preview is not available for this file type',
          url: url,
          name: _name,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          _name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        actions: [
          DownloadButton(url: url, fileName: _name, color: Colors.white),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(child: _body()),
    );
  }
}

class _PreviewMessage extends StatelessWidget {
  const _PreviewMessage({required this.icon, required this.text, required this.url, required this.name});

  final IconData icon;
  final String text;
  final String url;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: AppColors.textSecondary),
            const SizedBox(height: 14),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
            ),
            const SizedBox(height: 6),
            Text(
              name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => downloadAttachment(context, url, name),
              icon: const Icon(Icons.download_rounded),
              label: const Text('Download'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PdfPreview extends StatefulWidget {
  const _PdfPreview({required this.url, required this.name});

  final String url;
  final String name;

  @override
  State<_PdfPreview> createState() => _PdfPreviewState();
}

class _PdfPreviewState extends State<_PdfPreview> {
  PdfControllerPinch? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await Dio().get<List<int>>(
        widget.url,
        options: Options(responseType: ResponseType.bytes),
      );
      final data = res.data;
      if (data == null || data.isEmpty) throw Exception('empty');
      final controller = PdfControllerPinch(
        document: PdfDocument.openData(Uint8List.fromList(data)),
      );
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return _PreviewMessage(
        icon: Icons.picture_as_pdf_outlined,
        text: 'Could not load this PDF',
        url: widget.url,
        name: widget.name,
      );
    }
    final c = _controller;
    if (c == null) return const Center(child: CircularProgressIndicator());
    return PdfViewPinch(
      controller: c,
      onDocumentError: (_) {
        if (mounted) setState(() => _failed = true);
      },
    );
  }
}

class _VideoPreview extends StatefulWidget {
  const _VideoPreview({required this.url, required this.name});

  final String url;
  final String name;

  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<_VideoPreview> {
  late final VideoPlayerController _c;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _c.addListener(_tick);
    _c.initialize().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
      _c.play();
    }).catchError((_) {
      if (mounted) setState(() => _failed = true);
    });
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _c.removeListener(_tick);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return _PreviewMessage(
        icon: Icons.videocam_off_outlined,
        text: 'Could not play this video',
        url: widget.url,
        name: widget.name,
      );
    }
    if (!_ready) return const Center(child: CircularProgressIndicator());
    final playing = _c.value.isPlaying;
    return Column(
      children: [
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: _c.value.aspectRatio == 0 ? 16 / 9 : _c.value.aspectRatio,
              child: GestureDetector(
                onTap: () => playing ? _c.pause() : _c.play(),
                child: VideoPlayer(_c),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: VideoProgressIndicator(
            _c,
            allowScrubbing: true,
            colors: const VideoProgressColors(
              playedColor: AppColors.primary,
              bufferedColor: AppColors.surfaceBorder,
              backgroundColor: AppColors.surface,
            ),
          ),
        ),
        IconButton(
          iconSize: 44,
          color: Colors.white,
          onPressed: () => playing ? _c.pause() : _c.play(),
          icon: Icon(playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _AudioPreview extends StatefulWidget {
  const _AudioPreview({required this.url, required this.name});

  final String url;
  final String name;

  @override
  State<_AudioPreview> createState() => _AudioPreviewState();
}

class _AudioPreviewState extends State<_AudioPreview> {
  final AudioPlayer _player = AudioPlayer();
  final List<StreamSubscription> _subs = [];
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _started = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _subs.add(_player.onPositionChanged.listen((d) {
      if (mounted) setState(() => _position = d);
    }));
    _subs.add(_player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    }));
    _subs.add(_player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _playing = s == PlayerState.playing);
    }));
    _subs.add(_player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _position = Duration.zero;
          _playing = false;
          _started = false;
        });
      }
    }));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    try {
      if (_playing) {
        await _player.pause();
      } else if (_started) {
        await _player.resume();
      } else {
        _started = true;
        await _player.play(UrlSource(widget.url));
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return _PreviewMessage(
        icon: Icons.audiotrack_outlined,
        text: 'Could not play this audio',
        url: widget.url,
        name: widget.name,
      );
    }
    final max = _duration.inMilliseconds <= 0 ? 1.0 : _duration.inMilliseconds.toDouble();
    final value = _position.inMilliseconds.toDouble().clamp(0.0, max);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.audiotrack_rounded, size: 72, color: AppColors.primaryLight),
            const SizedBox(height: 16),
            Text(
              widget.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
            ),
            const SizedBox(height: 20),
            Slider(
              value: value,
              max: max,
              onChanged: _duration == Duration.zero
                  ? null
                  : (v) => _player.seek(Duration(milliseconds: v.toInt())),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_fmt(_position), style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  Text(_fmt(_duration), style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            IconButton(
              iconSize: 56,
              color: Colors.white,
              onPressed: _toggle,
              icon: Icon(_playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _TextPreview extends StatefulWidget {
  const _TextPreview({required this.url, required this.name});

  final String url;
  final String name;

  @override
  State<_TextPreview> createState() => _TextPreviewState();
}

class _TextPreviewState extends State<_TextPreview> {
  late final Future<String> _future = _load();

  Future<String> _load() async {
    final res = await Dio().get<String>(
      widget.url,
      options: Options(responseType: ResponseType.plain),
    );
    final text = res.data ?? '';
    return text.length > 200000 ? text.substring(0, 200000) : text;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return _PreviewMessage(
            icon: Icons.description_outlined,
            text: 'Could not load this file',
            url: widget.url,
            name: widget.name,
          );
        }
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: SelectableText(
            snap.data!,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, height: 1.4, fontFamily: 'monospace'),
          ),
        );
      },
    );
  }
}

class _WebPreview extends StatefulWidget {
  const _WebPreview({required this.url, required this.name});

  final String url;
  final String name;

  @override
  State<_WebPreview> createState() => _WebPreviewState();
}

class _WebPreviewState extends State<_WebPreview> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame == true && mounted) setState(() => _failed = true);
          },
        ),
      )
      ..loadRequest(
        Uri.parse('https://docs.google.com/gview?embedded=true&url=${Uri.encodeComponent(widget.url)}'),
      );
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return _PreviewMessage(
        icon: Icons.description_outlined,
        text: 'Could not preview this document',
        url: widget.url,
        name: widget.name,
      );
    }
    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_loading) const Center(child: CircularProgressIndicator()),
      ],
    );
  }
}