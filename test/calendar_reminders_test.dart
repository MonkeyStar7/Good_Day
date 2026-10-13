import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:good_day/data/vault_repository.dart';
import 'package:good_day/models/reminder_item.dart';
import 'package:good_day/models/good_day_task.dart';

void main() {
  late Directory vault;
  late VaultRepository store;
  late DateTime now;
  setUp(() async {
    vault = await Directory.systemTemp.createTemp('goodday_calendar_');
    now = DateTime(2026, 10, 12, 8);
    store = VaultRepository(vault, clock: () => now);
    await store.initialize();
  });
  tearDown(() async => vault.delete(recursive: true));
  Future<ReminderItem> daily({bool enabled = false, int? again}) =>
      store.saveReminder(
        title: '背单词',
        notes: '每天一页',
        dueAt: DateTime(2026, 10, 12, 9),
        rule: ReminderRule.presets['每天']!,
        enabled: enabled,
        calendarRepeat: true,
        repeatReminderMinutes: again,
        subtasks: const [GoodDaySubtask(id: 'read', title: '朗读')],
      );

  test('independent daily records appear without completion or reminders across restart', () async {
    final first = await daily();
    await store.setReminderSubtaskCompleted(first, 'read', true);
    now = DateTime(2026, 10, 13, 8);
    store = VaultRepository(vault, clock: () => now);
    final records = await store.loadReminders();
    expect(records, hasLength(2));
    expect(records.map((item) => item.isCompleted), [false, false]);
    expect(records.last.subtasks.single.isCompleted, isFalse);
    expect(records.every((item) => item.phaseDue(now) == null), isTrue);
    await store.completeReminder(records.last, true);
    expect((await store.loadReminders()).first.isCompleted, isFalse);
    now = DateTime(2026, 10, 14, 8);
    final third = await store.loadReminders();
    expect(third, hasLength(3));
    expect(third.map((item) => item.isCompleted), [false, true, false]);
    await Future.wait([store.loadReminders(), store.loadReminders()]);
    expect(await store.loadReminders(), hasLength(3));
  });

  test('plans project future occurrences without creating files and can edit a projected entry', () async {
    await daily();
    final plans = await store.loadReminders(through: DateTime(2027, 10, 12));
    expect(plans, hasLength(366));
    expect(plans.where((item) => item.projected), hasLength(365));
    expect(
      await store.remindersDirectory.list().where((f) => f is File).length,
      1,
    );
    final tomorrow = plans[1];
    final changed = await store.saveReminder(
      item: tomorrow,
      title: '背单词',
      notes: '每天两页',
      dueAt: tomorrow.dueAt,
      rule: tomorrow.rule,
      enabled: false,
      calendarRepeat: true,
    );
    expect(changed.id, tomorrow.id);
    expect(await store.loadReminders(), hasLength(2));
    now = DateTime(2026, 10, 13, 8);
    expect(await store.loadReminders(), hasLength(2));
  });

  test('workdays, stopping recurrence, and backup restoration preserve completed history', () async {
    final first = await store.saveReminder(
      title: '学习',
      notes: '',
      dueAt: DateTime(2026, 10, 16, 9),
      rule: ReminderRule.presets['工作日']!,
      calendarRepeat: true,
      enabled: false,
    );
    final plans = await store.loadReminders(through: DateTime(2026, 10, 20));
    expect(plans.map((item) => item.dueAt.day), [16, 19, 20]);
    final backup = await store.createBackup();
    await store.saveReminder(
      item: first,
      title: first.title,
      notes: '',
      dueAt: first.dueAt,
      rule: ReminderRule.presets['不重复']!,
      calendarRepeat: false,
      enabled: false,
    );
    expect(
      await store.loadReminders(through: DateTime(2026, 10, 20)),
      hasLength(1),
    );
    await store.restoreBackup(backup.id);
    expect(
      await store.loadReminders(through: DateTime(2026, 10, 20)),
      hasLength(3),
    );
    await store.deleteReminder(first);
    expect(await store.loadReminders(through: DateTime(2026, 10, 20)), isEmpty);
  });

  test('again reminders stop on completion or midnight and a daily task gets its own alarm', () async {
    final first = await daily(enabled: true, again: 5);
    now = first.dueAt;
    expect((await store.prepareReminder(first.id, now))!.pendingPhase, 'due');
    await store.resolveReminder(first.id, 'due');
    var saved = (await store.loadReminders()).first;
    expect(saved.phaseDue(now.add(const Duration(minutes: 4))), isNull);
    now = now.add(const Duration(minutes: 5));
    expect(saved.phaseDue(now), 'again');
    await store.prepareReminder(first.id, now);
    await store.resolveReminder(first.id, 'again');
    await store.completeReminder(saved, true);
    saved = (await store.loadReminders()).first;
    expect(saved.phaseDue(now.add(const Duration(minutes: 5))), isNull);
    now = DateTime(2026, 10, 13, 9);
    final records = await store.loadReminders();
    expect(records.last.phaseDue(now), 'due');
    expect(records.first.phaseDue(now), isNull);
  });

  test(
    'legacy calendar rules migrate idempotently without requiring completion',
    () async {
      await store.saveReminder(
        title: '原有每天事项',
        notes: '',
        dueAt: DateTime(2026, 10, 12, 9),
        rule: ReminderRule.presets['每天']!,
      );
      await store.migrateReminderRecurrence();
      await store.migrateReminderRecurrence();
      now = DateTime(2026, 10, 14, 8);
      final records = await store.loadReminders();
      expect(records, hasLength(3));
      expect(records.every((item) => item.calendarRepeat), isTrue);
      expect(records.first.phaseDue(now), isNull);
    },
  );

  test('failed series settings roll back the edited record and retain the prior repeat rule', () async {
    if (!Platform.isWindows) return;
    final first = await daily();
    final file = File('${vault.path}/Reminders/Series/${first.id}.md');
    await store.loadReminders();
    await Process.run('attrib', ['+R', file.path]);
    try {
      await expectLater(
        store.saveReminder(
          item: first,
          title: '不应保存的名称',
          notes: '',
          dueAt: first.dueAt,
          rule: ReminderRule.presets['每周']!,
          calendarRepeat: true,
          enabled: false,
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect((await store.loadReminders()).single.title, '背单词');
      expect((await store.loadReminders()).single.rule.label, '每天');
    } finally {
      await Process.run('attrib', ['-R', file.path]);
    }
  });

  test(
    'interrupted multi-file save recovers on restart before generating records',
    () async {
      final first = await daily();
      final root = store.remindersDirectory;
      final original = <String, String>{};
      await for (final entry in root.list(recursive: true)) {
        if (entry is File && entry.path.endsWith('.md')) {
          original[entry.path
              .substring(root.path.length + 1)
              .replaceAll('\\', '/')] = base64Encode(
            await entry.readAsBytes(),
          );
        }
      }
      await File('${root.path}/.series-operation.json')
          .writeAsString(jsonEncode(original));
      await File('${root.path}/${first.id}.md')
          .writeAsString(first.patch({'title': '半途修改'}).toMarkdown());
      store = VaultRepository(vault, clock: () => now);
      await store.initialize();
      expect((await store.loadReminders()).single.title, '背单词');
      expect(
        await File('${root.path}/.series-operation.json').exists(),
        isFalse,
      );
    },
  );
}
