import 'package:flutter/foundation.dart';
import 'package:flutter_background/flutter_background.dart';

class ScreenShareForeground {
  ScreenShareForeground._();

  static bool _initialized = false;

  static bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<bool> start() async {
    if (!_isAndroid) return true;
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
      await FlutterBackground.disableBackgroundExecution().timeout(const Duration(seconds: 3));
    } catch (_) {}
  }
}
