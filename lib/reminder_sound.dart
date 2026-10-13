import 'package:flutter/services.dart';

enum ReminderSound {
  woodTap('wood_tap', '轻巧木音'),
  softChime('soft_chime', '柔和双音'),
  clearBell('clear_bell', '清亮铃声'),
  warmKeys('warm_keys', '温暖琴音'),
  none('none', '静音');

  const ReminderSound(this.key, this.label);
  final String key, label;
  static ReminderSound fromKey(Object? key) =>
      values.firstWhere((sound) => sound.key == key, orElse: () => none);
  Future<void> preview() =>
      const MethodChannel('good_day/reminder')
          .invokeMethod<void>('previewSound', {'sound': key});
}
