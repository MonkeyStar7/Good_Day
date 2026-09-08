import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/good_day_task.dart';

class VaultRepository {
  VaultRepository(this.vaultDirectory, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final Directory vaultDirectory;
  final DateTime Function() _clock;

  Directory get tasksDirectory => _childDirectory(vaultDirectory, 'Tasks');
  Directory get dailyDirectory => _childDirectory(vaultDirectory, 'Daily');
  Directory get archiveDirectory => _childDirectory(vaultDirectory, 'Archive');

  static Future<VaultRepository> createDefault() async {
    final documents = await getApplicationDocumentsDirectory();
    return VaultRepository(_childDirectory(documents, 'Good Day Vault'));
  }

  Future<void> initialize() async {
    await tasksDirectory.create(recursive: true);
    await dailyDirectory.create(recursive: true);
    await archiveDirectory.create(recursive: true);
  }

  Future<bool> hasVaultData() async {
    for (final directory in [
      tasksDirectory,
      dailyDirectory,
      archiveDirectory,
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

    for (final name in ['Tasks', 'Daily', 'Archive']) {
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
