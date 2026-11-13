import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/recording_repository.dart';
import 'package:quorum_app/models/recording_models.dart';

enum RecordingJobStage { queued, preparing, uploading, finalizing, done, failed }

class RecordingJob extends ChangeNotifier {
  RecordingJob({
    required this.meetingCode,
    required this.recordingId,
    required this.path,
    required this.durationSeconds,
  });

  final String meetingCode;
  final String recordingId;
  final String path;
  final int durationSeconds;

  RecordingJobStage stage = RecordingJobStage.queued;
  double progress = 0;
  String? error;
  RecordingUploadTarget? target;
  bool uploaded = false;
  int fileSize = 0;
  bool _running = false;

  bool get isActive =>
      stage == RecordingJobStage.preparing ||
      stage == RecordingJobStage.uploading ||
      stage == RecordingJobStage.finalizing ||
      stage == RecordingJobStage.queued;

  void _set(RecordingJobStage s, {double? progress, String? error}) {
    stage = s;
    if (progress != null) this.progress = progress;
    this.error = error;
    notifyListeners();
  }
}

class RecordingUploader extends ChangeNotifier {
  RecordingUploader._();
  static final RecordingUploader instance = RecordingUploader._();

  final RecordingRepository _repo = RecordingRepository.instance;
  final List<RecordingJob> _jobs = [];
  final StreamController<RecordingJob> _finished = StreamController<RecordingJob>.broadcast();

  List<RecordingJob> get jobs => List.unmodifiable(_jobs);
  Stream<RecordingJob> get finished => _finished.stream;

  List<RecordingJob> jobsFor(String meetingCode) => _jobs.where((j) => j.meetingCode == meetingCode).toList();

  RecordingJob enqueue({
    required String meetingCode,
    required String recordingId,
    required String path,
    required int durationSeconds,
  }) {
    final job = RecordingJob(
      meetingCode: meetingCode,
      recordingId: recordingId,
      path: path,
      durationSeconds: durationSeconds,
    );
    _jobs.add(job);
    notifyListeners();
    unawaited(run(job));
    return job;
  }

  void dismiss(RecordingJob job) {
    _jobs.remove(job);
    notifyListeners();
  }

  Future<void> run(RecordingJob job) async {
    if (job._running) return;
    job._running = true;
    try {
      final file = File(job.path);
      if (!await file.exists()) {
        throw ApiException('The recorded video file is no longer available on this device.');
      }
      job.fileSize = await file.length();
      if (job.fileSize == 0) {
        throw ApiException('The recorded video is empty.');
      }

      if (job.target == null) {
        job._set(RecordingJobStage.preparing, progress: 0);
        job.target = await _repo.uploadUrl(job.meetingCode, 'recording-${job.recordingId}.mp4');
      }

      if (!job.uploaded) {
        job._set(RecordingJobStage.uploading, progress: 0);
        await _repo.putFile(
          job.target!.uploadUrl,
          file,
          onProgress: (p) {
            job.progress = p;
            job.notifyListeners();
          },
        );
        job.uploaded = true;
      }

      job._set(RecordingJobStage.finalizing, progress: 1);
      await _repo.complete(
        job.recordingId,
        fileUrl: job.target!.fileUrl,
        durationSeconds: job.durationSeconds,
        fileSizeBytes: job.fileSize,
      );
      job._set(RecordingJobStage.done, progress: 1);
      try {
        await file.delete();
      } catch (_) {}
      _finished.add(job);
    } catch (e) {
      job._set(RecordingJobStage.failed, error: errorText(e));
      _finished.add(job);
    } finally {
      job._running = false;
      notifyListeners();
    }
  }

  Future<void> retry(RecordingJob job) async {
    if (job._running) return;
    if (job.stage != RecordingJobStage.failed) return;
    if (!job.uploaded) {
      job.progress = 0;
      job.target = null;
    }
    await run(job);
  }
}