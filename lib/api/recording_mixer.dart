import 'dart:io';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

class MicSegment {
  const MicSegment(this.path, this.offsetMs);
  final String path;
  final int offsetMs;
}

class RecordingMixer {
  RecordingMixer._();

  static Future<bool> _hasAudio(String path) async {
    try {
      final session = await FFprobeKit.getMediaInformation(path);
      final info = session.getMediaInformation();
      if (info == null) return true;
      final streams = info.getStreams();
      return streams.any((s) => s.getType() == 'audio');
    } catch (_) {
      return true;
    }
  }

  static Future<void> _delete(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  static Future<String> mix(String videoPath, List<MicSegment> segments) async {
    final usable = <MicSegment>[];
    for (final s in segments) {
      try {
        final f = File(s.path);
        if (await f.exists() && await f.length() > 2048) usable.add(s);
      } catch (_) {}
    }
    if (usable.isEmpty) {
      for (final s in segments) {
        await _delete(s.path);
      }
      return videoPath;
    }
    final out = videoPath.endsWith('.mp4')
        ? '${videoPath.substring(0, videoPath.length - 4)}-mixed.mp4'
        : '$videoPath-mixed.mp4';
    var result = videoPath;
    try {
      final remote = await _hasAudio(videoPath);
      final args = <String>['-y', '-i', videoPath];
      for (final s in usable) {
        args.addAll(['-i', s.path]);
      }
      final parts = <String>[];
      final labels = <String>[if (remote) '[0:a]'];
      for (var i = 0; i < usable.length; i++) {
        final input = i + 1;
        parts.add('[$input:a]adelay=${usable[i].offsetMs}:all=1[m$input]');
        labels.add('[m$input]');
      }
      if (labels.length == 1) {
        parts.add('${labels.first}anull[aout]');
      } else {
        parts.add('${labels.join()}amix=inputs=${labels.length}:duration=longest:dropout_transition=0:normalize=0[aout]');
      }
      args.addAll([
        '-filter_complex',
        parts.join(';'),
        '-map',
        '0:v',
        '-map',
        '[aout]',
        '-c:v',
        'copy',
        '-c:a',
        'aac',
        '-b:a',
        '128k',
        '-movflags',
        '+faststart',
        out,
      ]);
      final session = await FFmpegKit.executeWithArguments(args);
      final code = await session.getReturnCode();
      if (ReturnCode.isSuccess(code)) {
        final f = File(out);
        if (await f.exists() && await f.length() > 0) {
          result = out;
        }
      }
    } catch (_) {}
    if (result == videoPath) {
      await _delete(out);
    } else {
      await _delete(videoPath);
    }
    for (final s in segments) {
      await _delete(s.path);
    }
    return result;
  }
}