import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:good_day/data/vault_repository.dart';
import 'package:good_day/main.dart';
import 'package:good_day/models/good_day_task.dart';
import 'package:good_day/settings/app_settings.dart';

void main() {
  testWidgets('adds, completes, and removes a task from the UI', (
    tester,
  ) async {
    final repository = _MemoryRepository();
    await tester.pumpWidget(
      GoodDayApp(
        repository: repository,
        settingsController: AppSettingsController.inMemory(),
      ),
    );
    await _flushMicrotasks(tester);

    expect(find.text('今天很轻盈'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('new-task-field')),
      '完成 Good Day MVP',
    );
    await tester.tap(find.byKey(const Key('add-task-button')));
    await _flushMicrotasks(tester);

    expect(find.text('完成 Good Day MVP'), findsOneWidget);
    final task = repository.tasks.single;
    final checkbox = find.byKey(Key('task-checkbox-${task.id}'));

    await tester.tap(checkbox);
    await _flushMicrotasks(tester);
    expect(tester.widget<Checkbox>(checkbox).value, isTrue);

    await tester.tap(find.byKey(Key('delete-task-${task.id}')));
    await _flushMicrotasks(tester);
    expect(find.text('完成 Good Day MVP'), findsNothing);
    expect(repository.tasks, isEmpty);
  });

  testWidgets('opens settings and changes the font', (tester) async {
    final controller = AppSettingsController.inMemory();
    await tester.pumpWidget(
      GoodDayApp(
        repository: _MemoryRepository(),
        settingsController: controller,
      ),
    );
    await _flushMicrotasks(tester);

    await tester.tap(find.byKey(const Key('settings-button')));
    await _flushMicrotasks(tester);
    expect(find.text('设置'), findsWidgets);
    expect(find.byKey(const Key('choose-vault-button')), findsOneWidget);
    expect(find.byKey(const Key('vault-path')), findsOneWidget);

    await tester.tap(find.byKey(const Key('font-dengxian')));
    await _flushMicrotasks(tester);
    expect(controller.settings.font, AppFont.dengXian);
  });
}

Future<void> _flushMicrotasks(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

class _MemoryRepository extends VaultRepository {
  _MemoryRepository() : super(Directory('memory-vault'));

  final List<GoodDayTask> tasks = [];
  var _sequence = 0;

  @override
  Future<void> initialize() async {}

  @override
  Future<List<GoodDayTask>> loadTasks() async => List.of(tasks);

  @override
  Future<GoodDayTask> addTask(String title) async {
    final now = DateTime(2026, 9, 8, 9, _sequence++);
    final task = GoodDayTask(
      id: 'test_${_sequence.toString()}',
      title: title,
      createdAt: now,
      scheduledDate: now,
    );
    tasks.add(task);
    return task;
  }

  @override
  Future<GoodDayTask> setCompleted(GoodDayTask task, bool completed) async {
    final updated = task.setCompleted(completed, DateTime(2026, 9, 8, 10));
    final index = tasks.indexWhere((item) => item.id == task.id);
    tasks[index] = updated;
    return updated;
  }

  @override
  Future<void> deleteTask(GoodDayTask task) async {
    tasks.removeWhere((item) => item.id == task.id);
  }
}
