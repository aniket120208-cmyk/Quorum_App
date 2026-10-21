import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:quorum_app/models/chat_models.dart';
import 'chat_widgets.dart';

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
                  builder: (_) => ImageViewerScreen(url: message.fileUrl!),
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
        ],
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final uri = Uri.tryParse(message.fileUrl!);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      showErrorSnack(context, 'Could not open this file');
    }
  }
}

class ImageViewerScreen extends StatelessWidget {
  const ImageViewerScreen({super.key, required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
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