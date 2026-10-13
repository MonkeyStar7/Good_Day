import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:good_day/main.dart';
import 'package:good_day/reminder_sound.dart';
import 'package:good_day/settings/app_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('wood default, unknown settings and explicit silence remain stable', () {
    expect(AppSettings.fromJson({}).reminderSound, ReminderSound.woodTap);
    expect(
      AppSettings.fromJson({'reminderSound': 'broken'}).reminderSound,
      ReminderSound.woodTap,
    );
    expect(
      AppSettings.fromJson({'reminderSound': 'none'}).reminderSound,
      ReminderSound.none,
    );
  });
  test('four bundled tones are short PCM WAV files with audible, unclipped samples', () async {
    for (final sound in ReminderSound.values.where(
      (s) => s != ReminderSound.none,
    )) {
      final bytes = await File('assets/sounds/${sound.key}.wav').readAsBytes();
      final data = ByteData.sublistView(bytes);
      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
      expect(data.getUint16(20, Endian.little), 1);
      expect(data.getUint16(22, Endian.little), 1);
      expect(data.getUint16(34, Endian.little), 16);
      final rate = data.getUint32(24, Endian.little);
      expect(rate, 44100);
      expect((bytes.length - 44) / (2 * rate), inInclusiveRange(0.5, 3));
      var peak = 0;
      for (var i = 44; i + 1 < bytes.length; i += 2) {
        final value = data.getInt16(i, Endian.little).abs();
        if (value > peak) peak = value;
      }
      expect(peak, inInclusiveRange(1000, 16000));
      final bundled = await rootBundle.load('assets/sounds/${sound.key}.wav');
      expect(bundled.lengthInBytes, bytes.length);
    }
  });
  testWidgets(
    'settings preview uses selected sound and mute disables preview',
    (tester) async {
      final settings = AppSettingsController.inMemory();
      addTearDown(settings.dispose);
      final calls = <MethodCall>[];
      const channel = MethodChannel('good_day/reminder');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsPage(
            controller: settings,
            initialVaultPath: 'test-vault',
            onVaultSelected: (
              path, {
              required deleteSourceAfterMigration,
            }) async => path,
            onLoadTrash: () async => [],
            onRestoreTrashItem: (_) async {},
            onEmptyTrash: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final selector = find.byKey(const Key('reminder-sound-choice'));
      await tester.scrollUntilVisible(selector, 150);
      final control = tester.getRect(
        find.byKey(const Key('reminder-sound-control')),
      );
      final label = tester.getRect(
        find.descendant(of: selector, matching: find.text('轻巧木音')),
      );
      expect(label.left - control.left, greaterThanOrEqualTo(12));
      expect(label.right, lessThan(control.right));
      await tester.tap(find.byKey(const Key('preview-reminder-sound')));
      await tester.pumpAndSettle();
      expect(calls.single.method, 'previewSound');
      expect(calls.single.arguments, {'sound': 'wood_tap'});
      await tester.tap(selector);
      await tester.pumpAndSettle();
      await tester.tap(find.text('温暖琴音').last);
      await tester.pumpAndSettle();
      expect(settings.settings.reminderSound, ReminderSound.warmKeys);
      await tester.tap(find.byKey(const Key('preview-reminder-sound')));
      await tester.pumpAndSettle();
      expect(calls.last.arguments, {'sound': 'warm_keys'});
      await tester.tap(selector);
      await tester.pumpAndSettle();
      await tester.tap(find.text('静音').last);
      await tester.pumpAndSettle();
      expect(settings.settings.reminderSound, ReminderSound.none);
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('preview-reminder-sound')))
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
