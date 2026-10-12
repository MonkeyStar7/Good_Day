import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:good_day/data/vault_repository.dart';
import 'package:good_day/event_reminder_service.dart';
import 'package:good_day/models/reminder_item.dart';
import 'package:good_day/models/good_day_event.dart';

void main() {
  test(
    'preset and custom recurrence retain clock, weekday, calendar anchors',
    () {
      final anchor = DateTime(2026, 10, 12, 9, 15);
      expect(
        ReminderRule.presets['每小时']!.nextAfter(anchor, anchor),
        DateTime(2026, 10, 12, 10, 15),
      );
      expect(
        ReminderRule.presets['工作日']!.nextAfter(
          anchor,
          DateTime(2026, 10, 16, 10),
        ),
        DateTime(2026, 10, 19, 9, 15),
      );
      expect(
        ReminderRule.presets['周末']!.nextAfter(anchor, anchor),
        DateTime(2026, 10, 17, 9, 15),
      );
      expect(
        ReminderRule.presets['每两周']!.nextAfter(anchor, anchor),
        DateTime(2026, 10, 26, 9, 15),
      );
      const custom = ReminderRule(
        RepeatUnit.week,
        interval: 3,
        weekdays: [1, 3, 5],
      );
      expect(
        custom.nextAfter(anchor, DateTime(2026, 10, 16, 10)),
        DateTime(2026, 11, 2, 9, 15),
      );
      final monthAnchor = DateTime(2027, 1, 31, 15);
      final february = ReminderRule.presets['每个月']!.nextAfter(
        monthAnchor,
        monthAnchor,
      )!;
      expect(february, DateTime(2027, 2, 28, 15));
      expect(
        ReminderRule.presets['每个月']!.nextAfter(monthAnchor, february),
        DateTime(2027, 3, 31, 15),
      );
      expect(
        ReminderRule.presets['每三个月']!.nextAfter(monthAnchor, monthAnchor),
        DateTime(2027, 4, 30, 15),
      );
      expect(
        ReminderRule.presets['每六个月']!.nextAfter(monthAnchor, monthAnchor),
        DateTime(2027, 7, 31, 15),
      );
      final leap = DateTime(2028, 2, 29, 20);
      expect(
        ReminderRule.presets['每年']!.nextAfter(leap, leap),
        DateTime(2029, 2, 28, 20),
      );
      expect(
        ReminderRule.presets['每年']!.nextAfter(leap, DateTime(2031, 3, 1)),
        DateTime(2032, 2, 29, 20),
      );
      expect(ReminderRule.presets['不重复']!.nextAfter(anchor, anchor), isNull);
    },
  );
  test(
    'early reminders use calendar months and expose both early and due alerts',
    () {
      final due = DateTime(2027, 3, 31, 9);
      expect(
        const EarlyReminder(1, LeadUnit.month).before(due),
        DateTime(2027, 2, 28, 9),
      );
      final item = ReminderItem(
        id: 'rem_test',
        title: '提醒',
        dueAt: due,
        createdAt: due,
        early: const EarlyReminder(30, LeadUnit.minute),
      );
      expect(item.phaseDue(due.subtract(const Duration(minutes: 31))), isNull);
      expect(item.phaseDue(due.subtract(const Duration(minutes: 30))), 'early');
      final acknowledged = item.patch({'earlyHandled': true});
      expect(
        acknowledged.phaseDue(due.subtract(const Duration(minutes: 5))),
        isNull,
      );
      expect(acknowledged.phaseDue(due), 'due');
      expect(item.phaseDue(due.add(const Duration(hours: 2))), 'due');
    },
  );

  late Directory vault;
  late VaultRepository repository;
  late DateTime now;
  setUp(() async {
    vault = await Directory.systemTemp.createTemp('goodday_redesign_');
    now = DateTime(2026, 10, 12, 8);
    repository = VaultRepository(vault, clock: () => now)
      ..usesReminderWorkflow = true;
    await repository.initialize();
  });
  tearDown(() async => vault.delete(recursive: true));
  test('old data stays historical and new reminders start empty', () async {
    final old = await repository.addTask('旧任务');
    await repository.addPlan(title: '旧计划', deadline: DateTime(2026, 12, 1));
    expect(await repository.loadReminders(), isEmpty);
    expect((await repository.loadTasks()).single.id, old.id);
    expect((await repository.loadPlans()).single.title, '旧计划');
  });
  test(
    'hourly completion creates distinct next instances without duplicates',
    () async {
      var item = await repository.saveReminder(
        title: '',
        dueAt: DateTime(2026, 10, 12, 9),
        notes: '保留备注',
        rule: ReminderRule.presets['每小时']!,
      );
      expect(item.title, '未命名1');
      await Future.wait([
        repository.completeReminder(item, true),
        repository.completeReminder(item, true),
      ]);
      var records = await repository.loadReminders();
      expect(records, hasLength(2));
      expect(records.where((item) => item.isCompleted), hasLength(1));
      item = records.singleWhere((item) => !item.isCompleted);
      expect(item.dueAt, DateTime(2026, 10, 12, 10));
      await repository.completeReminder(item, true);
      records = await repository.loadReminders();
      expect(records, hasLength(3));
      expect(
        records.singleWhere((item) => !item.isCompleted).dueAt,
        DateTime(2026, 10, 12, 11),
      );
      final reopened = VaultRepository(vault, clock: () => now);
      expect(await reopened.loadReminders(), hasLength(3));
      expect(
        (await reopened.loadReminders()).every((item) => item.notes == '保留备注'),
        isTrue,
      );
    },
  );
  test(
    'monthly recurrence and early reminders survive editing and backup restore',
    () async {
      now = DateTime(2027, 1, 31, 8);
      final item = await repository.saveReminder(
        title: '刷题',
        notes: '',
        dueAt: DateTime(2027, 1, 31, 9),
        rule: ReminderRule.presets['每个月']!,
        early: const EarlyReminder(1, LeadUnit.month),
      );
      await repository.completeReminder(item, true);
      var next = (await repository.loadReminders()).singleWhere(
        (item) => !item.isCompleted,
      );
      next = await repository.saveReminder(
        item: next,
        title: '改名',
        notes: '备注',
        dueAt: next.dueAt,
        rule: next.rule,
        early: const EarlyReminder(2, LeadUnit.hour),
      );
      now = DateTime(2027, 2, 28, 8);
      await repository.completeReminder(next, true);
      expect(
        (await repository.loadReminders())
            .singleWhere((item) => !item.isCompleted)
            .dueAt,
        DateTime(2027, 3, 31, 9),
      );
      final snapshot = await repository.createBackup();
      final latest = (await repository.loadReminders()).last;
      await repository.deleteReminder(latest);
      expect(await repository.loadReminders(), hasLength(2));
      await repository.restoreBackup(snapshot.id);
      expect(await repository.loadReminders(), hasLength(3));
    },
  );
  test(
    'early acknowledgement, snooze and due acknowledgement remain durable',
    () async {
      final item = await repository.saveReminder(
        title: '开会',
        notes: '',
        dueAt: DateTime(2026, 10, 12, 9),
        rule: ReminderRule.presets['不重复']!,
        early: const EarlyReminder(30, LeadUnit.minute),
      );
      now = DateTime(2026, 10, 12, 8, 30);
      expect(
        (await repository.prepareReminder(item.id, now))!.pendingPhase,
        'early',
      );
      await repository.resolveReminder(
        item.id,
        'early',
        snoozeUntil: now.add(const Duration(minutes: 40)),
      );
      final reopened = VaultRepository(vault, clock: () => now);
      expect((await reopened.loadReminders()).single.phaseDue(now), isNull);
      now = DateTime(2026, 10, 12, 9);
      expect(
        (await repository.prepareReminder(item.id, now))!.pendingPhase,
        'due',
      );
      await repository.resolveReminder(item.id, 'due');
      expect((await repository.loadReminders()).single.phaseDue(now), isNull);
    },
  );
  test(
    'deleted reminders restore paused and remain recoverable from trash',
    () async {
      final item = await repository.saveReminder(
        title: '待恢复',
        notes: '',
        dueAt: now,
        rule: ReminderRule.presets['不重复']!,
      );
      await repository.deleteReminder(item);
      expect(await repository.loadReminders(), isEmpty);
      final trashed = (await repository.loadTrash()).single;
      expect(trashed.type, TrashItemType.reminder);
      await repository.restoreTrashItem(trashed);
      expect((await repository.loadReminders()).single.enabled, isFalse);
      await repository.deleteReminder(
        (await repository.loadReminders()).single,
      );
      await repository.emptyTrash();
      expect(await repository.loadReminders(includeDeleted: true), isEmpty);
    },
  );
  test(
    'a past early time is skipped when creating a future reminder',
    () async {
      final item = await repository.saveReminder(
        title: '今天九点',
        notes: '',
        dueAt: DateTime(2026, 10, 12, 9),
        rule: ReminderRule.presets['不重复']!,
        early: const EarlyReminder(2, LeadUnit.hour),
      );
      expect(item.earlyHandled, isTrue);
      expect(item.phaseDue(now), isNull);
      expect(item.phaseDue(DateTime(2026, 10, 12, 9)), 'due');
    },
  );

  test(
    'completing historical repeated tasks does not repopulate the new workflow',
    () async {
      var old = await repository.addTask('旧循环任务');
      old = await repository.saveTaskOptions(
        task: old,
        repeat: EventRepeat.daily,
        reminderAt: null,
      );
      await repository.setCompleted(old, true);
      now = DateTime(2026, 10, 14);
      expect(await repository.loadTasks(), hasLength(1));
      expect(await repository.loadReminders(), isEmpty);
    },
  );

  test(
    'failed completion rolls back its newly generated next reminder',
    () async {
      if (!Platform.isWindows) return;
      final item = await repository.saveReminder(
        title: '不能丢的重复任务',
        notes: '',
        dueAt: DateTime(2026, 10, 12, 9),
        rule: ReminderRule.presets['每天']!,
      );
      final file = File('${vault.path}/Reminders/${item.id}.md');
      await Process.run('attrib', ['+R', file.path]);
      try {
        await expectLater(
          repository.completeReminder(item, true),
          throwsA(isA<FileSystemException>()),
        );
        final records = await repository.loadReminders();
        expect(records, hasLength(1));
        expect(records.single.isCompleted, isFalse);
      } finally {
        await Process.run('attrib', ['-R', file.path]);
      }
      await repository.completeReminder(item, true);
      expect(await repository.loadReminders(), hasLength(2));
    },
  );

  test('acknowledging a stale popup does not change completed or rescheduled reminders', () async {
    var item = await repository.saveReminder(
      title: '状态保护',
      notes: '',
      dueAt: DateTime(2026, 10, 12, 9),
      rule: ReminderRule.presets['不重复']!,
    );
    now = DateTime(2026, 10, 12, 9);
    await repository.prepareReminder(item.id, now);
    await repository.completeReminder(item, true);
    await repository.resolveReminder(item.id, 'due');
    expect((await repository.loadReminders()).single.isCompleted, isTrue);
    item = await repository.saveReminder(
      title: '改日期保护',
      notes: '',
      dueAt: now,
      rule: ReminderRule.presets['不重复']!,
    );
    await repository.prepareReminder(item.id, now);
    item = await repository.saveReminder(
      item: item,
      title: item.title,
      notes: '',
      dueAt: now.add(const Duration(days: 1)),
      rule: item.rule,
    );
    await repository.resolveReminder(item.id, 'due');
    final saved = (await repository.loadReminders()).singleWhere(
      (record) => record.id == item.id,
    );
    expect(saved.dueHandled, isFalse);
    expect(saved.dueAt, now.add(const Duration(days: 1)));
  });

  test(
    'new workflow ignores old alarms and fires early plus due notifications',
    () async {
      final old = await repository.addTask('旧闹钟');
      await repository.saveTaskOptions(
        task: old,
        repeat: old.repeat,
        reminderAt: DateTime(2026, 10, 12, 8, 30),
      );
      await repository.saveReminder(
        title: '新提醒',
        notes: '',
        dueAt: DateTime(2026, 10, 12, 9),
        rule: ReminderRule.presets['不重复']!,
        early: const EarlyReminder(30, LeadUnit.minute),
      );
      final fired = <String>[];
      final service = EventReminderService(
        repository: () => repository,
        clock: () => now,
        canPresent: () => true,
        present: (event, occurrence, resolve) async {
          fired.add(event.title);
          await resolve(null);
        },
        onChanged: () async {},
        onError: (error) => fail('$error'),
      );
      now = DateTime(2026, 10, 12, 8, 30);
      await service.check();
      await service.check();
      expect(fired, ['新提醒']);
      now = DateTime(2026, 10, 12, 9);
      await service.check();
      await service.check();
      expect(fired, ['新提醒', '新提醒']);
      service.dispose();
    },
  );
}
