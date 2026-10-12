import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:good_day/data/vault_repository.dart';
import 'package:good_day/models/good_day_task.dart';
import 'package:good_day/models/good_day_event.dart';

void main() {
  GoodDayTask task(TaskPeriod period, DateTime date) => GoodDayTask(
    id: 'test',
    title: '刷题',
    createdAt: date,
    scheduledDate: date,
    period: period,
  );
  test('period labels show dates, ISO week ranges, month and year', () {
    final today = DateTime(2026, 10, 12);
    expect(TaskPeriod.day.dateLabel(today), '2026年10月12日 · 周一');
    expect(TaskPeriod.week.dateLabel(today), '2026年第42周 · 10月12日—10月18日');
    expect(TaskPeriod.month.dateLabel(today), '2026年10月');
    expect(TaskPeriod.year.dateLabel(today), '2026年');
    expect(
      TaskPeriod.week.dateLabel(DateTime(2027, 1, 1)),
      '2026年第53周 · 2026年12月28日—2027年1月3日',
    );
    expect(
      TaskPeriod.week.dateLabel(DateTime(2027, 1, 4)),
      '2027年第1周 · 1月4日—1月10日',
    );
  });

  test('calendar periods cross weeks, leap months and years correctly', () {
    expect(TaskPeriod.week.start(DateTime(2027, 1, 1)), DateTime(2026, 12, 28));
    expect(TaskPeriod.week.end(DateTime(2027, 1, 1)), DateTime(2027, 1, 4));
    expect(TaskPeriod.month.end(DateTime(2028, 2, 29)), DateTime(2028, 3, 1));
    expect(TaskPeriod.year.end(DateTime(2026, 12, 31)), DateTime(2027, 1, 1));
    for (final period in [
      TaskPeriod.day,
      TaskPeriod.week,
      TaskPeriod.month,
      TaskPeriod.year,
    ]) {
      final item = task(period, DateTime(2026, 12, 31));
      final end = period.end(item.scheduledDate);
      expect(
        item.isWaitingForSchedule(
          end.subtract(const Duration(microseconds: 1)),
        ),
        isFalse,
      );
      expect(item.appearsIn(TaskPeriod.backlog, end), isTrue);
      expect(item.appearsIn(period, end), isFalse);
    }
  });
  test(
    'ongoing records stay independent and completions aggregate upwards',
    () {
      final now = DateTime(2026, 10, 12, 10);
      for (final period in [
        TaskPeriod.day,
        TaskPeriod.week,
        TaskPeriod.month,
        TaskPeriod.year,
      ]) {
        final item = task(period, now);
        final complete = item.setCompleted(true, now);
        for (final view in [
          TaskPeriod.day,
          TaskPeriod.week,
          TaskPeriod.month,
          TaskPeriod.year,
        ]) {
          expect(item.appearsIn(view, now), period == view);
          expect(complete.appearsIn(view, now), period.index <= view.index);
        }
        expect(complete.appearsIn(TaskPeriod.backlog, now), isFalse);
      }
      final old = task(
        TaskPeriod.day,
        DateTime(2026, 10, 11),
      ).setCompleted(true, now);
      expect(old.appearsIn(TaskPeriod.day, now), isTrue);
      expect(old.appearsIn(TaskPeriod.day, DateTime(2026, 10, 13)), isFalse);
      expect(old.appearsIn(TaskPeriod.week, DateTime(2026, 10, 13)), isTrue);
      expect(old.appearsIn(TaskPeriod.week, DateTime(2026, 10, 19)), isFalse);
      expect(old.appearsIn(TaskPeriod.month, DateTime(2026, 10, 19)), isTrue);
    },
  );
  test(
    'period metadata is backwards compatible and rejects an invalid assignment',
    () {
      final item = task(TaskPeriod.month, DateTime(2026, 10, 12));
      expect(
        GoodDayTask.fromMarkdown(item.toMarkdown()).period,
        TaskPeriod.month,
      );
      expect(
        GoodDayTask.fromMarkdown(
          item.toMarkdown().replaceAll('period: month\n', ''),
        ).period,
        TaskPeriod.day,
      );
      final legacy = task(
        TaskPeriod.day,
        DateTime(2026, 10, 10),
      ).rollForward(DateTime(2026, 10, 12));
      final imported = GoodDayTask.fromMarkdown(
        legacy.toMarkdown().replaceAll('period: day\n', ''),
      );
      expect(imported.scheduledDate, DateTime(2026, 10, 10));
      expect(
        imported.appearsIn(TaskPeriod.backlog, DateTime(2026, 10, 12)),
        isTrue,
      );
      expect(
        GoodDayTask.fromMarkdown(legacy.toMarkdown()).scheduledDate,
        DateTime(2026, 10, 12),
      );
      expect(
        () => GoodDayTask.fromMarkdown(
          item.toMarkdown().replaceAll('period: month', 'period: backlog'),
        ),
        throwsFormatException,
      );
    },
  );

  late Directory directory;
  late VaultRepository repository;
  late DateTime now;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('goodday_period_');
    now = DateTime(2026, 10, 12, 9);
    repository = VaultRepository(directory, clock: () => now);
    await repository.initialize();
  });
  tearDown(() async => directory.delete(recursive: true));
  test('waiting tasks persist until manually reassigned, retaining original details', () async {
    var item = await repository.addPeriodTask('一整本试卷', TaskPeriod.week);
    item = await repository.updateTaskDetails(
      item,
      title: item.title,
      notes: '整理错题',
    );
    item = await repository.addSubtask(item, '第一套');
    item = await repository.saveTaskOptions(
      task: item,
      repeat: EventRepeat.once,
      reminderAt: now.add(const Duration(hours: 1)),
    );
    now = DateTime(2026, 10, 19, 11);
    item = (await repository.loadTasks()).single;
    expect(item.appearsIn(TaskPeriod.backlog, now), isTrue);
    final original = item.originalScheduledDate;
    item = await repository.rescheduleTaskPeriod(item, TaskPeriod.month);
    expect(item.period, TaskPeriod.month);
    expect(item.notes, '整理错题');
    expect(item.subtasks.single.title, '第一套');
    expect(item.originalScheduledDate, original);
    expect(item.appearsIn(TaskPeriod.month, now), isTrue);
    expect(item.appearsIn(TaskPeriod.backlog, now), isFalse);
    expect(item.reminder!.enabled, isFalse);
    final reopened = VaultRepository(directory, clock: () => now);
    expect((await reopened.loadTasks()).single.period, TaskPeriod.month);
    final snapshot = await repository.createBackup();
    await repository.rescheduleTaskPeriod(item, TaskPeriod.day);
    await repository.restoreBackup(snapshot.id);
    expect((await repository.loadTasks()).single.period, TaskPeriod.month);
  });
  test(
    'repeat regeneration and reassignment retain the selected period',
    () async {
      var item = await repository.addPeriodTask('刷套题', TaskPeriod.week);
      item = await repository.saveTaskOptions(
        task: item,
        repeat: EventRepeat.daily,
        reminderAt: now.add(const Duration(hours: 1)),
      );
      await repository.setCompleted(item, true);
      final next = (await repository.loadTasks()).singleWhere(
        (t) => !t.isCompleted,
      );
      expect(next.period, TaskPeriod.week);
      now = DateTime(2026, 10, 13, 9);
      final reassigned = await repository.rescheduleTaskPeriod(
        next,
        TaskPeriod.month,
      );
      await repository.setCompleted(reassigned, true);
      final following = (await repository.loadTasks()).singleWhere(
        (t) => !t.isCompleted,
      );
      expect(following.period, TaskPeriod.month);
      expect(following.reminder!.startsAt, DateTime(2026, 10, 14, 10));
    },
  );
  test('legacy automatic rollover does not shift a reminder by the old accumulated days', () async {
    final original = GoodDayTask(
      id: 'legacy',
      title: '旧任务',
      createdAt: DateTime(2026, 10, 10),
      scheduledDate: DateTime(2026, 10, 12),
      originalDate: DateTime(2026, 10, 10),
      reminder: GoodDayEvent(
        id: 'task_legacy',
        title: '旧任务',
        startsAt: DateTime(2026, 10, 12, 10),
      ),
    );
    await File('${repository.tasksDirectory.path}/legacy.md')
        .writeAsString(original.toMarkdown().replaceAll('period: day\n', ''));
    now = DateTime(2026, 10, 19, 11);
    final old = (await repository.loadTasks()).single;
    expect(old.appearsIn(TaskPeriod.backlog, now), isTrue);
    final moved = await repository.rescheduleTaskPeriod(old, TaskPeriod.week);
    expect(moved.reminder!.startsAt, DateTime(2026, 10, 19, 10));
    expect(moved.reminder!.enabled, isFalse);
    expect(moved.originalScheduledDate, DateTime(2026, 10, 10));
  });
}
