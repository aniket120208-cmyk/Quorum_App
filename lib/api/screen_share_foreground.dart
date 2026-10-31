import 'package:flutter/foundation.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class ScreenShareForeground {
  ScreenShareForeground._();

  static bool _initialized = false;

  static bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<bool> start() async {
    if (!_isAndroid) return true;
    final granted = await Helper.requestCapturePermission();
    if (!granted) return false;
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
    return FlutterBackground.enableBackgroundExecution();
  }

  static Future<void> stop() async {
    if (!_isAndroid) return;
    try {
      await FlutterBackground.disableBackgroundExecution();
    } catch (_) {}
  }
}
