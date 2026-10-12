import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:good_day/desktop_experience.dart';
import 'package:good_day/models/good_day_event.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const window = MethodChannel('window_manager');
  const reminder = MethodChannel('good_day/reminder');

  test('pin and temporary reminder topmost remain independent, including concurrent changes', () async {
    final applied = <bool>[];
    var fail = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(window, (call) async {
          if (call.method == 'setAlwaysOnTop') {
            if (fail) throw PlatformException(code: 'failed');
            applied.add((call.arguments as Map)['isAlwaysOnTop'] as bool);
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(window, null),
    );
    final desktop = SystemDesktopExperience();
    await desktop.setWindowPinned(true);
    await desktop.setReminderOnTop(true);
    await desktop.setReminderOnTop(false);
    expect(desktop.windowPinned.value, true);
    expect(applied, [true, true, true]);
    await desktop.setWindowPinned(false);
    expect(applied.last, false);
    await Future.wait([
      desktop.setReminderOnTop(true),
      desktop.setWindowPinned(true),
    ]);
    await desktop.setWindowPinned(false);
    expect(applied.last, true);
    await desktop.setReminderOnTop(false);
    expect(applied.last, false);
    fail = true;
    await expectLater(
      desktop.setWindowPinned(true),
      throwsA(isA<PlatformException>()),
    );
    expect(desktop.windowPinned.value, false);
  });

  test('native reminder receives the current accent', () async {
    Map? payload;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(reminder, (call) async {
          if (call.method == 'show') payload = call.arguments as Map;
          throw MissingPluginException();
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(reminder, null),
    );
    final now = DateTime(2026, 10, 12, 10);
    final desktop = SystemDesktopExperience();
    expect(
      await desktop.showEventReminder(
        GoodDayEvent(id: 'theme', title: '读书', startsAt: now),
        now,
        now,
        (_) async {},
        accentRgb: 0x536D7A,
      ),
      false,
    );
    expect(payload!['accentRgb'], 0x536D7A);
    expect(payload!.containsKey('timing'), isFalse);
  });
}
