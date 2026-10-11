import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:good_day/data/vault_repository.dart';
import 'package:good_day/event_reminder_service.dart';
import 'package:good_day/models/good_day_event.dart';

GoodDayEvent event({
  EventRepeat repeat = EventRepeat.once,
  DateTime? start,
  int lead = 0,
}) => GoodDayEvent(
  id: 'event_example',
  title: '开会',
  notes: '带上笔记\n准备资料',
  startsAt: start ?? DateTime(2026, 10, 12, 10),
  repeat: repeat,
  reminderMinutes: lead,
);

void main() {
  test(
    'one-off fires at the chosen lead time and stops after acknowledgement',
    () {
      final item = event(lead: 10);
      expect(item.dueOccurrence(DateTime(2026, 10, 12, 9, 49, 59)), isNull);
      expect(item.dueOccurrence(DateTime(2026, 10, 12, 9, 50)), item.startsAt);
      final handled = item.resolve(item.startsAt);
      expect(handled.enabled, isFalse);
      expect(handled.dueOccurrence(DateTime(2026, 10, 13)), isNull);
    },
  );

  test(
    'daily recurrences survive midnight and collapse a long missed interval',
    () {
      final item = event(
        repeat: EventRepeat.daily,
        start: DateTime(2026, 10, 12, 0, 5),
        lead: 10,
      );
      expect(
        item.dueOccurrence(DateTime(2026, 10, 11, 23, 55)),
        DateTime(2026, 10, 12, 0, 5),
      );
      final handled = item.resolve(item.startsAt);
      expect(handled.dueOccurrence(DateTime(2026, 10, 12, 0, 6)), isNull);
      expect(
        handled.dueOccurrence(DateTime(2026, 11, 1, 12)),
        DateTime(2026, 11, 1, 0, 5),
      );
      expect(
        handled.nextReminderAt(DateTime(2026, 10, 12, 1)),
        DateTime(2026, 10, 12, 23, 55),
      );
    },
  );

  test('workdays skip weekends, including a weekend starting date', () {
    final friday = event(
      repeat: EventRepeat.weekdays,
      start: DateTime(2026, 10, 9, 10),
    );
    expect(
      friday.resolve(friday.startsAt).dueOccurrence(DateTime(2026, 10, 11, 12)),
      isNull,
    );
    expect(
      friday.nextOccurrenceAfter(friday.startsAt),
      DateTime(2026, 10, 12, 10),
    );
    final sunday = event(
      repeat: EventRepeat.weekdays,
      start: DateTime(2026, 10, 11, 10),
    );
    expect(sunday.dueOccurrence(DateTime(2026, 10, 11, 12)), isNull);
    expect(
      sunday.nextReminderAt(DateTime(2026, 10, 11, 12)),
      DateTime(2026, 10, 12, 10),
    );
  });

  test('weekly repeats on the selected weekday across a year boundary', () {
    final item = event(
      repeat: EventRepeat.weekly,
      start: DateTime(2026, 12, 28, 10),
    );
    expect(item.nextOccurrenceAfter(item.startsAt), DateTime(2027, 1, 4, 10));
    expect(item.dueOccurrence(DateTime(2027, 1, 3, 12)), item.startsAt);
    expect(
      item.resolve(item.startsAt).dueOccurrence(DateTime(2027, 1, 4, 10)),
      DateTime(2027, 1, 4, 10),
    );
  });

  test(
    'monthly day 31 clamps to month end without drifting in later months',
    () {
      final item = event(
        repeat: EventRepeat.monthly,
        start: DateTime(2028, 1, 31, 10),
      );
      expect(
        item.nextOccurrenceAfter(item.startsAt),
        DateTime(2028, 2, 29, 10),
      );
      expect(
        item.nextOccurrenceAfter(DateTime(2028, 2, 29, 10)),
        DateTime(2028, 3, 31, 10),
      );
      expect(
        item.latestOccurrenceAtOrBefore(DateTime(2028, 3, 30, 12)),
        DateTime(2028, 2, 29, 10),
      );
      expect(
        item.latestOccurrenceAtOrBefore(DateTime(2028, 4, 30, 10)),
        DateTime(2028, 4, 30, 10),
      );
    },
  );

  test('snooze persists independently of occurrence time and a paused event cannot fire', () {
    final item = event()
        .pending(DateTime(2026, 10, 12, 10))
        .resolve(
          DateTime(2026, 10, 12, 10),
          snoozeUntil: DateTime(2026, 10, 12, 10, 10),
        );
    final restored = GoodDayEvent.fromMarkdown(item.toMarkdown());
    expect(restored.notes, '带上笔记\n准备资料');
    expect(restored.dueOccurrence(DateTime(2026, 10, 12, 10, 9)), isNull);
    expect(
      restored.dueOccurrence(DateTime(2026, 10, 12, 10, 10)),
      restored.startsAt,
    );
    final paused = restored.edit(
      title: restored.title,
      notes: restored.notes,
      startsAt: restored.startsAt,
      repeat: restored.repeat,
      reminderMinutes: 0,
      enabled: false,
    );
    expect(paused.snoozedUntil, isNull);
    expect(paused.dueOccurrence(DateTime(2026, 10, 13)), isNull);
  });

  test(
    'changing a schedule resets acknowledgement, changing notes does not',
    () {
      final handled = event(repeat: EventRepeat.daily)
          .resolve(DateTime(2026, 10, 12, 10));
      GoodDayEvent edited(DateTime time) => handled.edit(
        title: '开会改名',
        notes: '',
        startsAt: time,
        repeat: handled.repeat,
        reminderMinutes: 0,
        enabled: true,
      );
      expect(edited(handled.startsAt).handledThrough, handled.startsAt);
      expect(edited(DateTime(2026, 10, 12, 11)).handledThrough, isNull);
    },
  );

  group('durable event storage', () {
    late Directory vault;
    late VaultRepository store;
    late DateTime now;
    setUp(() async {
      vault = await Directory.systemTemp.createTemp('good_day_events_');
      now = DateTime(2026, 10, 12, 9, 50);
      store = VaultRepository(vault, clock: () => now);
      await store.initialize();
    });
    tearDown(() async => vault.delete(recursive: true));
    Future<GoodDayEvent> create({EventRepeat repeat = EventRepeat.once}) =>
        store.saveEvent(
          GoodDayEvent(
            id: '',
            title: '测试提醒',
            startsAt: DateTime(2026, 10, 12, 10),
            repeat: repeat,
            reminderMinutes: 10,
          ),
        );

    test(
      'prepared reminder replays after restart, handled reminder never repeats',
      () async {
        final saved = await create();
        final prepared = await store.prepareEventReminder(saved.id, now);
        expect(prepared!.pendingOccurrence, saved.startsAt);
        store = VaultRepository(vault, clock: () => now);
        expect(
          (await store.loadEvents()).single.pendingOccurrence,
          saved.startsAt,
        );
        await store.resolveEventReminder(saved.id, saved.startsAt);
        store = VaultRepository(vault, clock: () => now);
        expect(await store.prepareEventReminder(saved.id, now), isNull);
        expect((await store.loadEvents()).single.enabled, isFalse);
      },
    );

    test(
      'snooze survives restart and acknowledgement failure leaves it retryable',
      () async {
        final saved = await create();
        await store.prepareEventReminder(saved.id, now);
        await store.resolveEventReminder(
          saved.id,
          saved.startsAt,
          snoozeUntil: now.add(const Duration(minutes: 5)),
        );
        store = VaultRepository(vault, clock: () => now);
        expect(await store.prepareEventReminder(saved.id, now), isNull);
        now = now.add(const Duration(minutes: 5));
        expect(await store.prepareEventReminder(saved.id, now), isNotNull);
        final file = File('${store.eventsDirectory.path}/${saved.id}.md');
        if (Platform.isWindows) {
          expect((await Process.run('attrib', ['+R', file.path])).exitCode, 0);
          try {
            await expectLater(
              store.resolveEventReminder(saved.id, saved.startsAt),
              throwsA(isA<FileSystemException>()),
            );
            expect(
              (await store.loadEvents()).single.pendingOccurrence,
              saved.startsAt,
            );
          } finally {
            await Process.run('attrib', ['-R', file.path]);
          }
        }
        await store.resolveEventReminder(saved.id, saved.startsAt);
        expect((await store.loadEvents()).single.dueOccurrence(now), isNull);
      },
    );

    test(
      'event backup and migration preserve schedules and reminder state',
      () async {
        final saved = await create(repeat: EventRepeat.daily);
        await store.prepareEventReminder(saved.id, now);
        await store.resolveEventReminder(
          saved.id,
          saved.startsAt,
          snoozeUntil: now.add(const Duration(minutes: 5)),
        );
        final snapshot = await store.createBackup();
        expect(snapshot.files, contains('Events/${saved.id}.md'));
        final target = await Directory.systemTemp.createTemp(
          'good_day_events_migration_',
        );
        try {
          await store.copyDataTo(target);
          final copied = VaultRepository(target, clock: () => now);
          expect(await copied.hasVaultData(), isTrue);
          expect(
            (await copied.loadEvents()).single.snoozedUntil,
            now.add(const Duration(minutes: 5)),
          );
          await store.deleteEvent(saved);
          expect(await store.loadEvents(), isEmpty);
          await store.restoreBackup(snapshot.id);
          expect(
            (await store.loadEvents()).single.snoozedUntil,
            now.add(const Duration(minutes: 5)),
          );
        } finally {
          await target.delete(recursive: true);
        }
      },
    );

    test(
      'delete cancels reminders and trash restore deliberately pauses them',
      () async {
        final saved = await create();
        await store.prepareEventReminder(saved.id, now);
        await store.deleteEvent(saved);
        expect(await store.prepareEventReminder(saved.id, now), isNull);
        final trashed = (await store.loadTrash()).single;
        expect(trashed.type, TrashItemType.event);
        await store.restoreTrashItem(trashed);
        expect((await store.loadEvents()).single.enabled, isFalse);
        await store.deleteEvent((await store.loadEvents()).single);
        await store.emptyTrash();
        expect(await store.loadTrash(), isEmpty);
      },
    );

    test('invalid event files are preserved and reported', () async {
      final file = File('${store.eventsDirectory.path}/bad.md');
      await file.writeAsString('invalid event');
      expect(await store.loadEvents(), isEmpty);
      expect(
        store.unreadableFiles.map((path) => path.replaceAll('\\', '/')),
        contains(file.path.replaceAll('\\', '/')),
      );
      expect(await file.readAsString(), 'invalid event');
    });

    test(
      'a disabled or removed event cannot be claimed from a stale list',
      () async {
        final saved = await create();
        await store.saveEvent(
          saved.edit(
            title: saved.title,
            notes: '',
            startsAt: saved.startsAt,
            repeat: saved.repeat,
            reminderMinutes: saved.reminderMinutes,
            enabled: false,
          ),
        );
        expect(await store.prepareEventReminder(saved.id, now), isNull);
        await store.deleteEvent(saved);
        expect(await store.prepareEventReminder(saved.id, now), isNull);
      },
    );

    test('service serializes simultaneous ticks and replays after an interrupted popup', () async {
      await create();
      var shown = 0;
      final gate = Completer<void>();
      final errors = <Object>[];
      final service = EventReminderService(
        repository: () => store,
        clock: () => now,
        canPresent: () => true,
        onChanged: () async {},
        onError: errors.add,
        present: (event, occurrence, resolve) async {
          shown++;
          await gate.future;
        },
      );
      final first = service.check();
      while (shown == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await service.check();
      expect(shown, 1);
      gate.complete();
      await first;
      service.dispose();
      final restarted = EventReminderService(
        repository: () => store,
        clock: () => now,
        canPresent: () => true,
        onChanged: () async {},
        onError: errors.add,
        present: (event, occurrence, resolve) async {
          shown++;
          await resolve(null);
        },
      );
      await restarted.check();
      await restarted.check();
      restarted.dispose();
      expect(shown, 2);
      expect(errors, isEmpty);
    });

    test('service waits for editors and handles refresh failures after a durable answer', () async {
      await create();
      var allowed = false;
      var shown = 0;
      final errors = <Object>[];
      final service = EventReminderService(
        repository: () => store,
        clock: () => now,
        canPresent: () => allowed,
        onChanged: () async => throw StateError('list refresh failed'),
        onError: errors.add,
        present: (event, occurrence, resolve) async {
          shown++;
          await resolve(null);
        },
      );
      await service.check();
      expect(shown, 0);
      allowed = true;
      await service.check();
      await service.check();
      service.dispose();
      expect(shown, 1);
      expect(errors.length, 1);
      expect((await store.loadEvents()).single.enabled, isFalse);
    });
  });
}
