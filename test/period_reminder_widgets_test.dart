import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:good_day/models/good_day_task.dart';
import 'package:good_day/task_inline_options.dart';

void main() {
  for (final period in [TaskPeriod.week, TaskPeriod.month, TaskPeriod.year]) {
    for (final width in [210.0, 280.0]) {
      testWidgets('$period selects only dates inside the scope at $width', (
        tester,
      ) async {
        final now = DateTime(2026, 10, 14, 9, 17);
        DateTime? saved;
        int? interval;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: width,
                    child: TaskInlineOptions(
                      task: GoodDayTask(
                        id: 'scope',
                        title: '刷题',
                        createdAt: now,
                        scheduledDate: now,
                        period: period,
                      ),
                      clock: () => now,
                      onEditingChanged: (_) {},
                      onSave: (_, time, minutes) async {
                        saved = time;
                        interval = minutes;
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.byKey(const Key('task-reminder-settings-scope')));
        await tester.pumpAndSettle();
        CupertinoPicker picker(String label, int count) =>
            tester.widget<CupertinoPicker>(
              find.descendant(
                of: find.byKey(ValueKey('wheel-$label-$count')),
                matching: find.byType(CupertinoPicker),
              ),
            );
        expect(find.byKey(const ValueKey('wheel-年-201')), findsNothing);
        if (period == TaskPeriod.week) {
          final past = tester.widget<ChoiceChip>(
            find.byKey(const Key('reminder-weekday-1')),
          );
          expect(past.onSelected, isNull);
          await tester.tap(find.byKey(const Key('reminder-weekday-7')));
          await tester.pumpAndSettle();
        } else {
          picker('日', 31).onSelectedItemChanged!(19);
          await tester.pumpAndSettle();
          if (period == TaskPeriod.month) {
            expect(find.byKey(const ValueKey('wheel-月-12')), findsNothing);
          }
        }
        picker('时', 24).onSelectedItemChanged!(11);
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const Key('reminder-repeat-scope')),
        );
        await tester.tap(find.byKey(const Key('reminder-repeat-scope')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('reminder-interval-scope')),
          '30',
        );
        await tester.ensureVisible(
          find.byKey(const Key('save-task-options-scope')),
        );
        await tester.tap(find.byKey(const Key('save-task-options-scope')));
        await tester.pumpAndSettle();
        expect(
          saved,
          period == TaskPeriod.week
              ? DateTime(2026, 10, 18, 11, 17)
              : DateTime(2026, 10, 20, 11, 17),
        );
        expect(interval, 30);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets(
    'today quick choices are limited and cannot spill into tomorrow',
    (tester) async {
      final now = DateTime(2026, 10, 12, 23, 58);
      var saves = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: 240,
                child: TaskInlineOptions(
                  task: GoodDayTask(
                    id: 'end',
                    title: '复习',
                    createdAt: now,
                    scheduledDate: now,
                  ),
                  clock: () => now,
                  onSave: (_, _, _) async => saves++,
                  onEditingChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('task-reminder-settings-end')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('remind-after-end-15')), findsNothing);
      expect(find.byKey(const Key('remind-after-end-120')), findsNothing);
      await tester.tap(find.byKey(const Key('remind-after-end-5')));
      await tester.pumpAndSettle();
      expect(find.textContaining('今日内'), findsOneWidget);
      await tester.tap(find.byKey(const Key('reminder-repeat-end')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('reminder-interval-end')),
        '1440',
      );
      await tester.ensureVisible(find.byKey(const Key('remind-after-end-5')));
      await tester.tap(find.byKey(const Key('remind-after-end-5')));
      await tester.pumpAndSettle();
      expect(find.textContaining('1～1439'), findsOneWidget);
      expect(saves, 0);
    },
  );
}
