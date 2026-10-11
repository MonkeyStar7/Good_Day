import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:good_day/data/vault_repository.dart';
import 'package:good_day/models/good_day_plan.dart';
import 'package:good_day/models/good_day_task.dart';

void main() {
  late Directory temporaryVault;
  late DateTime now;
  late VaultRepository repository;

  setUp(() async {
    temporaryVault = await Directory.systemTemp.createTemp('good_day_vault_');
    now = DateTime(2026, 9, 8, 9, 30);
    repository = VaultRepository(temporaryVault, clock: () => now);
    await repository.initialize();
  });

  tearDown(() async {
    if (await temporaryVault.exists()) {
      await temporaryVault.delete(recursive: true);
    }
  });

  test('Markdown task is the source of truth and Daily stays readable', () async {
    final created = await repository.addTask('写下今天的计划');
    final taskFile = File(
      '${repository.tasksDirectory.path}${Platform.pathSeparator}${created.id}.md',
    );
    final dailyFile = File(
      '${repository.dailyDirectory.path}${Platform.pathSeparator}2026-09-08.md',
    );

    expect(await taskFile.exists(), isTrue);
    expect(await taskFile.readAsString(), contains('status: todo'));
    expect(await dailyFile.readAsString(), contains('- [ ] [写下今天的计划]'));

    final fromDisk = (await repository.loadTasks()).single;
    final completed = await repository.setCompleted(fromDisk, true);
    expect(completed.isCompleted, isTrue);
    expect(await taskFile.readAsString(), contains('status: done'));
    expect(await dailyFile.readAsString(), contains('- [x] [写下今天的计划]'));
    expect(await dailyFile.readAsString(), contains('## 今日完成'));
  });

  test('edits details and persists readable checkable subtasks', () async {
    var task = await repository.addTask('原来的任务');
    task = await repository.updateTaskDetails(
      task,
      title: '更新后的任务',
      notes: '一行备注\n会被收成一行',
    );
    task = await repository.addSubtask(task, '第一个子任务');
    final subtask = task.subtasks.single;
    task = await repository.updateSubtask(task, subtask.id, isCompleted: true);

    final taskFile = File(
      '${repository.tasksDirectory.path}${Platform.pathSeparator}${task.id}.md',
    );
    final markdown = await taskFile.readAsString();
    final fromDisk = (await repository.loadTasks()).single;
    final daily = await File(
      '${repository.dailyDirectory.path}${Platform.pathSeparator}2026-09-08.md',
    ).readAsString();

    expect(fromDisk.id, task.id);
    expect(fromDisk.title, '更新后的任务');
    expect(fromDisk.notes, '一行备注 会被收成一行');
    expect(fromDisk.subtasks.single.title, '第一个子任务');
    expect(fromDisk.subtasks.single.isCompleted, isTrue);
    expect(markdown, contains('> 一行备注 会被收成一行'));
    expect(markdown, contains('- [x] 第一个子任务'));
    expect(daily, contains('[更新后的任务]'));
    expect(daily, contains('  - [x] 第一个子任务'));
  });

  test('goals, plans, and task goal labels round-trip through Markdown', () async {
    var goal = await repository.addGoal(
      name: '深度学习',
      description: '完成 D2L 学习',
      colorValue: 0xFFF2B544,
    );
    var plan = await repository.addPlan(
      title: '完成第三章',
      deadline: DateTime(2026, 9, 20),
      goalId: goal.id,
    );
    var task = await repository.addTask('阅读第三章');
    task = await repository.assignTaskGoal(task, goal.id);

    goal = await repository.updateGoal(
      goal,
      name: '深度学习基础',
      description: '完成 D2L 和练习',
      colorValue: 0xFFDB8F5A,
    );
    plan = await repository.setPlanCompleted(plan, true);

    final loadedGoal = (await repository.loadGoals()).single;
    final loadedPlan = (await repository.loadPlans()).single;
    final loadedTask = (await repository.loadTasks()).single;
    final goalMarkdown = await File(
      '${repository.goalsDirectory.path}${Platform.pathSeparator}${goal.id}.md',
    ).readAsString();
    final planMarkdown = await File(
      '${repository.plansDirectory.path}${Platform.pathSeparator}${plan.id}.md',
    ).readAsString();

    expect(loadedGoal.name, '深度学习基础');
    expect(loadedGoal.description, '完成 D2L 和练习');
    expect(loadedGoal.colorValue, 0xFFDB8F5A);
    expect(loadedPlan.title, '完成第三章');
    expect(loadedPlan.goalId, goal.id);
    expect(loadedPlan.isCompleted, isTrue);
    expect(loadedTask.goalId, goal.id);
    expect(goalMarkdown, contains('# 深度学习基础'));
    expect(planMarkdown, contains('deadline: 2026-09-20'));
    expect(planMarkdown, contains('goal: ${goal.id}'));
  });

  test('plan remaining percentage decreases toward its deadline', () {
    final plan = GoodDayPlan(
      id: 'plan_test',
      title: '阶段计划',
      createdAt: DateTime(2026, 9, 8),
      deadline: DateTime(2026, 9, 17),
    );

    expect(plan.remainingFraction(DateTime(2026, 9, 8)), closeTo(1, 0.01));
    expect(plan.remainingFraction(DateTime(2026, 9, 13)), closeTo(0.5, 0.06));
    expect(plan.remainingFraction(DateTime(2026, 9, 18)), 0);
    expect(plan.remainingDays(DateTime(2026, 9, 17, 23, 59)), 0);
    expect(plan.remainingDays(DateTime(2026, 9, 18, 0, 1)), -1);
  });

  test('unfinished tasks wait for rescheduling without changing the old Daily file', () async {
    await repository.addTask('跨天任务');
    final oldDaily = File(
      '${repository.dailyDirectory.path}${Platform.pathSeparator}2026-09-08.md',
    );
    final oldContent = await oldDaily.readAsString();

    now = DateTime(2026, 9, 9, 8);
    final rolled = (await repository.loadTasks()).single;

    expect(dateKey(rolled.scheduledDate), '2026-09-08');
    expect(rolled.isWaitingForSchedule(now), isTrue);
    expect(await oldDaily.readAsString(), oldContent);
    expect(
      await File(
        '${repository.dailyDirectory.path}${Platform.pathSeparator}2026-09-09.md',
      ).exists(),
      isTrue,
    );
  });

  test('deleting archives Markdown instead of destroying it', () async {
    final task = await repository.addTask('以后仍然可以找回');
    await repository.deleteTask(task);

    expect(await repository.loadTasks(), isEmpty);
    final archived = File(
      '${repository.archiveDirectory.path}${Platform.pathSeparator}${task.id}.md',
    );
    expect(await archived.exists(), isTrue);
    expect(await archived.readAsString(), contains('status: deleted'));
  });

  test('edits plans and restores every deleted item from trash', () async {
    final goal = await repository.addGoal(
      name: '学习目标',
      description: '保持方向',
      colorValue: 0xFFF2B544,
    );
    var plan = await repository.addPlan(
      title: '原计划',
      deadline: DateTime(2026, 9, 12),
      goalId: goal.id,
    );
    final task = await repository.addTask('今日任务');
    plan = await repository.updatePlan(
      plan,
      title: '修改后的计划',
      deadline: DateTime(2026, 9, 20),
      clearGoal: true,
    );

    await repository.deleteTask(task);
    await repository.deletePlan(plan);
    await repository.deleteGoal(goal);

    final trash = await repository.loadTrash();
    expect(trash, hasLength(3));
    expect(
      trash.map((item) => item.type),
      containsAll([TrashItemType.task, TrashItemType.plan, TrashItemType.goal]),
    );
    expect(trash.map((item) => item.title), contains('修改后的计划'));

    for (final item in List<TrashItem>.of(trash)) {
      await repository.restoreTrashItem(item);
    }

    expect((await repository.loadTasks()).single.title, '今日任务');
    expect((await repository.loadPlans()).single.title, '修改后的计划');
    expect(
      (await repository.loadPlans()).single.deadline,
      DateTime(2026, 9, 20),
    );
    expect((await repository.loadGoals()).single.name, '学习目标');
    expect(await repository.loadTrash(), isEmpty);
  });

  test(
    'emptying trash permanently removes files and orphaned goal labels',
    () async {
      final goal = await repository.addGoal(
        name: '会被清空的目标',
        description: '',
        colorValue: 0xFFF2B544,
      );
      var task = await repository.addTask('有关联的任务');
      task = await repository.assignTaskGoal(task, goal.id);
      final plan = await repository.addPlan(
        title: '有关联的计划',
        deadline: DateTime(2026, 9, 20),
        goalId: goal.id,
      );
      await repository.deleteGoal(goal);
      expect(await repository.loadTrash(), hasLength(1));

      await repository.emptyTrash();

      expect(await repository.loadTrash(), isEmpty);
      expect((await repository.loadTasks()).single.goalId, isNull);
      expect((await repository.loadPlans()).single.goalId, isNull);
      expect(
        await File(
          '${repository.archivedGoalsDirectory.path}'
          '${Platform.pathSeparator}${goal.id}.md',
        ).exists(),
        isFalse,
      );
      expect(task.goalId, goal.id);
      expect(plan.goalId, goal.id);
    },
  );

  test('copies Markdown data to an empty vault without deleting source', () async {
    final task = await repository.addTask('搬到新的数据文件夹');
    final goal = await repository.addGoal(
      name: '迁移目标',
      description: '',
      colorValue: 0xFFF2B544,
    );
    final plan = await repository.addPlan(
      title: '迁移计划',
      deadline: DateTime(2026, 9, 20),
      goalId: goal.id,
    );
    final target = await Directory.systemTemp.createTemp('good_day_target_');
    addTearDown(() async {
      if (await target.exists()) await target.delete(recursive: true);
    });

    await repository.copyDataTo(target);
    final copiedRepository = VaultRepository(target, clock: () => now);
    final copiedTasks = await copiedRepository.loadTasks();

    expect(copiedTasks.single.title, task.title);
    expect((await copiedRepository.loadGoals()).single.name, goal.name);
    expect((await copiedRepository.loadPlans()).single.title, plan.title);
    expect(await repository.hasVaultData(), isTrue);
    expect(await copiedRepository.hasVaultData(), isTrue);
    expect(
      await File(
        '${repository.tasksDirectory.path}${Platform.pathSeparator}${task.id}.md',
      ).exists(),
      isTrue,
    );
  });

  test('deletes only Good Day managed data after a successful copy', () async {
    await repository.addTask('迁移后清理原数据');
    final unrelated = File(
      '${temporaryVault.path}${Platform.pathSeparator}我的其他文件.txt',
    );
    await unrelated.writeAsString('保留');
    final target = await Directory.systemTemp.createTemp('good_day_move_');
    addTearDown(() async {
      if (await target.exists()) await target.delete(recursive: true);
    });

    await repository.copyDataTo(target);
    await repository.deleteManagedData();

    expect(await repository.hasVaultData(), isFalse);
    expect(await unrelated.exists(), isTrue);
    expect(
      await VaultRepository(target, clock: () => now).hasVaultData(),
      isTrue,
    );
  });
}
