import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:good_day/desktop_experience.dart';
import 'package:good_day/models/good_day_event.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('good_day/reminder');
  const codec = StandardMethodCodec();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  Future<void> action(int minutes) async {
    final finished = Completer<void>();
    messenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(MethodCall('action', minutes)),
      (_) => finished.complete(),
    );
    await finished.future;
  }

  GoodDayEvent event() => GoodDayEvent(
    id: 'test',
    title: '开会',
    startsAt: DateTime(2026, 10, 12, 9),
  );

  test(
    'native reminder stays open until acknowledgement is durably saved',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      final saved = Completer<void>();
      final shown = SystemDesktopExperience().showEventReminder(
        event(),
        event().startsAt,
        event().startsAt,
        (_) => saved.future,
      );
      await Future<void>.delayed(Duration.zero);
      expect(calls.single.method, 'show');
      final resolving = action(0);
      await Future<void>.delayed(Duration.zero);
      expect(calls.map((call) => call.method), ['show']);
      saved.complete();
      await resolving;
      expect(await shown, isTrue);
      expect(calls.map((call) => call.method), ['show', 'dismiss']);
    },
  );
  test('failed save shows native error and snooze can be retried', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    var fail = true;
    Duration? snooze;
    final shown = SystemDesktopExperience().showEventReminder(
      event(),
      event().startsAt,
      event().startsAt,
      (duration) async {
        if (fail) throw Exception('磁盘不可写');
        snooze = duration;
      },
    );
    await Future<void>.delayed(Duration.zero);
    await action(10);
    expect(calls.map((call) => call.method), ['show', 'error']);
    fail = false;
    await action(10);
    expect(await shown, isTrue);
    expect(snooze, const Duration(minutes: 10));
    expect(calls.last.method, 'dismiss');
  });
}
