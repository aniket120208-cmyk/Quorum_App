import 'dart:io';
import 'package:flutter/material.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/download_service.dart';
import 'package:quorum_app/models/chat_models.dart';
import 'chat_widgets.dart';
import 'file_preview_screen.dart';
export 'file_preview_screen.dart' show openFilePreview;

class AttachmentView extends StatelessWidget {
  const AttachmentView({super.key, required this.message});

  final ChatMessage message;

  bool get _isImage => message.fileType == 'image';
  bool get _uploading => message.status == MessageStatus.uploading;

  @override
  Widget build(BuildContext context) {
    return _isImage ? _image(context) : _fileTile(context);
  }

  Widget _brokenImage() => const SizedBox(
        width: 220,
        height: 140,
        child: Center(
          child: Icon(Icons.broken_image_outlined, color: AppColors.textSecondary, size: 32),
        ),
      );

  Widget _networkImage() {
    final url = message.fileUrl;
    if (url == null) return _brokenImage();
    return Image.network(
      url,
      width: 220,
      height: 220,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return const SizedBox(
          width: 220,
          height: 220,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        );
      },
      errorBuilder: (context, error, stack) => _brokenImage(),
    );
  }

  Widget _image(BuildContext context) {
    final local = message.localPath;
    final Widget img = local != null
        ? Image.file(
            File(local),
            width: 220,
            height: 220,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stack) => _networkImage(),
          )
        : _networkImage();

    return GestureDetector(
      onTap: (_uploading || message.fileUrl == null)
          ? null
          : () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ImageViewerScreen(
                    url: message.fileUrl!,
                    fileName: message.attachmentName,
                  ),
                ),
              ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          alignment: Alignment.center,
          children: [
            img,
            if (_uploading)
              Positioned.fill(
                child: Container(
                  color: Colors.black54,
                  child: Center(
                    child: CircularProgressIndicator(
                      value: (message.uploadProgress ?? 0) > 0
                          ? message.uploadProgress
                          : null,
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  IconData get _fileIcon {
    switch (message.fileType) {
      case 'video':
        return Icons.videocam_outlined;
      case 'audio':
        return Icons.audiotrack_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  Widget _fileTile(BuildContext context) {
    return InkWell(
      onTap: (_uploading || message.fileUrl == null)
          ? null
          : () => _open(context),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: Colors.black26,
              shape: BoxShape.circle,
            ),
            child: _uploading
                ? Padding(
                    padding: const EdgeInsets.all(10),
                    child: CircularProgressIndicator(
                      value: (message.uploadProgress ?? 0) > 0
                          ? message.uploadProgress
                          : null,
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : Icon(_fileIcon, color: AppColors.textPrimary, size: 22),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              message.attachmentName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                decoration: TextDecoration.underline,
                decorationColor: AppColors.textSecondary,
              ),
            ),
          ),
          if (!_uploading && message.fileUrl != null)
            DownloadButton(url: message.fileUrl!, fileName: message.attachmentName),
        ],
      ),
    );
  }

  void _open(BuildContext context) =>
      openFilePreview(context, message.fileUrl!, message.attachmentName);
}

Future<void> downloadAttachment(BuildContext context, String url, String? fileName) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      const SnackBar(
        content: Text('Downloading...', style: TextStyle(color: Colors.white)),
        backgroundColor: Color(0xFF334155),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 30),
      ),
    );
  try {
    final saved = await DownloadService.instance.save(url: url, fileName: fileName);
    if (saved == null || saved.isEmpty) {
      messenger.hideCurrentSnackBar();
      return;
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Saved to your device', style: TextStyle(color: Colors.white)),
          backgroundColor: Color(0xFF334155),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
  } catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(e is ApiException ? e.message : 'Could not save this file', style: const TextStyle(color: Colors.white)),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }
}

class DownloadButton extends StatefulWidget {
  const DownloadButton({super.key, required this.url, this.fileName, this.color = AppColors.textPrimary});

  final String url;
  final String? fileName;
  final Color color;

  @override
  State<DownloadButton> createState() => _DownloadButtonState();
}

class _DownloadButtonState extends State<DownloadButton> {
  bool _busy = false;

  Future<void> _download() async {
    if (_busy) return;
    setState(() => _busy = true);
    await downloadAttachment(context, widget.url, widget.fileName);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Download',
      visualDensity: VisualDensity.compact,
      onPressed: _busy ? null : _download,
      icon: _busy
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: widget.color),
            )
          : Icon(Icons.download_rounded, size: 20, color: widget.color),
    );
  }
}

class ImageViewerScreen extends StatelessWidget {
  const ImageViewerScreen({super.key, required this.url, this.fileName});
  final String url;
  final String? fileName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          DownloadButton(url: url, fileName: fileName, color: Colors.white),
          const SizedBox(width: 4),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          child: Image.network(
            url,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return const CircularProgressIndicator();
            },
            errorBuilder: (context, error, stack) => const Icon(
              Icons.broken_image_outlined,
              color: Colors.white54,
              size: 48,
            ),
          ),
        ),
      ),
    );
  }
}