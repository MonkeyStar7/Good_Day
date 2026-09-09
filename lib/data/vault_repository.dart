import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/good_day_goal.dart';
import '../models/good_day_plan.dart';
import '../models/good_day_task.dart';

enum TrashItemType { task, plan, goal }

class TrashItem {
  const TrashItem({
    required this.type,
    required this.id,
    required this.title,
    required this.deletedAt,
  });

  final TrashItemType type;
  final String id;
  final String title;
  final DateTime deletedAt;
}

class VaultRepository {
  VaultRepository(this.vaultDirectory, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final Directory vaultDirectory;
  final DateTime Function() _clock;

  Directory get tasksDirectory => _childDirectory(vaultDirectory, 'Tasks');
  Directory get dailyDirectory => _childDirectory(vaultDirectory, 'Daily');
  Directory get archiveDirectory => _childDirectory(vaultDirectory, 'Archive');
  Directory get archivedPlansDirectory =>
      _childDirectory(archiveDirectory, 'Plans');
  Directory get archivedGoalsDirectory =>
      _childDirectory(archiveDirectory, 'Goals');
  Directory get goalsDirectory => _childDirectory(vaultDirectory, 'Goals');
  Directory get plansDirectory => _childDirectory(vaultDirectory, 'Plans');

  static Future<VaultRepository> createDefault() async {
    final documents = await getApplicationDocumentsDirectory();
    return VaultRepository(_childDirectory(documents, 'Good Day Vault'));
  }

  Future<void> initialize() async {
    await tasksDirectory.create(recursive: true);
    await dailyDirectory.create(recursive: true);
    await archiveDirectory.create(recursive: true);
    await archivedPlansDirectory.create(recursive: true);
    await archivedGoalsDirectory.create(recursive: true);
    await goalsDirectory.create(recursive: true);
    await plansDirectory.create(recursive: true);
  }

  Future<bool> hasVaultData() async {
    for (final directory in [
      tasksDirectory,
      dailyDirectory,
      archiveDirectory,
      goalsDirectory,
      plansDirectory,
    ]) {
      if (!await directory.exists()) continue;
      await for (final entity in directory.list()) {
        if (entity is File && entity.path.toLowerCase().endsWith('.md')) {
          return true;
        }
      }
    }
    return false;
  }

  Future<void> copyDataTo(Directory targetVault) async {
    await initialize();
    await targetVault.create(recursive: true);

    final sourcePath = (await vaultDirectory.resolveSymbolicLinks())
        .replaceAll('/', Platform.pathSeparator)
        .toLowerCase();
    final targetPath = (await targetVault.resolveSymbolicLinks())
        .replaceAll('/', Platform.pathSeparator)
        .toLowerCase();
    final separator = Platform.pathSeparator;
    if (sourcePath == targetPath ||
        targetPath.startsWith('$sourcePath$separator') ||
        sourcePath.startsWith('$targetPath$separator')) {
      throw const FileSystemException('不能选择当前 Vault 的内部或上级文件夹');
    }

    for (final name in ['Tasks', 'Daily', 'Archive', 'Goals', 'Plans']) {
      await _copyDirectory(
        _childDirectory(vaultDirectory, name),
        _childDirectory(targetVault, name),
      );
    }
  }

  Future<void> deleteManagedData() async {
    final resolvedVaultPath = (await vaultDirectory.resolveSymbolicLinks())
        .replaceAll('/', Platform.pathSeparator);
    if (_isFileSystemRoot(resolvedVaultPath)) {
      throw const FileSystemException('拒绝删除磁盘根目录中的数据');
    }

    for (final directory in [
      tasksDirectory,
      dailyDirectory,
      archiveDirectory,
      goalsDirectory,
      plansDirectory,
    ]) {
      if (await directory.exists()) await directory.delete(recursive: true);
    }

    final settingsDirectory = _childDirectory(vaultDirectory, '.goodday');
    final settingsFile = _childFile(settingsDirectory, 'settings.json');
    if (await settingsFile.exists()) await settingsFile.delete();
    if (await settingsDirectory.exists() &&
        await settingsDirectory.list().isEmpty) {
      await settingsDirectory.delete();
    }
  }

  Future<List<GoodDayTask>> loadTasks() async {
    await initialize();
    final tasks = await _readTasks(tasksDirectory);
    final now = _clock();

    for (var i = 0; i < tasks.length; i++) {
      final task = tasks[i];
      if (!task.isCompleted && !isSameDay(task.scheduledDate, now)) {
        final rolled = task.rollForward(now);
        tasks[i] = rolled;
        await _writeTask(rolled);
      }
    }

    _sort(tasks);
    await _syncDaily(tasks, now);
    return tasks;
  }

  Future<GoodDayTask> addTask(String title) async {
    final now = _clock();
    final task = GoodDayTask(
      id: 'gd_${now.microsecondsSinceEpoch.toRadixString(36)}',
      title: title.trim(),
      createdAt: now,
      scheduledDate: now,
    );
    await _writeTask(task);
    await _syncDaily(await _readTasks(tasksDirectory), now);
    return task;
  }

  Future<GoodDayTask> setCompleted(GoodDayTask task, bool completed) async {
    final now = _clock();
    final updated = task.setCompleted(completed, now);
    await _writeTask(updated);
    await _syncDaily(await _readTasks(tasksDirectory), now);
    return updated;
  }

  Future<GoodDayTask> assignTaskGoal(GoodDayTask task, String? goalId) async {
    final updated = task.assignGoal(goalId);
    await _writeTask(updated);
    await _syncDaily(await _readTasks(tasksDirectory), _clock());
    return updated;
  }

  Future<List<GoodDayGoal>> loadGoals() async {
    await initialize();
    final goals = <GoodDayGoal>[];
    await for (final entity in goalsDirectory.list()) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.md')) {
        continue;
      }
      try {
        goals.add(GoodDayGoal.fromMarkdown(await entity.readAsString()));
      } on FormatException {
        // Keep malformed or hand-written files untouched.
      }
    }
    goals.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return goals;
  }

  Future<GoodDayGoal> addGoal({
    required String name,
    required String description,
    required int colorValue,
  }) async {
    final normalizedName = name.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    if (normalizedName.isEmpty) throw const FormatException('目标名称不能为空');
    final now = _clock();
    final goal = GoodDayGoal(
      id: 'goal_${now.microsecondsSinceEpoch.toRadixString(36)}',
      name: normalizedName,
      description: description,
      colorValue: colorValue,
      createdAt: now,
    );
    await _writeGoal(goal);
    return goal;
  }

  Future<GoodDayGoal> updateGoal(
    GoodDayGoal goal, {
    required String name,
    required String description,
    required int colorValue,
  }) async {
    if (name.trim().isEmpty) throw const FormatException('目标名称不能为空');
    final updated = goal.update(
      name: name,
      description: description,
      colorValue: colorValue,
    );
    await _writeGoal(updated);
    return updated;
  }

  Future<void> deleteGoal(GoodDayGoal goal) async {
    await initialize();
    await _taskFile(
      archivedGoalsDirectory,
      goal.id,
    ).writeAsString(goal.toMarkdown(), flush: true);
    final activeFile = _taskFile(goalsDirectory, goal.id);
    if (await activeFile.exists()) await activeFile.delete();
  }

  Future<List<GoodDayPlan>> loadPlans() async {
    await initialize();
    final plans = <GoodDayPlan>[];
    await for (final entity in plansDirectory.list()) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.md')) {
        continue;
      }
      try {
        plans.add(GoodDayPlan.fromMarkdown(await entity.readAsString()));
      } on FormatException {
        // Keep malformed or hand-written files untouched.
      }
    }
    _sortPlans(plans);
    return plans;
  }

  Future<GoodDayPlan> addPlan({
    required String title,
    required DateTime deadline,
    String? goalId,
  }) async {
    final normalizedTitle = title.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    if (normalizedTitle.isEmpty) throw const FormatException('计划名称不能为空');
    final now = _clock();
    final normalizedDeadline = DateTime(
      deadline.year,
      deadline.month,
      deadline.day,
    );
    if (normalizedDeadline.isBefore(DateTime(now.year, now.month, now.day))) {
      throw const FormatException('截止日期不能早于今天');
    }
    final plan = GoodDayPlan(
      id: 'plan_${now.microsecondsSinceEpoch.toRadixString(36)}',
      title: normalizedTitle,
      createdAt: now,
      deadline: normalizedDeadline,
      goalId: goalId,
    );
    await _writePlan(plan);
    return plan;
  }

  Future<GoodDayPlan> setPlanCompleted(GoodDayPlan plan, bool completed) async {
    final updated = plan.setCompleted(completed, _clock());
    await _writePlan(updated);
    return updated;
  }

  Future<GoodDayPlan> updatePlan(
    GoodDayPlan plan, {
    String? title,
    DateTime? deadline,
    String? goalId,
    bool clearGoal = false,
  }) async {
    if (title != null && title.trim().isEmpty) {
      throw const FormatException('计划名称不能为空');
    }
    final updated = plan.update(
      title: title,
      deadline: deadline,
      goalId: goalId,
      clearGoal: clearGoal,
    );
    await _writePlan(updated);
    return updated;
  }

  Future<void> deletePlan(GoodDayPlan plan) async {
    await initialize();
    await _taskFile(
      archivedPlansDirectory,
      plan.id,
    ).writeAsString(plan.toMarkdown(), flush: true);
    final activeFile = _taskFile(plansDirectory, plan.id);
    if (await activeFile.exists()) await activeFile.delete();
  }

  Future<GoodDayTask> updateTaskDetails(
    GoodDayTask task, {
    required String title,
    required String notes,
  }) async {
    if (title.trim().isEmpty) {
      throw const FormatException('任务内容不能为空');
    }
    final updated = task.updateDetails(title: title, notes: notes);
    await _writeTask(updated);
    await _syncDaily(await _readTasks(tasksDirectory), _clock());
    return updated;
  }

  Future<GoodDayTask> addSubtask(GoodDayTask task, String title) async {
    final normalizedTitle = title.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    if (normalizedTitle.isEmpty) {
      throw const FormatException('子任务内容不能为空');
    }
    final now = _clock();
    final updated = task.addSubtask(
      GoodDaySubtask(
        id: 'sub_${now.microsecondsSinceEpoch.toRadixString(36)}',
        title: normalizedTitle,
      ),
    );
    await _writeTask(updated);
    await _syncDaily(await _readTasks(tasksDirectory), now);
    return updated;
  }

  Future<GoodDayTask> updateSubtask(
    GoodDayTask task,
    String subtaskId, {
    String? title,
    bool? isCompleted,
  }) async {
    if (title != null && title.trim().isEmpty) {
      throw const FormatException('子任务内容不能为空');
    }
    final now = _clock();
    final updated = task.updateSubtask(
      subtaskId,
      title: title,
      isCompleted: isCompleted,
    );
    await _writeTask(updated);
    await _syncDaily(await _readTasks(tasksDirectory), now);
    return updated;
  }

  Future<GoodDayTask> removeSubtask(GoodDayTask task, String subtaskId) async {
    final now = _clock();
    final updated = task.removeSubtask(subtaskId);
    await _writeTask(updated);
    await _syncDaily(await _readTasks(tasksDirectory), now);
    return updated;
  }

  Future<void> deleteTask(GoodDayTask task) async {
    final now = _clock();
    final deleted = task.markDeleted(now);
    final archiveFile = _taskFile(archiveDirectory, task.id);
    await archiveFile.writeAsString(deleted.toMarkdown(), flush: true);

    final activeFile = _taskFile(tasksDirectory, task.id);
    if (await activeFile.exists()) {
      await activeFile.delete();
    }
    await _syncDaily(await _readTasks(tasksDirectory), now);
  }

  Future<List<TrashItem>> loadTrash() async {
    await initialize();
    final items = <TrashItem>[];
    await for (final entity in archiveDirectory.list()) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.md')) {
        continue;
      }
      try {
        final task = GoodDayTask.fromMarkdown(await entity.readAsString());
        final stat = await entity.stat();
        items.add(
          TrashItem(
            type: TrashItemType.task,
            id: task.id,
            title: task.title,
            deletedAt: task.deletedAt ?? stat.changed,
          ),
        );
      } on FormatException {
        // Keep malformed or hand-written files untouched.
      }
    }
    await _appendArchivedPlans(items);
    await _appendArchivedGoals(items);
    items.sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
    return items;
  }

  Future<void> restoreTrashItem(TrashItem item) async {
    await initialize();
    switch (item.type) {
      case TrashItemType.task:
        final source = _taskFile(archiveDirectory, item.id);
        final restored = GoodDayTask.fromMarkdown(await source.readAsString())
            .restore();
        await _writeTask(restored);
        await source.delete();
        await _syncDaily(await _readTasks(tasksDirectory), _clock());
        return;
      case TrashItemType.plan:
        await _restoreFile(
          _taskFile(archivedPlansDirectory, item.id),
          _taskFile(plansDirectory, item.id),
        );
        return;
      case TrashItemType.goal:
        await _restoreFile(
          _taskFile(archivedGoalsDirectory, item.id),
          _taskFile(goalsDirectory, item.id),
        );
        return;
    }
  }

  Future<void> emptyTrash() async {
    await initialize();
    final removedGoalIds = <String>{};
    await for (final entity in archivedGoalsDirectory.list()) {
      if (entity is File && entity.path.toLowerCase().endsWith('.md')) {
        try {
          removedGoalIds.add(
            GoodDayGoal.fromMarkdown(await entity.readAsString()).id,
          );
        } on FormatException {
          // Malformed files are still deleted as part of an explicit empty.
        }
      }
    }

    if (removedGoalIds.isNotEmpty) {
      for (final task in await _readTasks(tasksDirectory)) {
        if (removedGoalIds.contains(task.goalId)) {
          await _writeTask(task.assignGoal(null));
        }
      }
      for (final plan in await loadPlans()) {
        if (removedGoalIds.contains(plan.goalId)) {
          await _writePlan(plan.update(clearGoal: true));
        }
      }
    }

    await for (final entity in archiveDirectory.list()) {
      if (entity is File && entity.path.toLowerCase().endsWith('.md')) {
        await entity.delete();
      }
    }
    await _deleteContents(archivedPlansDirectory);
    await _deleteContents(archivedGoalsDirectory);
    await _syncDaily(await _readTasks(tasksDirectory), _clock());
  }

  Future<void> _appendArchivedPlans(List<TrashItem> items) async {
    await for (final entity in archivedPlansDirectory.list()) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.md')) {
        continue;
      }
      try {
        final plan = GoodDayPlan.fromMarkdown(await entity.readAsString());
        items.add(
          TrashItem(
            type: TrashItemType.plan,
            id: plan.id,
            title: plan.title,
            deletedAt: (await entity.stat()).changed,
          ),
        );
      } on FormatException {
        // Keep malformed or hand-written files untouched.
      }
    }
  }

  Future<void> _appendArchivedGoals(List<TrashItem> items) async {
    await for (final entity in archivedGoalsDirectory.list()) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.md')) {
        continue;
      }
      try {
        final goal = GoodDayGoal.fromMarkdown(await entity.readAsString());
        items.add(
          TrashItem(
            type: TrashItemType.goal,
            id: goal.id,
            title: goal.name,
            deletedAt: (await entity.stat()).changed,
          ),
        );
      } on FormatException {
        // Keep malformed or hand-written files untouched.
      }
    }
  }

  Future<List<GoodDayTask>> _readTasks(Directory directory) async {
    if (!await directory.exists()) return [];
    final tasks = <GoodDayTask>[];
    await for (final entity in directory.list()) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.md')) {
        continue;
      }
      try {
        tasks.add(GoodDayTask.fromMarkdown(await entity.readAsString()));
      } on FormatException {
        // Malformed or hand-written files remain untouched to prevent data loss.
      }
    }
    _sort(tasks);
    return tasks;
  }

  Future<void> _writeTask(GoodDayTask task) async {
    await tasksDirectory.create(recursive: true);
    await _taskFile(
      tasksDirectory,
      task.id,
    ).writeAsString(task.toMarkdown(), flush: true);
  }

  Future<void> _writeGoal(GoodDayGoal goal) async {
    await goalsDirectory.create(recursive: true);
    await _taskFile(
      goalsDirectory,
      goal.id,
    ).writeAsString(goal.toMarkdown(), flush: true);
  }

  Future<void> _writePlan(GoodDayPlan plan) async {
    await plansDirectory.create(recursive: true);
    await _taskFile(
      plansDirectory,
      plan.id,
    ).writeAsString(plan.toMarkdown(), flush: true);
  }

  Future<void> _syncDaily(List<GoodDayTask> active, DateTime now) async {
    final archived = await _readTasks(archiveDirectory);
    final planned = <GoodDayTask>[
      ...active.where((task) => isSameDay(task.scheduledDate, now)),
      ...archived.where((task) => isSameDay(task.scheduledDate, now)),
    ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final completed =
        active
            .where(
              (task) =>
                  task.completedAt != null && isSameDay(task.completedAt!, now),
            )
            .toList()
          ..sort((a, b) => a.completedAt!.compareTo(b.completedAt!));

    final managed = StringBuffer()
      ..writeln('<!-- goodday:begin -->')
      ..writeln('## 计划');
    if (planned.isEmpty) {
      managed.writeln('\n今天还没有计划。');
    } else {
      for (final task in planned) {
        final archivedTask = task.deletedAt != null;
        final checked = task.isCompleted || archivedTask ? 'x' : ' ';
        final title = _escapeMarkdown(task.title);
        final relativePath = archivedTask
            ? '../Archive/${task.id}.md'
            : '../Tasks/${task.id}.md';
        final label = archivedTask ? '~~$title~~（已删除）' : title;
        managed.writeln(
          '- [$checked] [$label]($relativePath) <!-- goodday:${task.id} -->',
        );
        for (final subtask in task.subtasks) {
          final subtaskChecked = subtask.isCompleted ? 'x' : ' ';
          managed.writeln(
            '  - [$subtaskChecked] ${_escapeMarkdown(subtask.title)}',
          );
        }
      }
    }

    managed.writeln('\n## 今日完成');
    if (completed.isEmpty) {
      managed.writeln('\n今天还没有完成的任务。');
    } else {
      for (final task in completed) {
        final time = task.completedAt!.toLocal();
        managed.writeln(
          '- ${_escapeMarkdown(task.title)} · '
          '${time.hour.toString().padLeft(2, '0')}:'
          '${time.minute.toString().padLeft(2, '0')}',
        );
      }
    }
    managed.write('<!-- goodday:end -->');

    await dailyDirectory.create(recursive: true);
    final dailyFile = _childFile(dailyDirectory, '${dateKey(now)}.md');
    final existing = await dailyFile.exists()
        ? await dailyFile.readAsString()
        : '';
    final next = _replaceManagedSection(existing, managed.toString(), now);
    await dailyFile.writeAsString(next, flush: true);
  }

  String _replaceManagedSection(String existing, String managed, DateTime now) {
    const begin = '<!-- goodday:begin -->';
    const end = '<!-- goodday:end -->';
    final beginIndex = existing.indexOf(begin);
    final endIndex = existing.indexOf(end);
    if (beginIndex >= 0 && endIndex >= beginIndex) {
      final suffixStart = endIndex + end.length;
      return '${existing.substring(0, beginIndex)}$managed'
          '${existing.substring(suffixStart)}';
    }

    final header = existing.trim().isEmpty
        ? '# ${dateKey(now)}\n\n> Good Day 自动维护下方计划区域；你可以在区域外自由记录。\n\n'
        : '${existing.trimRight()}\n\n';
    return '$header$managed\n';
  }

  static void _sort(List<GoodDayTask> tasks) {
    tasks.sort((a, b) {
      if (a.isCompleted != b.isCompleted) return a.isCompleted ? 1 : -1;
      return b.createdAt.compareTo(a.createdAt);
    });
  }

  static void _sortPlans(List<GoodDayPlan> plans) {
    plans.sort((a, b) {
      if (a.isCompleted != b.isCompleted) return a.isCompleted ? 1 : -1;
      final deadline = a.deadline.compareTo(b.deadline);
      return deadline == 0 ? a.createdAt.compareTo(b.createdAt) : deadline;
    });
  }

  static String _escapeMarkdown(String value) => value
      .replaceAll(r'\', r'\\')
      .replaceAll('[', r'\[')
      .replaceAll(']', r'\]');

  static Directory _childDirectory(Directory parent, String name) =>
      Directory('${parent.path}${Platform.pathSeparator}$name');

  static File _childFile(Directory parent, String name) =>
      File('${parent.path}${Platform.pathSeparator}$name');

  static File _taskFile(Directory parent, String id) =>
      _childFile(parent, '$id.md');

  static Future<void> _copyDirectory(
    Directory source,
    Directory destination,
  ) async {
    if (!await source.exists()) return;
    await destination.create(recursive: true);
    await for (final entity in source.list()) {
      final name = entity.uri.pathSegments
          .where((segment) => segment.isNotEmpty)
          .last;
      if (entity is Directory) {
        await _copyDirectory(entity, _childDirectory(destination, name));
      } else if (entity is File) {
        final target = _childFile(destination, name);
        if (!await target.exists()) await entity.copy(target.path);
      }
    }
  }

  static Future<void> _restoreFile(File source, File destination) async {
    if (!await source.exists()) {
      throw const FileSystemException('垃圾桶中的文件不存在');
    }
    await destination.parent.create(recursive: true);
    await source.copy(destination.path);
    await source.delete();
  }

  static Future<void> _deleteContents(Directory directory) async {
    if (!await directory.exists()) return;
    await for (final entity in directory.list()) {
      if (entity is Directory) {
        await entity.delete(recursive: true);
      } else if (entity is File) {
        await entity.delete();
      }
    }
  }

  static bool _isFileSystemRoot(String path) {
    final trimmed = path.endsWith(Platform.pathSeparator)
        ? path.substring(0, path.length - 1)
        : path;
    if (Platform.isWindows) {
      return RegExp(r'^[a-zA-Z]:$').hasMatch(trimmed);
    }
    return trimmed.isEmpty;
  }
}
