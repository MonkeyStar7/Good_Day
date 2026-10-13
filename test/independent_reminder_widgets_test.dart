import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:good_day/data/vault_repository.dart';
import 'package:good_day/models/reminder_item.dart';
import 'package:good_day/reminder_pages.dart';
import 'package:good_day/app_update.dart';
import 'package:good_day/app_update_panel.dart';

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

  Widget editor() => MaterialApp(
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
    'reminder dialog holds only alarm settings and minute-based additional reminders',
    (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(editor());
        await tester.enterText(find.byKey(const Key('reminder-title')), '喝水');
        await tester.tap(find.byKey(const Key('reminder-enabled')));
        await tester.pumpAndSettle();
        final dialog = find.byKey(const Key('reminder-options-dialog'));
        expect(
          find.descendant(
            of: dialog,
            matching: find.byKey(const Key('reminder-repeat')),
          ),
          findsNothing,
        );
        await tester.tap(find.byKey(const Key('reminder-again-enabled')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('reminder-again-minutes')),
          '5',
        );
        await tester.tap(find.byKey(const Key('apply-reminder-options')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('save-reminder')));
        await tester.tap(find.byKey(const Key('save-reminder')));
        await settle(tester);
        final items = await store.loadReminders();
        expect(items.single.enabled, isTrue);
        expect(items.single.rule.unit, RepeatUnit.none);
        expect(items.single.repeatReminderMinutes, 5);
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
}
