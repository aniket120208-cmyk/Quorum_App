import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SystemPipService {
  SystemPipService._() {
    if (Platform.isAndroid) _channel.setMethodCallHandler(_onCall);
  }
  static final SystemPipService instance = SystemPipService._();

  static const MethodChannel _channel = MethodChannel('quorum/pip');

  final ValueNotifier<bool> active = ValueNotifier<bool>(false);
  bool? _supported;

  Future<dynamic> _onCall(MethodCall call) async {
    if (call.method == 'onPipChanged') {
      active.value = call.arguments == true;
    }
  }

  Future<bool> isSupported() async {
    if (!Platform.isAndroid) return false;
    if (_supported != null) return _supported!;
    try {
      _supported = await _channel.invokeMethod<bool>('isSupported') ?? false;
    } catch (_) {
      _supported = false;
    }
    return _supported!;
  }

  Future<void> setAutoEnter(bool enabled, {int width = 9, int height = 16}) async {
    if (!await isSupported()) return;
    try {
      await _channel.invokeMethod<bool>('setAutoEnter', {
        'enabled': enabled,
        'width': width,
        'height': height,
      });
    } catch (_) {}
  }

  Future<bool> enter({int width = 9, int height = 16}) async {
    if (!await isSupported()) return false;
    try {
      return await _channel.invokeMethod<bool>('enter', {'width': width, 'height': height}) ?? false;
    } catch (_) {
      return false;
    }
  }
}