import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:good_day/data/vault_repository.dart';
import 'package:good_day/models/reminder_item.dart';
import 'package:good_day/models/good_day_task.dart';
import 'package:good_day/reminder_pages.dart';
import 'package:good_day/app_update.dart';
import 'package:good_day/app_update_panel.dart';
import 'package:good_day/app_colors.dart';

void main() {
  late Directory vault;
  late VaultRepository store;
  final date = DateTime(2026, 10, 13, 9);
  setUp(() async {
    vault = await Directory.systemTemp.createTemp('goodday_separate_ui_');
    store = VaultRepository(vault, clock: () => DateTime(2026, 10, 13, 8));
    await store.initialize();
  });
  tearDown(() async => vault.delete(recursive: true));
  Future<void> settle(WidgetTester tester) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
  }

  Widget editor({double transparency = 0}) => MaterialApp(
    theme: ThemeData(extensions: [AppGlassStyle(transparency)]),
    home: Scaffold(
      body: SingleChildScrollView(
        child: ReminderEditor(
          repository: store,
          initialDate: date,
          onClosed: () {},
          onSaved: () async {},
        ),
      ),
    ),
  );

  testWidgets(
    'completed parent checks children and stays read-only until reopened',
    (tester) async {
      await tester.runAsync(() async {
        final item = await store.saveReminder(
          title: '整体验收',
          dueAt: date,
          notes: '保留备注',
          rule: const ReminderRule(RepeatUnit.none),
          enabled: false,
          subtasks: [GoodDaySubtask(id: 'step', title: '检查细节')],
        );
        await store.completeReminder(item, true);
        final completed = (await store.loadReminders()).single;
        expect(completed.subtasks.single.isCompleted, isTrue);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ReminderAgendaPage(
                repository: store,
                date: date,
                clock: () => date,
                scheduled: false,
                onEditingChanged: (_) {},
              ),
            ),
          ),
        );
        await settle(tester);
        await tester.tap(find.text('1 项已完成 · 显示'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('整体验收'));
        await tester.pumpAndSettle();
        expect(find.byType(ReminderEditor), findsNothing);
        expect(find.byKey(Key('delete-completed-${item.id}')), findsOneWidget);
        expect(
          tester
              .widget<Checkbox>(
                find.descendant(
                  of: find.byKey(const Key('reminder-subtask-step')),
                  matching: find.byType(Checkbox),
                ),
              )
              .value,
          isTrue,
        );
        await tester.tap(find.byKey(Key('reminder-complete-${item.id}')));
        await settle(tester);
        expect((await store.loadReminders()).single.isCompleted, isFalse);
        await tester.tap(find.text('整体验收'));
        await tester.pumpAndSettle();
        expect(find.byType(ReminderEditor), findsOneWidget);
        await tester.tap(find.byKey(const Key('cancel-reminder')));
        await settle(tester);
        await tester.tap(find.byKey(Key('reminder-complete-${item.id}')));
        await settle(tester);
        await tester.ensureVisible(
          find.byKey(Key('delete-completed-${item.id}')),
        );
        await tester.tap(find.byKey(Key('delete-completed-${item.id}')));
        await settle(tester);
        expect(await store.loadReminders(), isEmpty);
      });
    },
  );

  testWidgets(
    'workday recurrence is editable and saved without opening or enabling an alarm',
    (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(editor());
        await tester.enterText(
          find.byKey(const Key('reminder-title')),
          '工作日学习',
        );
        await tester.tap(find.byKey(const Key('todo-repeat-enabled')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('reminder-repeat')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('工作日').last);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('reminder-options-dialog')), findsNothing);
        expect(
          tester
              .widget<SwitchListTile>(find.byKey(const Key('reminder-enabled')))
              .value,
          isFalse,
        );
        await tester.ensureVisible(find.byKey(const Key('save-reminder')));
        await tester.tap(find.byKey(const Key('save-reminder')));
        await settle(tester);
        final items = await store.loadReminders();
        expect(items.single.rule.label, '工作日');
        expect(items.single.calendarRepeat, isTrue);
        expect(items.single.enabled, isFalse);
        await tester.pumpWidget(const SizedBox());
      });
    },
  );

  testWidgets(
    'reminder settings expand inline and retain date/time without additional reminders',
    (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(editor());
        await tester.enterText(find.byKey(const Key('reminder-title')), '喝水');
        await tester.tap(find.byKey(const Key('reminder-enabled')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('reminder-options-dialog')), findsNothing);
        expect(find.byKey(const Key('reminder-date')), findsOneWidget);
        expect(find.byKey(const Key('early-reminder')), findsOneWidget);
        expect(find.byKey(const Key('reminder-again-enabled')), findsNothing);
        await tester.ensureVisible(find.byKey(const Key('save-reminder')));
        await tester.tap(find.byKey(const Key('save-reminder')));
        await settle(tester);
        final items = await store.loadReminders();
        expect(items.single.enabled, isTrue);
        expect(items.single.rule.unit, RepeatUnit.none);
        expect(items.single.repeatReminderMinutes, isNull);
        await tester.pumpWidget(const SizedBox());
      });
    },
  );

  testWidgets('update controls and progress fit a small settings panel', (
    tester,
  ) async {
    final controller = AppUpdateController(install: (_) async => false);
    controller.release = AppRelease('1.4.14', Uri(), 1, '');
    controller.stage = UpdateStage.available;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 240,
              child: AppUpdatePanel(controller: controller),
            ),
          ),
        ),
      ),
    );
    expect(find.text('下载并更新'), findsOneWidget);
    expect(find.text('发现新版本 1.4.14'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets(
    'expanded task marker is passive and inline cards follow transparency',
    (tester) async {
      for (final opacity in [0.0, 0.55, 0.95]) {
        await tester.pumpWidget(editor(transparency: opacity));
        await tester.pumpAndSettle();
        final marker = find.byKey(const Key('reminder-state-indicator'));
        expect(tester.widget<Icon>(marker).icon, Icons.arrow_drop_down);
        expect(
          find.ancestor(of: marker, matching: find.byType(IconButton)),
          findsNothing,
        );
        await tester.tap(marker, warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('add-reminder-subtask')), findsOneWidget);
        for (final key in ['todo-repeat-card', 'reminder-settings-card']) {
          final card = tester.widget<Container>(
            find
                .descendant(
                  of: find.byKey(Key(key)),
                  matching: find.byType(Container),
                )
                .first,
          );
          expect(
            (card.decoration as BoxDecoration).color!.a,
            closeTo(1 - opacity, 0.01),
          );
        }
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'late selection changes do not repeat saving a disposed reminder editor',
    (tester) async {
      await tester.runAsync(() async {
        final key = GlobalKey<ReminderEditorState>();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ReminderEditor(
                key: key,
                repository: store,
                initialDate: date,
                onClosed: () {},
                onSaved: () async {
                  await tester.pumpWidget(const SizedBox());
                },
              ),
            ),
          ),
        );
        await tester.enterText(
          find.byKey(const Key('reminder-title')),
          '保存后退出',
        );
        final controller = tester
            .widget<TextField>(find.byKey(const Key('reminder-title')))
            .controller!;
        final saving = key.currentState!.flushPendingEdits();
        controller.selection = const TextSelection.collapsed(offset: 1);
        expect(await saving, isTrue);
        expect((await store.loadReminders()).single.title, '保存后退出');
        expect(tester.takeException(), isNull);
      });
    },
  );

  testWidgets(
    'typing during reminder save persists the newest text once before closing',
    (tester) async {
      await tester.runAsync(() async {
        final key = GlobalKey<ReminderEditorState>();
        var closed = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ReminderEditor(
                key: key,
                repository: store,
                initialDate: date,
                onClosed: () {},
                onSaved: () async {
                  closed++;
                  await tester.pumpWidget(const SizedBox());
                },
              ),
            ),
          ),
        );
        await tester.enterText(find.byKey(const Key('reminder-title')), '修改前');
        final controller = tester
            .widget<TextField>(find.byKey(const Key('reminder-title')))
            .controller!;
        final saving = key.currentState!.flushPendingEdits();
        controller.text = '修改后的最新文字';
        expect(await saving, isTrue);
        final records = await store.loadReminders();
        expect(records, hasLength(1));
        expect(records.single.title, '修改后的最新文字');
        expect(closed, 1);
        expect(tester.takeException(), isNull);
      });
    },
  );
}
