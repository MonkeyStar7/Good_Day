import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:good_day/models/good_day_task.dart';
import 'package:good_day/models/repeat_schedule.dart';
import 'package:good_day/task_inline_options.dart';

void main() {
  testWidgets(
    'reopening custom time resets to now and mouse wheel moves one item',
    (tester) async {
      var now = DateTime(2026, 10, 12, 11, 17);
      final outer = ScrollController();
      addTearDown(outer.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              controller: outer,
              child: SizedBox(
                width: 240,
                child: TaskInlineOptions(
                  task: GoodDayTask(
                    id: 'clock',
                    title: '提醒',
                    createdAt: now,
                    scheduledDate: now,
                  ),
                  clock: () => now,
                  onSave: (_, _, _) async {},
                  onEditingChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('task-reminder-settings-clock')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextButton>(
              find.byKey(const Key('task-reminder-settings-clock')),
            )
            .onPressed,
        isNotNull,
      );
      now = DateTime(2026, 10, 12, 11, 23);
      await tester.tap(find.byKey(const Key('custom-reminder-clock')));
      await tester.pumpAndSettle();
      CupertinoPicker picker(String name, int count) =>
          tester.widget<CupertinoPicker>(
            find.descendant(
              of: find.byKey(ValueKey('wheel-$name-$count')),
              matching: find.byType(CupertinoPicker),
            ),
          );
      expect(picker('分钟后', 60).scrollController!.selectedItem, 5);
      final position = tester.getCenter(
        find.byKey(const ValueKey('wheel-分钟后-60')),
      );
      final before = outer.offset;
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: position,
          scrollDelta: const Offset(0, 120),
        ),
      );
      await tester.pumpAndSettle();
      expect(picker('分钟后', 60).scrollController!.selectedItem, 6);
      expect(outer.offset, before);
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: position,
          scrollDelta: const Offset(0, -600),
        ),
      );
      await tester.pumpAndSettle();
      expect(picker('分钟后', 60).scrollController!.selectedItem, 5);
      await tester.tap(find.byKey(const Key('custom-reminder-clock')));
      await tester.pumpAndSettle();
      now = DateTime(2026, 10, 12, 13, 42);
      await tester.tap(find.byKey(const Key('custom-reminder-clock')));
      await tester.pumpAndSettle();
      expect(picker('小时后', 24).scrollController!.selectedItem, 0);
      expect(picker('分钟后', 60).scrollController!.selectedItem, 5);
      expect(tester.takeException(), isNull);
    },
  );
  for (final width in [210.0, 280.0]) {
    testWidgets('inline choices, quick reminder and wheel retry at $width', (
      tester,
    ) async {
      var now = DateTime(2026, 10, 12, 9);
      var fail = false;
      var editing = false;
      var task = GoodDayTask(
        id: 'one',
        title: '复习',
        createdAt: now,
        scheduledDate: now,
      );
      EventRepeat? savedRepeat;
      DateTime? savedTime;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: TaskInlineOptions(
                    task: task,
                    clock: () => now,
                    onEditingChanged: (value) => editing = value,
                    onSave: (repeat, time, interval) async {
                      if (fail) throw const FileSystemException('磁盘不可写');
                      savedRepeat = repeat;
                      savedTime = time;
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('task-repeat-settings-one')));
      await tester.pumpAndSettle();
      expect(editing, isTrue);
      expect(find.text('每小时'), findsNothing);
      await tester.tap(find.text('非工作日（周六、周日）'));
      await tester.pumpAndSettle();
      expect(savedRepeat, EventRepeat.weekends);
      expect(editing, isFalse);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(find.byKey(const Key('task-options-remind-one')));
      await tester.pumpAndSettle();
      expect(editing, isTrue);
      now = now.add(const Duration(minutes: 1));
      await tester.tap(find.byKey(const Key('remind-after-one-5')));
      await tester.pumpAndSettle();
      expect(savedTime, DateTime(2026, 10, 12, 9, 6));
      expect(editing, isFalse);
      await tester.tap(find.byKey(const Key('task-reminder-settings-one')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('custom-reminder-one')));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoPicker), findsNWidgets(2));
      expect(find.byType(TimePickerDialog), findsNothing);
      tester
          .widget<CupertinoPicker>(
            find.descendant(
              of: find.byKey(const ValueKey('wheel-分钟后-60')),
              matching: find.byType(CupertinoPicker),
            ),
          )
          .onSelectedItemChanged!(0);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('save-task-options-one')),
      );
      await tester.tap(find.byKey(const Key('save-task-options-one')));
      await tester.pumpAndSettle();
      expect(find.textContaining('请选择未来'), findsOneWidget);
      // Change the date through the actual picker, retaining all other wheels.
      final day = find.byKey(const ValueKey('wheel-分钟后-60'));
      final picker = tester.widget<CupertinoPicker>(
        find.descendant(of: day, matching: find.byType(CupertinoPicker)),
      );
      picker.onSelectedItemChanged!(15);
      await tester.pumpAndSettle();
      fail = true;
      await tester.tap(find.byKey(const Key('save-task-options-one')));
      await tester.pumpAndSettle();
      expect(find.textContaining('磁盘不可写'), findsOneWidget);
      expect(editing, isTrue);
      fail = false;
      await tester.tap(find.byKey(const Key('save-task-options-one')));
      await tester.pumpAndSettle();
      expect(savedTime, DateTime(2026, 10, 12, 9, 16));
      expect(editing, isFalse);
      expect(find.byType(CupertinoPicker), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'wheel changes clamp month end and dispose during a pending save',
    (tester) async {
      var date = DateTime(2028, 1, 31, 10, 40);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (_, setState) => SizedBox(
                width: 210,
                child: InlineReminderWheels(
                  value: date,
                  period: TaskPeriod.year,
                  anchor: DateTime(2028),
                  now: DateTime(2028),
                  enabled: true,
                  onChanged: (value) => setState(() => date = value),
                ),
              ),
            ),
          ),
        ),
      );
      CupertinoPicker picker(String name, int count) =>
          tester.widget<CupertinoPicker>(
            find.descendant(
              of: find.byKey(ValueKey('wheel-$name-$count')),
              matching: find.byType(CupertinoPicker),
            ),
          );
      picker('月', 12).onSelectedItemChanged!(1);
      await tester.pumpAndSettle();
      expect(date, DateTime(2028, 2, 29, 10, 40));
      expect(find.byKey(const ValueKey('wheel-年-201')), findsNothing);
      picker('分', 60).scrollController!.jumpToItem(45);
      await tester.pumpAndSettle();
      expect(date.minute, 45);
      final gate = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TaskInlineOptions(
              task: GoodDayTask(
                id: 'save',
                title: '复习',
                createdAt: date,
                scheduledDate: date,
              ),
              clock: () => date,
              onEditingChanged: (_) {},
              onSave: (_, _, _) => gate.future,
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('task-reminder-settings-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('remind-after-save-5')));
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      gate.complete();
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
