import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:good_day/data/vault_repository.dart';
import 'package:good_day/event_reminder_service.dart';
import 'package:good_day/models/good_day_event.dart';
import 'package:good_day/models/good_day_task.dart';

void main() {
  late Directory vault;
  late VaultRepository repository;
  late DateTime now;
  setUp(() async {
    vault = await Directory.systemTemp.createTemp('good_day_task_reminders_');
    now = DateTime(2026, 10, 12, 9);
    repository = VaultRepository(vault, clock: () => now);
    await repository.initialize();
  });
  tearDown(() async => vault.delete(recursive: true));
  Future<GoodDayTask> create({EventRepeat repeat = EventRepeat.once}) async {
    var task = await repository.addTask('刷三套试卷');
    task = await repository.updateTaskDetails(
      task,
      title: task.title,
      notes: '整理错题',
    );
    return repository.saveTaskOptions(
      task: task,
      repeat: repeat,
      reminderAt: DateTime(2026, 10, 12, 10),
    );
  }

  test('old tasks remain readable and reminder options preserve title, notes and date', () async {
    final task = await create();
    final saved = (await repository.loadTasks()).single;
    expect(saved.title, '刷三套试卷');
    expect(saved.notes, '整理错题');
    expect(saved.scheduledDate, DateTime(2026, 10, 12));
    expect(saved.reminder!.startsAt, DateTime(2026, 10, 12, 10));
    expect(await repository.loadEvents(), isEmpty);
    final oldText = task
        .toMarkdown()
        .split('\n')
        .where((line) => !line.startsWith('reminder:'))
        .join('\n');
    expect(GoodDayTask.fromMarkdown(oldText).reminder, isNull);
    final disabled = await repository.saveTaskOptions(
      task: task,
      repeat: task.repeat,
      reminderAt: null,
    );
    expect(disabled.reminder, isNull);
    expect(disabled.title, task.title);
  });

  test(
    'task snooze survives restart and acknowledgement does not complete task',
    () async {
      final task = await create();
      now = DateTime(2026, 10, 12, 10);
      final prepared = await repository.prepareTaskReminder(task.id, now);
      expect(prepared!.pendingOccurrence, now);
      await repository.resolveTaskReminder(
        task.id,
        now,
        snoozeUntil: now.add(const Duration(minutes: 5)),
      );
      repository = VaultRepository(vault, clock: () => now);
      expect(await repository.prepareTaskReminder(task.id, now), isNull);
      now = now.add(const Duration(minutes: 5));
      expect(await repository.prepareTaskReminder(task.id, now), isNotNull);
      await repository.resolveTaskReminder(task.id, prepared.startsAt);
      final saved = (await repository.loadTasks()).single;
      expect(saved.isCompleted, isFalse);
      expect(saved.reminder!.enabled, isFalse);
      expect(await repository.prepareTaskReminder(task.id, now), isNull);
      final edited = await repository.updateTaskDetails(
        saved,
        title: '改名',
        notes: '新增备注',
      );
      expect(edited.activeReminder!.handledThrough, prepared.startsAt);
    },
  );

  test(
    'completion and deletion suppress reminders and restoration is paused',
    () async {
      final task = await create();
      now = DateTime(2026, 10, 12, 10);
      final completed = await repository.setCompleted(task, true);
      expect(await repository.prepareTaskReminder(task.id, now), isNull);
      await repository.setCompleted(completed, false);
      await repository.deleteTask(task);
      expect(await repository.prepareTaskReminder(task.id, now), isNull);
      await repository.restoreTrashItem((await repository.loadTrash()).single);
      expect(await repository.prepareTaskReminder(task.id, now), isNull);
      expect(
        (await repository.loadTasks()).single.reminder!.startsAt,
        DateTime(2026, 10, 12, 10),
      );
    },
  );

  test('next repeat inherits time; edits and disabling reach already generated future records', () async {
    var task = await create(repeat: EventRepeat.daily);
    await repository.setCompleted(task, true);
    task = await repository.setCompleted(task, false);
    task = await repository.saveTaskOptions(
      task: task,
      repeat: EventRepeat.daily,
      reminderAt: DateTime(2026, 10, 12, 11),
    );
    final future = (await repository.loadTasks()).singleWhere(
      (entry) => entry.id != task.id,
    );
    expect(future.reminder!.startsAt, DateTime(2026, 10, 13, 11));
    expect(future.reminder!.id, 'task_${future.id}');
    await repository.saveTaskOptions(
      task: task,
      repeat: EventRepeat.daily,
      reminderAt: null,
    );
    expect(
      (await repository.loadTasks()).every((entry) => entry.reminder == null),
      isTrue,
    );
    now = DateTime(2026, 10, 14, 12);
    expect((await repository.loadTasks()).last.reminder, isNull);
  });

  test('weekday repeat aligns reminder to first allowed day', () async {
    now = DateTime(2026, 10, 11, 9);
    final task = await repository.addTask('周末安排工作日');
    final saved = await repository.saveTaskOptions(
      task: task,
      repeat: EventRepeat.weekdays,
      reminderAt: DateTime(2026, 10, 11, 10),
    );
    expect(saved.scheduledDate, DateTime(2026, 10, 12));
    expect(saved.reminder!.startsAt, DateTime(2026, 10, 12, 10));
  });

  test(
    'weekend tasks generate Saturday and Sunday with inherited reminder',
    () async {
      now = DateTime(2026, 10, 9, 9);
      final task = await repository.addTask('周末刷题');
      final saturday = await repository.saveTaskOptions(
        task: task,
        repeat: EventRepeat.weekends,
        reminderAt: DateTime(2026, 10, 9, 10),
      );
      expect(saturday.scheduledDate, DateTime(2026, 10, 10));
      expect(saturday.reminder!.startsAt, DateTime(2026, 10, 10, 10));
      await repository.setCompleted(saturday, true);
      final sunday = (await repository.loadTasks()).singleWhere(
        (item) => !item.isCompleted,
      );
      expect(sunday.scheduledDate, DateTime(2026, 10, 11));
      expect(sunday.reminder!.startsAt, DateTime(2026, 10, 11, 10));
      await repository.setCompleted(sunday, true);
      final next = (await repository.loadTasks()).singleWhere(
        (item) => !item.isCompleted,
      );
      expect(next.scheduledDate, DateTime(2026, 10, 17));
      expect(next.reminder!.startsAt, DateTime(2026, 10, 17, 10));
    },
  );

  test(
    'editing later occurrence keeps reminder clock instead of drifting a day',
    () async {
      final first = await create(repeat: EventRepeat.daily);
      await repository.setCompleted(first, true);
      now = DateTime(2026, 10, 13, 9);
      var current = (await repository.loadTasks()).singleWhere(
        (task) => !task.isCompleted,
      );
      current = await repository.updateTaskDetails(
        current,
        title: '新名称',
        notes: '新备注',
      );
      await repository.setCompleted(current, true);
      final next = (await repository.loadTasks()).singleWhere(
        (task) => !task.isCompleted,
      );
      expect(next.reminder!.startsAt, DateTime(2026, 10, 14, 10));
      expect(next.activeReminder!.title, '新名称');
    },
  );

  test('deleting latest repeat does not resurrect an older reminder', () async {
    await create(repeat: EventRepeat.daily);
    now = DateTime(2026, 10, 13, 12);
    final tasks = await repository.loadTasks();
    final current = tasks.singleWhere(
      (task) => isSameDay(task.scheduledDate, now),
    );
    await repository.deleteTask(current);
    var shown = 0;
    final errors = <Object>[];
    final service = EventReminderService(
      repository: () => repository,
      clock: () => now,
      canPresent: () => true,
      onChanged: () async {},
      onError: errors.add,
      present: (event, occurrence, resolve) async {
        shown++;
      },
    );
    await service.check();
    service.dispose();
    expect(shown, 0);
    expect(errors, isEmpty);
  });

  test('failed series write rolls reminder options back instead of partially saving', () async {
    if (!Platform.isWindows) return;
    final task = await create(repeat: EventRepeat.daily);
    final file = File(
      '${repository.taskSeriesDirectory.path}/${task.seriesId}.md',
    );
    final original = await file.readAsString();
    expect((await Process.run('attrib', ['+R', file.path])).exitCode, 0);
    try {
      await expectLater(
        repository.saveTaskOptions(
          task: task,
          repeat: task.repeat,
          reminderAt: DateTime(2026, 10, 12, 11),
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(
        (await repository.loadTaskReminders()).single.reminder!.startsAt,
        task.reminder!.startsAt,
      );
      expect(await file.readAsString(), original);
    } finally {
      await Process.run('attrib', ['-R', file.path]);
    }
  });

  test(
    'backup, restore and moving Vault retain pending task reminders',
    () async {
      final task = await create();
      now = DateTime(2026, 10, 12, 10);
      await repository.prepareTaskReminder(task.id, now);
      final backup = await repository.createBackup();
      await repository.resolveTaskReminder(task.id, now);
      await repository.restoreBackup(backup.id);
      expect(
        (await repository.loadTasks()).single.reminder!.pendingOccurrence,
        now,
      );
      final target = await Directory.systemTemp.createTemp(
        'good_day_reminder_move_',
      );
      try {
        await repository.copyDataTo(target);
        final copied = VaultRepository(target, clock: () => now);
        expect(
          (await copied.loadTasks()).single.reminder!.pendingOccurrence,
          now,
        );
      } finally {
        await target.delete(recursive: true);
      }
    },
  );

  test(
    'service retains legacy events and claims only latest due repeat',
    () async {
      await create(repeat: EventRepeat.daily);
      now = DateTime(2026, 10, 13, 12);
      await repository.loadTasks();
      await repository.saveEvent(
        GoodDayEvent(
          id: '',
          title: '旧独立提醒',
          startsAt: DateTime(2026, 10, 13, 11),
        ),
      );
      final titles = <String>[];
      final errors = <Object>[];
      final service = EventReminderService(
        repository: () => repository,
        clock: () => now,
        canPresent: () => true,
        onChanged: () async {},
        onError: errors.add,
        present: (event, occurrence, resolve) async {
          titles.add(event.title);
          await resolve(null);
        },
      );
      await service.check();
      await service.check();
      await service.check();
      service.dispose();
      expect(titles, ['刷三套试卷', '旧独立提醒']);
      expect(errors, isEmpty);
      expect(
        (await repository.loadTasks()).every((task) => !task.isCompleted),
        isTrue,
      );
    },
  );

  test(
    'failed acknowledgement retains pending reminder and allows retry',
    () async {
      if (!Platform.isWindows) return;
      final task = await create();
      now = DateTime(2026, 10, 12, 10);
      await repository.prepareTaskReminder(task.id, now);
      final file = File('${repository.tasksDirectory.path}/${task.id}.md');
      expect((await Process.run('attrib', ['+R', file.path])).exitCode, 0);
      try {
        await expectLater(
          repository.resolveTaskReminder(task.id, now),
          throwsA(isA<FileSystemException>()),
        );
        expect(
          (await repository.loadTaskReminders())
              .single
              .reminder!
              .pendingOccurrence,
          now,
        );
      } finally {
        await Process.run('attrib', ['-R', file.path]);
      }
      await repository.resolveTaskReminder(task.id, now);
      expect(await repository.prepareTaskReminder(task.id, now), isNull);
    },
  );
}
