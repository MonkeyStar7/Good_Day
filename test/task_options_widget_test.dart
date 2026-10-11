import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:good_day/models/good_day_task.dart';
import 'package:good_day/models/repeat_schedule.dart';
import 'package:good_day/task_options_dialog.dart';

void main() {
  for (final width in [340.0, 400.0]) {
    testWidgets(
      'options only edit repeat/reminder, retain failed choices at $width',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 720);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var fail = true;
        EventRepeat? savedRepeat;
        DateTime? savedReminder;
        final now = DateTime(2026, 10, 12, 9);
        final task = GoodDayTask(
          id: 'task1',
          title: '三套卷子',
          notes: '备注',
          createdAt: now,
          scheduledDate: now,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => TaskOptionsDialog(
                      task: task,
                      now: now,
                      onSave: (repeat, reminderAt) async {
                        if (fail) throw const FileSystemException('磁盘不可写');
                        savedRepeat = repeat;
                        savedReminder = reminderAt;
                      },
                    ),
                  ),
                  child: const Text('设置'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('设置'));
        await tester.pumpAndSettle();
        expect(find.byType(TextField), findsNothing);
        expect(find.text('安排日期'), findsNothing);
        await tester.tap(find.byKey(const Key('task-options-repeat')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('每天').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('task-options-remind')));
        await tester.pumpAndSettle();
        expect(find.text('10:00'), findsOneWidget);
        await tester.tap(find.byKey(const Key('save-task-options')));
        await tester.pumpAndSettle();
        expect(find.textContaining('磁盘不可写'), findsOneWidget);
        expect(find.text('10:00'), findsOneWidget);
        fail = false;
        await tester.tap(find.byKey(const Key('save-task-options')));
        await tester.pumpAndSettle();
        expect(savedRepeat, EventRepeat.daily);
        expect(savedReminder, DateTime(2026, 10, 12, 10));
        expect(find.byType(TaskOptionsDialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
