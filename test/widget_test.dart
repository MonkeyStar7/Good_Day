import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:good_day/data/vault_repository.dart';
import 'package:good_day/main.dart';
import 'package:good_day/models/good_day_goal.dart';
import 'package:good_day/models/good_day_plan.dart';
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

    expect(find.byKey(const Key('add-task-button')), findsOneWidget);

    final addRow = find.byKey(const Key('add-task-button'));
    final addRowRect = tester.getRect(addRow);
    await tester.tapAt(Offset(addRowRect.right - 8, addRowRect.center.dy));
    await _flushMicrotasks(tester);
    await tester.enterText(
      find.byKey(const Key('new-task-field')),
      '完成 Good Day MVP',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _flushMicrotasks(tester);

    expect(find.text('完成 Good Day MVP'), findsOneWidget);
    final task = repository.tasks.single;
    final checkbox = find.byKey(Key('task-checkbox-${task.id}'));

    await tester.tap(checkbox);
    await _flushMicrotasks(tester);
    expect(tester.widget<Checkbox>(checkbox).value, isTrue);

    await tester.tap(find.byKey(Key('delete-task-${task.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-delete-button')));
    await _flushMicrotasks(tester);
    expect(find.text('完成 Good Day MVP'), findsNothing);
    expect(repository.tasks, isEmpty);
  });

  testWidgets('finishes or cancels a new task when clicking elsewhere', (
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

    await tester.tap(find.byKey(const Key('add-task-button')));
    await _flushMicrotasks(tester);
    await tester.enterText(find.byKey(const Key('new-task-field')), '点击外部创建');
    await tester.tap(find.text('GOOD DAY'));
    await _flushMicrotasks(tester);

    expect(repository.tasks.single.title, '点击外部创建');
    expect(find.text('点击外部创建'), findsOneWidget);

    await tester.tap(find.byKey(const Key('add-task-button')));
    await _flushMicrotasks(tester);
    await tester.enterText(find.byKey(const Key('new-task-field')), '   ');
    await tester.tap(find.text('GOOD DAY'));
    await _flushMicrotasks(tester);

    expect(repository.tasks, hasLength(1));
    expect(find.byKey(const Key('new-task-field')), findsNothing);
    expect(find.byKey(const Key('add-task-button')), findsOneWidget);
  });

  testWidgets(
    'edits task details and shows checkable subtasks when collapsed',
    (tester) async {
      final repository = _MemoryRepository();
      final task = await repository.addTask('旧任务内容');
      await tester.pumpWidget(
        GoodDayApp(
          repository: repository,
          settingsController: AppSettingsController.inMemory(),
        ),
      );
      await _flushMicrotasks(tester);

      await tester.tap(find.byKey(Key('task-content-${task.id}')));
      await _flushMicrotasks(tester);
      await tester.enterText(
        find.byKey(Key('task-title-${task.id}')),
        '新的任务内容',
      );
      await tester.enterText(find.byKey(Key('task-note-${task.id}')), '一行备注');
      await tester.pump(const Duration(milliseconds: 700));
      await _flushMicrotasks(tester);

      final addSubtaskRow = find.byKey(Key('add-subtask-${task.id}'));
      final addSubtaskRect = tester.getRect(addSubtaskRow);
      await tester.tapAt(
        Offset(addSubtaskRect.right - 4, addSubtaskRect.center.dy),
      );
      await _flushMicrotasks(tester);
      await tester.enterText(
        find.byKey(Key('new-subtask-field-${task.id}')),
        '第一个子任务',
      );
      await tester.tap(find.text('GOOD DAY'));
      await _flushMicrotasks(tester);

      final updated = repository.tasks.single;
      expect(updated.title, '新的任务内容');
      expect(updated.notes, '一行备注');
      expect(updated.subtasks.single.title, '第一个子任务');
      expect(find.byKey(Key('task-note-${task.id}')), findsNothing);
      expect(find.text('第一个子任务'), findsOneWidget);

      await tester.tap(find.byKey(Key('task-content-${task.id}')));
      await _flushMicrotasks(tester);
      final subtask = repository.tasks.single.subtasks.single;
      await tester.enterText(
        find.byKey(Key('subtask-title-${task.id}-${subtask.id}')),
        '修改后的子任务',
      );
      await tester.tap(find.text('GOOD DAY'));
      await _flushMicrotasks(tester);
      expect(repository.tasks.single.subtasks.single.title, '修改后的子任务');
      expect(find.byKey(Key('task-note-${task.id}')), findsNothing);

      await tester.tap(find.byKey(Key('task-content-${task.id}')));
      await _flushMicrotasks(tester);
      await tester.tap(find.byKey(Key('add-subtask-${task.id}')));
      await _flushMicrotasks(tester);
      await tester.enterText(
        find.byKey(Key('new-subtask-field-${task.id}')),
        '   ',
      );
      await tester.tap(find.text('GOOD DAY'));
      await _flushMicrotasks(tester);
      expect(repository.tasks.single.subtasks, hasLength(1));
      expect(find.byKey(Key('task-note-${task.id}')), findsNothing);

      await tester.tap(
        find.byKey(Key('subtask-checkbox-${task.id}-${subtask.id}')),
      );
      await _flushMicrotasks(tester);
      expect(repository.tasks.single.subtasks.single.isCompleted, isTrue);
    },
  );

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

    await tester.ensureVisible(find.byKey(const Key('font-dengxian')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('font-dengxian')));
    await _flushMicrotasks(tester);
    expect(controller.settings.font, AppFont.dengXian);
  });

  testWidgets('cycles today, plans, and goals with shared goal labels', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 720);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final repository = _MemoryRepository();
    await tester.pumpWidget(
      GoodDayApp(
        repository: repository,
        settingsController: AppSettingsController.inMemory(),
      ),
    );
    await _flushMicrotasks(tester);

    await tester.tap(find.byKey(const Key('home-mode-switch')));
    await _flushMicrotasks(tester);
    expect(find.text('计划'), findsWidgets);
    await tester.tap(find.byKey(const Key('home-mode-switch')));
    await _flushMicrotasks(tester);
    expect(find.text('目标'), findsWidgets);

    await tester.tap(find.byKey(const Key('add-goal-button')));
    await _flushMicrotasks(tester);
    await tester.enterText(find.byKey(const Key('new-goal-name')), '深度学习');
    await tester.enterText(
      find.byKey(const Key('new-goal-description')),
      '完成 D2L 学习',
    );
    await tester.tap(find.byKey(const Key('goal-color-2')));
    await tester.tap(find.text('GOOD DAY'));
    await _flushMicrotasks(tester);

    final goal = repository.goals.single;
    expect(goal.name, '深度学习');
    expect(goal.description, '完成 D2L 学习');

    await tester.tap(find.byKey(const Key('home-mode-switch')));
    await _flushMicrotasks(tester);
    await tester.tap(find.byKey(const Key('add-task-button')));
    await _flushMicrotasks(tester);
    await tester.enterText(find.byKey(const Key('new-task-field')), '阅读第三章');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _flushMicrotasks(tester);
    final task = repository.tasks.single;
    await tester.tap(find.byKey(Key('task-content-${task.id}')));
    await _flushMicrotasks(tester);
    await tester.tap(find.byKey(Key('task-goal-${task.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('goal-menu-${goal.id}')));
    await tester.pumpAndSettle();
    expect(repository.tasks.single.goalId, goal.id);

    await tester.tap(find.byKey(const Key('home-mode-switch')));
    await _flushMicrotasks(tester);
    await tester.tap(find.byKey(const Key('add-plan-button')));
    await _flushMicrotasks(tester);
    await tester.enterText(find.byKey(const Key('new-plan-title')), '完成第三章');
    await tester.tap(find.byKey(const Key('plan-deadline-week')));
    await tester.tap(find.byKey(Key('plan-goal-${goal.id}')));
    await tester.tap(find.text('GOOD DAY'));
    await _flushMicrotasks(tester);

    final plan = repository.plans.single;
    expect(plan.title, '完成第三章');
    expect(plan.goalId, goal.id);
    expect(find.textContaining('%'), findsOneWidget);

    await tester.tap(find.byKey(Key('plan-checkbox-${plan.id}')));
    await _flushMicrotasks(tester);
    expect(repository.plans.single.isCompleted, isTrue);
    expect(find.text('已完成'), findsOneWidget);
  });

  testWidgets('edits and deletes plans and goals, then restores from trash', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 720);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final repository = _MemoryRepository();
    final goal = await repository.addGoal(
      name: '旧目标',
      description: '旧描述',
      colorValue: 0xFFF2B544,
    );
    final plan = await repository.addPlan(
      title: '旧计划',
      deadline: DateTime.now().add(const Duration(days: 7)),
      goalId: goal.id,
    );
    await tester.pumpWidget(
      GoodDayApp(
        repository: repository,
        settingsController: AppSettingsController.inMemory(),
      ),
    );
    await _flushMicrotasks(tester);

    await tester.tap(find.byKey(const Key('home-mode-switch')));
    await _flushMicrotasks(tester);
    await tester.tap(find.byKey(Key('edit-plan-${plan.id}')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(Key('edit-plan-title-${plan.id}')),
      '新计划',
    );
    await tester.pump(const Duration(milliseconds: 700));
    await _flushMicrotasks(tester);
    expect(repository.plans.single.title, '新计划');

    await tester.tap(find.byKey(Key('delete-plan-${plan.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-delete-button')));
    await _flushMicrotasks(tester);
    expect(repository.plans, isEmpty);

    await tester.tap(find.byKey(const Key('home-mode-switch')));
    await _flushMicrotasks(tester);
    await tester.tap(find.byKey(Key('edit-goal-${goal.id}')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(Key('edit-goal-name-${goal.id}')), '新目标');
    await tester.pump(const Duration(milliseconds: 700));
    await _flushMicrotasks(tester);
    expect(repository.goals.single.name, '新目标');

    await tester.tap(find.byKey(Key('delete-goal-${goal.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-delete-button')));
    await _flushMicrotasks(tester);
    expect(repository.goals, isEmpty);

    await tester.tap(find.byKey(const Key('settings-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('trash-button')));
    await tester.pumpAndSettle();
    expect(find.text('新计划'), findsOneWidget);
    expect(find.text('新目标'), findsOneWidget);

    await tester.tap(find.byKey(Key('restore-plan-${plan.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('restore-goal-${goal.id}')));
    await tester.pumpAndSettle();
    expect(repository.plans.single.title, '新计划');
    expect(repository.goals.single.name, '新目标');
    expect(find.text('垃圾桶是空的'), findsOneWidget);
  });
}

Future<void> _flushMicrotasks(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

class _MemoryRepository extends VaultRepository {
  _MemoryRepository() : super(Directory('memory-vault'));

  final List<GoodDayTask> tasks = [];
  final List<GoodDayGoal> goals = [];
  final List<GoodDayPlan> plans = [];
  final Map<String, GoodDayTask> trashedTasks = {};
  final Map<String, GoodDayPlan> trashedPlans = {};
  final Map<String, GoodDayGoal> trashedGoals = {};
  var _sequence = 0;

  @override
  Future<void> initialize() async {}

  @override
  Future<List<GoodDayTask>> loadTasks() async => List.of(tasks);

  @override
  Future<List<GoodDayGoal>> loadGoals() async => List.of(goals);

  @override
  Future<List<GoodDayPlan>> loadPlans() async => List.of(plans);

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
  Future<GoodDayTask> assignTaskGoal(GoodDayTask task, String? goalId) async {
    return _replace(task.assignGoal(goalId));
  }

  @override
  Future<GoodDayGoal> addGoal({
    required String name,
    required String description,
    required int colorValue,
  }) async {
    final goal = GoodDayGoal(
      id: 'goal_${++_sequence}',
      name: name,
      description: description,
      colorValue: colorValue,
      createdAt: DateTime(2026, 9, 9, 9),
    );
    goals.add(goal);
    return goal;
  }

  @override
  Future<GoodDayPlan> addPlan({
    required String title,
    required DateTime deadline,
    String? goalId,
  }) async {
    final plan = GoodDayPlan(
      id: 'plan_${++_sequence}',
      title: title,
      createdAt: DateTime.now(),
      deadline: deadline,
      goalId: goalId,
    );
    plans.add(plan);
    return plan;
  }

  @override
  Future<GoodDayPlan> setPlanCompleted(GoodDayPlan plan, bool completed) async {
    final updated = plan.setCompleted(completed, DateTime.now());
    final index = plans.indexWhere((item) => item.id == plan.id);
    plans[index] = updated;
    return updated;
  }

  @override
  Future<GoodDayGoal> updateGoal(
    GoodDayGoal goal, {
    required String name,
    required String description,
    required int colorValue,
  }) async {
    final updated = goal.update(
      name: name,
      description: description,
      colorValue: colorValue,
    );
    final index = goals.indexWhere((item) => item.id == goal.id);
    goals[index] = updated;
    return updated;
  }

  @override
  Future<GoodDayPlan> updatePlan(
    GoodDayPlan plan, {
    String? title,
    DateTime? deadline,
    String? goalId,
    bool clearGoal = false,
  }) async {
    final updated = plan.update(
      title: title,
      deadline: deadline,
      goalId: goalId,
      clearGoal: clearGoal,
    );
    final index = plans.indexWhere((item) => item.id == plan.id);
    plans[index] = updated;
    return updated;
  }

  @override
  Future<void> deletePlan(GoodDayPlan plan) async {
    trashedPlans[plan.id] = plan;
    plans.removeWhere((item) => item.id == plan.id);
  }

  @override
  Future<void> deleteGoal(GoodDayGoal goal) async {
    trashedGoals[goal.id] = goal;
    goals.removeWhere((item) => item.id == goal.id);
  }

  @override
  Future<GoodDayTask> updateTaskDetails(
    GoodDayTask task, {
    required String title,
    required String notes,
  }) async {
    return _replace(task.updateDetails(title: title, notes: notes));
  }

  @override
  Future<GoodDayTask> addSubtask(GoodDayTask task, String title) async {
    final updated = task.addSubtask(
      GoodDaySubtask(id: 'sub_${++_sequence}', title: title),
    );
    return _replace(updated);
  }

  @override
  Future<GoodDayTask> updateSubtask(
    GoodDayTask task,
    String subtaskId, {
    String? title,
    bool? isCompleted,
  }) async {
    return _replace(
      task.updateSubtask(subtaskId, title: title, isCompleted: isCompleted),
    );
  }

  @override
  Future<GoodDayTask> removeSubtask(GoodDayTask task, String subtaskId) async {
    return _replace(task.removeSubtask(subtaskId));
  }

  @override
  Future<void> deleteTask(GoodDayTask task) async {
    trashedTasks[task.id] = task;
    tasks.removeWhere((item) => item.id == task.id);
  }

  @override
  Future<List<TrashItem>> loadTrash() async => [
    for (final task in trashedTasks.values)
      TrashItem(
        type: TrashItemType.task,
        id: task.id,
        title: task.title,
        deletedAt: DateTime(2026, 9, 9),
      ),
    for (final plan in trashedPlans.values)
      TrashItem(
        type: TrashItemType.plan,
        id: plan.id,
        title: plan.title,
        deletedAt: DateTime(2026, 9, 9),
      ),
    for (final goal in trashedGoals.values)
      TrashItem(
        type: TrashItemType.goal,
        id: goal.id,
        title: goal.name,
        deletedAt: DateTime(2026, 9, 9),
      ),
  ];

  @override
  Future<void> restoreTrashItem(TrashItem item) async {
    switch (item.type) {
      case TrashItemType.task:
        tasks.add(trashedTasks.remove(item.id)!);
        return;
      case TrashItemType.plan:
        plans.add(trashedPlans.remove(item.id)!);
        return;
      case TrashItemType.goal:
        goals.add(trashedGoals.remove(item.id)!);
        return;
    }
  }

  @override
  Future<void> emptyTrash() async {
    trashedTasks.clear();
    trashedPlans.clear();
    trashedGoals.clear();
  }

  GoodDayTask _replace(GoodDayTask updated) {
    final index = tasks.indexWhere((item) => item.id == updated.id);
    tasks[index] = updated;
    return updated;
  }
}
