import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:good_day/data/vault_repository.dart';
import 'package:good_day/models/good_day_task.dart';
import 'package:good_day/models/repeat_schedule.dart';

void main() {
  late Directory vault;
  late VaultRepository repository;
  late DateTime now;
  setUp(() async {
    vault = await Directory.systemTemp.createTemp('good_day_schedules_');
    now = DateTime(2026, 10, 12, 9);
    repository = VaultRepository(vault, clock: () => now);
    await repository.initialize();
  });
  tearDown(() async => vault.delete(recursive: true));
  Future<GoodDayTask> create({
    EventRepeat repeat = EventRepeat.once,
    DateTime? date,
  }) => repository.saveScheduledTask(
    title: '读书',
    notes: '二十页',
    date: date ?? now,
    repeat: repeat,
  );

  Future<List<GoodDayTask>> todayTasks() async => (await repository.loadTasks())
      .where(
        (task) =>
            isSameDay(task.scheduledDate, now) ||
            (task.completedAt != null && isSameDay(task.completedAt!, now)),
      )
      .toList();
  test(
    'future tasks stay out of today and enter today on the scheduled date',
    () async {
      final task = await create(date: DateTime(2026, 10, 14));
      expect(await todayTasks(), isEmpty);
      now = DateTime(2026, 10, 14, 9);
      expect((await todayTasks()).single.id, task.id);
    },
  );
  test(
    'overdue one-off keeps its assignment and enters the waiting list',
    () async {
      final task = await create();
      now = DateTime(2026, 10, 15, 9);
      final rolled = (await repository.loadTasks()).single;
      expect(rolled.originalScheduledDate, DateTime(2026, 10, 12));
      expect(isSameDay(rolled.scheduledDate, DateTime(2026, 10, 12)), isTrue);
      expect(rolled.isWaitingForSchedule(now), isTrue);
      final completed = await repository.setCompleted(task, true);
      expect(completed.originalScheduledDate, DateTime(2026, 10, 12));
      expect(GoodDayTask.fromMarkdown(completed.toMarkdown()).completedAt, now);
    },
  );
  test(
    'completion generates exactly one future record and carries reset subtasks',
    () async {
      var task = await create(repeat: EventRepeat.daily);
      task = await repository.addSubtask(task, '做笔记');
      task = await repository.updateSubtask(
        task,
        task.subtasks.single.id,
        isCompleted: true,
      );
      task = await repository.updateTaskDetails(
        task,
        title: '阅读书籍',
        notes: '新备注',
      );
      await repository.setCompleted(task, true);
      await repository.setCompleted(task, true);
      final tasks = await repository.loadTasks();
      expect(tasks, hasLength(2));
      final next = tasks.singleWhere((entry) => !entry.isCompleted);
      expect(next.scheduledDate, DateTime(2026, 10, 13));
      expect(next.title, '阅读书籍');
      expect(next.notes, '新备注');
      expect(next.subtasks.single.isCompleted, isFalse);
      expect(next.seriesId, task.seriesId);
      await repository.setCompleted(task, false);
      expect(await repository.loadTasks(), hasLength(2));
    },
  );
  test(
    'missed repeats keep old record and generate only latest due after restart',
    () async {
      final task = await create(repeat: EventRepeat.daily);
      now = DateTime(2026, 10, 18, 9);
      repository = VaultRepository(vault, clock: () => now);
      await Future.wait([repository.loadTasks(), repository.loadTasks()]);
      final tasks = await repository.loadTasks();
      expect(tasks, hasLength(2));
      expect(
        tasks.singleWhere((entry) => entry.id == task.id).scheduledDate,
        DateTime(2026, 10, 12),
      );
      expect(
        tasks.map((entry) => entry.scheduledDate),
        contains(DateTime(2026, 10, 18)),
      );
      expect(await todayTasks(), hasLength(1));
    },
  );
  test('deleting and clearing occurrence never regenerates it but series continues', () async {
    final task = await create(repeat: EventRepeat.daily);
    await repository.deleteTask(task);
    await repository.emptyTrash();
    expect(await repository.loadTasks(), isEmpty);
    now = DateTime(2026, 10, 13, 9);
    expect(await repository.loadTasks(), hasLength(1));
  });
  test(
    'ending repeat archives future record but preserves completed history',
    () async {
      final task = await create(repeat: EventRepeat.daily);
      await repository.setCompleted(task, true);
      await repository.stopTaskSeries(task.seriesId!);
      expect((await repository.loadTasks()).single.isCompleted, isTrue);
      expect(await repository.loadTrash(), hasLength(1));
      now = DateTime(2026, 10, 20, 9);
      expect(await todayTasks(), isEmpty);
    },
  );
  test(
    'monthly clamps to February then returns to original day in March',
    () async {
      now = DateTime(2026, 1, 31, 9);
      final task = await create(repeat: EventRepeat.monthly);
      await repository.setCompleted(task, true);
      now = DateTime(2026, 2, 28, 9);
      final february = (await todayTasks()).single;
      await repository.setCompleted(february, true);
      expect(
        (await repository.loadTasks())
            .where((entry) => !entry.isCompleted)
            .single
            .scheduledDate,
        DateTime(2026, 3, 31),
      );
    },
  );
  test('workdays begin Monday if scheduled for Saturday', () async {
    final task = await create(
      repeat: EventRepeat.weekdays,
      date: DateTime(2026, 10, 17),
    );
    expect(task.scheduledDate, DateTime(2026, 10, 19));
  });
  test(
    'changing repeat ends old series and does not resurrect old future tasks',
    () async {
      final original = await create(repeat: EventRepeat.daily);
      await repository.setCompleted(original, true);
      final next = (await repository.loadTasks()).singleWhere(
        (entry) => !entry.isCompleted,
      );
      final updated = await repository.saveScheduledTask(
        task: next,
        title: '新安排',
        notes: '',
        date: DateTime(2026, 10, 15),
        repeat: EventRepeat.weekly,
      );
      final series = await repository.loadTaskSeries();
      expect(
        series.singleWhere((entry) => entry.id == original.seriesId).enabled,
        isFalse,
      );
      expect(
        series.singleWhere((entry) => entry.id == updated.seriesId).enabled,
        isTrue,
      );
      now = DateTime(2026, 10, 16, 9);
      expect(await repository.loadTasks(), hasLength(2));
      await expectLater(
        repository.saveScheduledTask(
          task: original,
          title: '旧任务',
          notes: '',
          date: now,
          repeat: EventRepeat.daily,
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'failed series creation rolls back task and allows a clean retry',
    () async {
      final task = await create();
      await repository.taskSeriesDirectory.delete();
      await File(repository.taskSeriesDirectory.path).writeAsString('故障占位');
      await expectLater(
        repository.saveScheduledTask(
          task: task,
          title: '新标题',
          notes: '',
          date: now,
          repeat: EventRepeat.daily,
        ),
        throwsA(isA<FileSystemException>()),
      );
      final saved = GoodDayTask.fromMarkdown(
        await File('${repository.tasksDirectory.path}/${task.id}.md')
            .readAsString(),
      );
      expect(saved.title, task.title);
      expect(saved.seriesId, isNull);
      await File(repository.taskSeriesDirectory.path).delete();
      final retry = await repository.saveScheduledTask(
        task: task,
        title: '重试',
        notes: '',
        date: now,
        repeat: EventRepeat.daily,
      );
      expect((await repository.loadTasks()).single.seriesId, retry.seriesId);
      expect(await repository.loadTaskSeries(), hasLength(1));
    },
  );
  test(
    'series and metadata survive backup restore and data migration',
    () async {
      final task = await create(repeat: EventRepeat.weekly);
      final backup = await repository.createBackup();
      await repository.stopTaskSeries(task.seriesId!);
      await repository.restoreBackup(backup.id);
      expect((await repository.loadTaskSeries()).single.enabled, isTrue);
      final target = await Directory.systemTemp.createTemp(
        'good_day_migrated_',
      );
      addTearDown(() => target.delete(recursive: true));
      await repository.copyDataTo(target);
      final moved = VaultRepository(target, clock: () => now);
      expect((await moved.loadTasks()).single.repeat, EventRepeat.weekly);
      expect((await moved.loadTaskSeries()).single.id, task.seriesId);
    },
  );
}
