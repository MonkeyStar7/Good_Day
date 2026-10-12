import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:good_day/data/vault_repository.dart';
import 'package:good_day/models/good_day_task.dart';
import 'package:good_day/models/reminder_item.dart';

void main() {
  late Directory vault;
  late VaultRepository repository;
  late DateTime now;
  setUp(() async {
    vault = await Directory.systemTemp.createTemp('goodday_inline_safety_');
    now = DateTime(2026, 10, 12, 16);
    repository = VaultRepository(vault, clock: () => now)
      ..usesReminderWorkflow = true;
    await repository.initialize();
  });
  tearDown(() async => vault.delete(recursive: true));

  test('old reminder files without subtasks still load', () {
    final item = ReminderItem(
      id: 'old',
      title: '旧事项',
      dueAt: now,
      createdAt: now,
    );
    final json = item.toJson()..remove('subtasks');
    expect(ReminderItem.fromJson(json).subtasks, isEmpty);
  });

  test(
    'past configured times stay silent, future alarms survive restarting',
    () async {
      final past = await repository.saveReminder(
        title: '过去的提醒',
        dueAt: now.subtract(const Duration(hours: 7)),
        notes: '',
        rule: ReminderRule.presets['每天']!,
        early: const EarlyReminder(15, LeadUnit.minute),
      );
      expect(past.dueHandled, isTrue);
      expect(await repository.prepareReminder(past.id, now), isNull);
      final future = await repository.saveReminder(
        title: '稍后提醒',
        dueAt: now.add(const Duration(hours: 1)),
        notes: '',
        rule: ReminderRule.presets['不重复']!,
      );
      now = now.add(const Duration(hours: 2));
      final reopened = VaultRepository(vault, clock: () => now);
      expect(
        (await reopened.prepareReminder(future.id, now))!.pendingPhase,
        'due',
      );
      expect(await reopened.prepareReminder(past.id, now), isNull);
      final rescheduled = await reopened.saveReminder(
        item: future,
        title: future.title,
        dueAt: now.subtract(const Duration(minutes: 1)),
        notes: '',
        rule: future.rule,
      );
      expect(rescheduled.pendingPhase, isNull);
      expect(await reopened.prepareReminder(future.id, now), isNull);
    },
  );

  test('subtasks survive stale title edits, restart, backup, trash and repeat reset', () async {
    final item = await repository.saveReminder(
      title: '刷题',
      notes: '保留备注',
      dueAt: now.add(const Duration(hours: 1)),
      rule: ReminderRule.presets['每天']!,
      subtasks: const [
        GoodDaySubtask(id: 'one', title: '第一套'),
        GoodDaySubtask(id: 'two', title: '第二套'),
      ],
    );
    await repository.setReminderSubtaskCompleted(item, 'one', true);
    await repository.saveReminder(
      item: item,
      title: '刷数学题',
      notes: item.notes,
      dueAt: item.dueAt,
      rule: item.rule,
    );
    final reopened = VaultRepository(vault, clock: () => now)
      ..usesReminderWorkflow = true;
    var saved = (await reopened.loadReminders()).single;
    expect(saved.subtasks.first.isCompleted, isTrue);
    expect(saved.subtasks.last.isCompleted, isFalse);
    final backup = await reopened.createBackup();
    await reopened.setReminderSubtaskCompleted(saved, 'two', true);
    await reopened.restoreBackup(backup.id);
    saved = (await reopened.loadReminders()).single;
    expect(saved.subtasks.last.isCompleted, isFalse);
    await reopened.deleteReminder(saved);
    final trash = (await reopened.loadTrash()).single;
    await reopened.restoreTrashItem(trash);
    saved = (await reopened.loadReminders()).single;
    expect(saved.subtasks.first.title, '第一套');
    expect(saved.subtasks.first.isCompleted, isTrue);
    await reopened.completeReminder(saved, true);
    final records = await reopened.loadReminders();
    expect(
      records
          .singleWhere((item) => item.isCompleted)
          .subtasks
          .first
          .isCompleted,
      isTrue,
    );
    final next = records.singleWhere((item) => !item.isCompleted);
    expect(next.subtasks.map((task) => task.title), ['第一套', '第二套']);
    expect(next.subtasks.every((task) => !task.isCompleted), isTrue);
  });
}
