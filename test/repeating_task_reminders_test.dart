import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:good_day/data/vault_repository.dart';
import 'package:good_day/event_reminder_service.dart';
import 'package:good_day/models/good_day_event.dart';
import 'package:good_day/models/good_day_task.dart';

void main() {
  late Directory vault;
  late DateTime now;
  late VaultRepository repository;
  setUp(() async {
    vault = await Directory.systemTemp.createTemp('good_day_interval_');
    now = DateTime(2026, 10, 12, 10);
    repository = VaultRepository(vault, clock: () => now);
    await repository.initialize();
  });
  tearDown(() async => vault.delete(recursive: true));

  for (final period in [
    TaskPeriod.day,
    TaskPeriod.week,
    TaskPeriod.month,
    TaskPeriod.year,
  ]) {
    test(
      '$period reminders reject timestamps and intervals outside their calendar scope',
      () async {
        final task = await repository.addPeriodTask('刷题', period);
        final end = period.end(now);
        final span = end.difference(period.start(now)).inMinutes;
        await expectLater(
          repository.saveTaskOptions(
            task: task,
            repeat: EventRepeat.once,
            reminderAt: end,
            reminderIntervalMinutes: 5,
          ),
          throwsFormatException,
        );
        await expectLater(
          repository.saveTaskOptions(
            task: task,
            repeat: EventRepeat.once,
            reminderAt: now.add(const Duration(minutes: 5)),
            reminderIntervalMinutes: span,
          ),
          throwsFormatException,
        );
        final saved = await repository.saveTaskOptions(
          task: task,
          repeat: EventRepeat.once,
          reminderAt: now.add(const Duration(minutes: 5)),
          reminderIntervalMinutes: span - 1,
        );
        expect(saved.reminder!.expiresAt, end);
        expect(saved.reminder!.intervalMinutes, span - 1);
        expect(
          GoodDayTask.fromMarkdown(saved.toMarkdown())
              .reminder!
              .intervalMinutes,
          span - 1,
        );
      },
    );
  }

  test('acknowledgement continues repeating after restart; missed intervals produce one reminder', () async {
    final task = await repository.saveTaskOptions(
      task: await repository.addTask('复习'),
      repeat: EventRepeat.once,
      reminderAt: now.add(const Duration(minutes: 5)),
      reminderIntervalMinutes: 5,
    );
    var shown = 0;
    final service = EventReminderService(
      repository: () => repository,
      clock: () => now,
      canPresent: () => true,
      present: (_, _, resolve) async {
        shown++;
        await resolve(null);
      },
      onChanged: () async {},
      onError: (error) => fail('$error'),
    );
    addTearDown(service.dispose);
    now = DateTime(2026, 10, 12, 10, 5);
    await service.check();
    expect(shown, 1);
    final acknowledged = (await repository.loadTasks()).single;
    expect(acknowledged.isCompleted, false);
    expect(acknowledged.reminder!.enabled, true);
    expect(acknowledged.reminder!.intervalMinutes, 5);
    await service.check();
    expect(shown, 1);
    repository = VaultRepository(vault, clock: () => now);
    now = DateTime(2026, 10, 12, 10, 47);
    await service.check();
    expect(shown, 2);
    expect(
      (await repository.loadTasks()).single.reminder!.handledThrough,
      DateTime(2026, 10, 12, 10, 45),
    );
    await service.check();
    expect(shown, 2);
    await repository.setCompleted(task, true);
    now = DateTime(2026, 10, 12, 10, 50);
    await service.check();
    expect(shown, 2);
  });

  test(
    'snooze, disabling, restoration, and calendar expiry retain safe behavior',
    () async {
      var task = await repository.saveTaskOptions(
        task: await repository.addTask('复习'),
        repeat: EventRepeat.once,
        reminderAt: DateTime(2026, 10, 12, 23, 50),
        reminderIntervalMinutes: 5,
      );
      now = DateTime(2026, 10, 12, 23, 50);
      final claimed = (await repository.prepareTaskReminder(task.id, now))!;
      expect(claimed.intervalMinutes, 5);
      await repository.resolveTaskReminder(
        task.id,
        claimed.pendingOccurrence!,
        snoozeUntil: now.add(const Duration(minutes: 15)),
      );
      expect((await repository.loadTasks()).single.reminder!.enabled, false);
      now = DateTime(2026, 10, 13, 0, 5);
      expect(await repository.prepareTaskReminder(task.id, now), isNull);
      await repository.deleteTask(task);
      await repository.restoreTrashItem((await repository.loadTrash()).single);
      expect(
        (await repository.loadTasks()).single.reminder!.intervalMinutes,
        5,
      );
      expect(await repository.prepareTaskReminder(task.id, now), isNull);
      task = await repository.saveTaskOptions(
        task: task,
        repeat: EventRepeat.once,
        reminderAt: null,
      );
      expect(task.reminder, isNull);
    },
  );

  test('monthly reminder keeps its selected day and clamps February in the next task', () async {
    now = DateTime(2027, 1, 15, 9);
    final task = await repository.saveTaskOptions(
      task: await repository.addPeriodTask('整本题', TaskPeriod.month),
      repeat: EventRepeat.monthly,
      reminderAt: DateTime(2027, 1, 31, 10),
      reminderIntervalMinutes: 60,
    );
    await repository.setCompleted(task, true);
    final next = (await repository.loadTasks()).singleWhere(
      (entry) => !entry.isCompleted,
    );
    expect(next.reminder!.startsAt, DateTime(2027, 2, 28, 10));
    expect(next.reminder!.expiresAt, DateTime(2027, 3, 1));
    expect(next.reminder!.intervalMinutes, 60);
    now = DateTime(2027, 2, 15, 9);
    final edited = await repository.updateTaskDetails(
      next,
      title: '整本题改名',
      notes: '继续刷题',
    );
    await repository.setCompleted(edited, true);
    final march = (await repository.loadTasks()).singleWhere(
      (entry) => !entry.isCompleted,
    );
    expect(march.reminder!.startsAt, DateTime(2027, 3, 31, 10));
  });

  test('malformed intervals are rejected; old reminders without interval fields still load', () {
    final event = GoodDayEvent(id: 'task_test', title: '阅读', startsAt: now);
    final old = event
        .toMarkdown()
        .replaceAll('"intervalMinutes":0,', '')
        .replaceAll('"expiresAt":null,', '');
    expect(GoodDayEvent.fromMarkdown(old).intervalMinutes, 0);
    final invalid = event.toMarkdown().replaceAll(
      '"intervalMinutes":0',
      '"intervalMinutes":5',
    );
    expect(() => GoodDayEvent.fromMarkdown(invalid), throwsFormatException);
  });
}
