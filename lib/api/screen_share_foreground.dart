import 'package:flutter/foundation.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show Helper;

class ScreenShareForeground {
  ScreenShareForeground._();

  static bool _initialized = false;

  static bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<bool> start() async {
    if (!_isAndroid) return true;
    try {
      if (!await Helper.requestCapturePermission()) return false;
      if (!_initialized) {
        _initialized = await FlutterBackground.initialize(
          androidConfig: FlutterBackgroundAndroidConfig(
            notificationTitle: 'Quorum screen sharing',
            notificationText: 'You are sharing your screen in a meeting.',
            notificationImportance: AndroidNotificationImportance.normal,
          ),
        );
        if (!_initialized) return false;
      }
      return await FlutterBackground.enableBackgroundExecution();
    } catch (_) {
      _initialized = false;
      return false;
    }
  }

  static Future<void> stop() async {
    if (!_isAndroid) return;
    try {
      await FlutterBackground.disableBackgroundExecution().timeout(const Duration(seconds: 3));
    } catch (_) {}
  }
}
