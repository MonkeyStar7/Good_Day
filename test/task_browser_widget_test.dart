import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:good_day/data/vault_repository.dart';
import 'package:good_day/models/good_day_task.dart';
import 'package:good_day/models/repeat_schedule.dart';
import 'package:good_day/models/task_series.dart';
import 'package:good_day/task_browser_page.dart';

void main() {
  for (final width in [340.0, 400.0]) {
    testWidgets(
      'schedule editor keeps failed input and saves tomorrow repeat at $width',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 720);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var fail = true;
        DateTime? savedDate;
        EventRepeat? savedRepeat;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  child: const Text('安排'),
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => TaskScheduleDialog(
                      now: DateTime(2026, 10, 12, 9),
                      onSave: (title, notes, date, repeat) async {
                        if (fail) throw const FileSystemException('磁盘不可写');
                        savedDate = date;
                        savedRepeat = repeat;
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('安排'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('schedule-task-title')),
          '阅读',
        );
        await tester.tap(find.text('明天'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('task-repeat')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('每周').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('save-task-schedule')));
        await tester.pumpAndSettle();
        expect(find.textContaining('磁盘不可写'), findsOneWidget);
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('schedule-task-title')))
              .controller!
              .text,
          '阅读',
        );
        fail = false;
        await tester.tap(find.byKey(const Key('save-task-schedule')));
        await tester.pumpAndSettle();
        expect(savedDate, DateTime(2026, 10, 13));
        expect(savedRepeat, EventRepeat.weekly);
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      'task browser filters history, searches and completes future task at $width',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 720);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repository = _MemoryTasks();
        await tester.pumpWidget(
          MaterialApp(
            home: TaskBrowserPage(
              repository: repository,
              clock: () => DateTime(2026, 10, 12, 9),
              onEditingChanged: (_) {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('明天开会'), findsOneWidget);
        expect(find.text('昨天读书'), findsNothing);
        await tester.tap(find.byKey(const Key('task-filter-history')));
        await tester.pumpAndSettle();
        expect(find.text('昨天读书'), findsOneWidget);
        expect(find.text('明天开会'), findsNothing);
        await tester.enterText(find.byKey(const Key('task-search')), '不存在');
        await tester.pumpAndSettle();
        expect(find.text('这个范围没有任务'), findsOneWidget);
        await tester.enterText(find.byKey(const Key('task-search')), '书籍');
        await tester.pumpAndSettle();
        expect(find.text('昨天读书'), findsOneWidget);
        await tester.enterText(find.byKey(const Key('task-search')), '');
        await tester.tap(find.byKey(const Key('task-filter-tomorrow')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('browse-complete-next')));
        await tester.pumpAndSettle();
        expect(repository.tasks.last.isCompleted, isTrue);
        expect(find.text('明天开会'), findsNothing);
        await tester.tap(find.byKey(const Key('task-filter-history')));
        await tester.pumpAndSettle();
        expect(find.text('明天开会'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _MemoryTasks extends VaultRepository {
  _MemoryTasks() : super(Directory('unused-browser-fixture'));
  final tasks = [
    GoodDayTask(
      id: 'old',
      title: '昨天读书',
      notes: '书籍笔记',
      createdAt: DateTime(2026, 10, 11),
      scheduledDate: DateTime(2026, 10, 11),
      isCompleted: true,
      completedAt: DateTime(2026, 10, 11, 18),
    ),
    GoodDayTask(
      id: 'next',
      title: '明天开会',
      createdAt: DateTime(2026, 10, 12),
      scheduledDate: DateTime(2026, 10, 13),
    ),
  ];
  @override
  Future<List<GoodDayTask>> loadTasks() async => List.of(tasks);
  @override
  Future<List<TaskSeries>> loadTaskSeries() async => [];
  @override
  Future<GoodDayTask> setCompleted(GoodDayTask task, bool completed) async {
    final updated = task.setCompleted(completed, DateTime(2026, 10, 12, 9));
    tasks[tasks.indexWhere((entry) => entry.id == task.id)] = updated;
    return updated;
  }
}
