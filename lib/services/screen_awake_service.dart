import 'package:wakelock_plus/wakelock_plus.dart';

class ScreenAwakeService {
  ScreenAwakeService._();

  static int _activeOperations = 0;

  static Future<T> keepAwake<T>(Future<T> Function() action) async {
    await _enable();
    try {
      return await action();
    } finally {
      await _disable();
    }
  }

  static Future<void> _enable() async {
    _activeOperations += 1;
    if (_activeOperations == 1) {
      try {
        await WakelockPlus.enable();
      } catch (_) {
        // Best-effort: non bloccare mai import/condivisioni per errori wakelock.
      }
    }
  }

  static Future<void> _disable() async {
    if (_activeOperations <= 0) return;
    _activeOperations -= 1;
    if (_activeOperations == 0) {
      try {
        await WakelockPlus.disable();
      } catch (_) {
        // Best-effort: non bloccare mai import/condivisioni per errori wakelock.
      }
    }
  }
}
