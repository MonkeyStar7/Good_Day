import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'safe_file.dart';
import 'vault_backups.dart';

import '../models/good_day_goal.dart';
import '../models/good_day_plan.dart';
import '../models/good_day_task.dart';
import '../models/good_day_event.dart';
import '../models/task_series.dart';
import '../models/reminder_item.dart';

part 'reminder_repository.dart';

enum TrashItemType { task, plan, goal, event, reminder }

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
  DateTime get now => _clock();
  static int _idSequence = 0;
  static String _newId(String prefix, DateTime time) =>
      '${prefix}_${time.microsecondsSinceEpoch.toRadixString(36)}_${(_idSequence++).toRadixString(36)}';
  final OperationQueue _operations = OperationQueue();
  final Set<String> _unreadableFiles = {};
  RandomAccessFile? _session;
  bool usesReminderWorkflow = false;
  final _reminderChanges = StreamController<void>.broadcast();
  Stream<void> get reminderChanges => _reminderChanges.stream;

  Future<void> acquireSession() async {
    if (_session != null) return;
    final directory = _childDirectory(vaultDirectory, '.goodday');
    await directory.create(recursive: true);
    final file = await _childFile(
      directory,
      'session.lock',
    ).open(mode: FileMode.append);
    try {
      await file.lock(FileLock.exclusive);
      _session = file;
    } catch (_) {
      await file.close();
      throw FileSystemException(
        '这个数据文件夹已被另一个 Good Day 窗口使用，请回到原窗口',
        vaultDirectory.path,
      );
    }
  }

  Future<void> releaseSession() async {
    await _session?.close();
    _session = null;
  }

  List<String> get unreadableFiles => List.unmodifiable(_unreadableFiles);
  late final VaultBackups backups = VaultBackups(vaultDirectory, clock: _clock);

  Future<T> _writeOperation<T>(Future<T> Function() operation) =>
      _operations.run(() async {
        await initialize();
        await backups.ensureDaily();
        return operation();
      });

  Future<void> get idle => _operations.idle;
  Future<void> restoreBackup(String id) => _operations.run(() async {
    await backups.restore(id);
    _unreadableFiles.clear();
    _reminderChanges.add(null);
  });
  Future<VaultBackup> createBackup() => _operations.run(backups.createManual);

  Future<GoodDayTask> _readTaskFile(File file) async {
    final task = GoodDayTask.fromMarkdown(await file.readAsString());
    _validateRecordFile(file, task.id);
    return task;
  }

  Future<GoodDayTask> _currentTask(GoodDayTask task) =>
      _readTaskFile(_taskFile(tasksDirectory, task.id));
  Future<GoodDayPlan> _currentPlan(GoodDayPlan plan) async {
    final file = _taskFile(plansDirectory, plan.id);
    final current = GoodDayPlan.fromMarkdown(await file.readAsString());
    _validateRecordFile(file, current.id);
    return current;
  }

  Future<GoodDayGoal> _currentGoal(GoodDayGoal goal) async {
    final file = _taskFile(goalsDirectory, goal.id);
    final current = GoodDayGoal.fromMarkdown(await file.readAsString());
    _validateRecordFile(file, current.id);
    return current;
  }

  Directory get tasksDirectory => _childDirectory(vaultDirectory, 'Tasks');
  Directory get dailyDirectory => _childDirectory(vaultDirectory, 'Daily');
  Directory get archiveDirectory => _childDirectory(vaultDirectory, 'Archive');
  Directory get archivedPlansDirectory =>
      _childDirectory(archiveDirectory, 'Plans');
  Directory get archivedGoalsDirectory =>
      _childDirectory(archiveDirectory, 'Goals');
  Directory get goalsDirectory => _childDirectory(vaultDirectory, 'Goals');
  Directory get plansDirectory => _childDirectory(vaultDirectory, 'Plans');
  Directory get eventsDirectory => _childDirectory(vaultDirectory, 'Events');
  Directory get taskSeriesDirectory =>
      _childDirectory(vaultDirectory, 'TaskSeries');
  Directory get remindersDirectory =>
      _childDirectory(vaultDirectory, 'Reminders');
  Directory get archivedEventsDirectory =>
      _childDirectory(archiveDirectory, 'Events');

  static Future<VaultRepository> createDefault() async {
    final documents = await getApplicationDocumentsDirectory();
    return VaultRepository(
      _childDirectory(_childDirectory(documents, 'Good Day'), 'MD'),
    );
  }

  Future<void> initialize() async {
    await tasksDirectory.create(recursive: true);
    await dailyDirectory.create(recursive: true);
    await archiveDirectory.create(recursive: true);
    await archivedPlansDirectory.create(recursive: true);
    await archivedGoalsDirectory.create(recursive: true);
    await goalsDirectory.create(recursive: true);
    await plansDirectory.create(recursive: true);
    await eventsDirectory.create(recursive: true);
    await taskSeriesDirectory.create(recursive: true);
    await archivedEventsDirectory.create(recursive: true);
    await remindersDirectory.create(recursive: true);
    await backups.recoverPendingRestore();
  }

  Future<bool> hasVaultData() async {
    for (final directory in [
      tasksDirectory,
      dailyDirectory,
      archiveDirectory,
      goalsDirectory,
      plansDirectory,
      eventsDirectory,
      taskSeriesDirectory,
      remindersDirectory,
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

  Future<void> copyDataTo(Directory targetVault) => _writeOperation(() async {
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

    for (final name in [
      'Tasks',
      'Daily',
      'Archive',
      'Goals',
      'Plans',
      'Events',
      'TaskSeries',
      'Reminders',
    ]) {
      await _copyDirectory(
        _childDirectory(vaultDirectory, name),
        _childDirectory(targetVault, name),
      );
    }
    await _copyDirectory(
      _childDirectory(vaultDirectory, '.goodday'),
      _childDirectory(targetVault, '.goodday'),
    );
  });

  Future<void> deleteManagedData() => _writeOperation(() async {
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
      eventsDirectory,
      taskSeriesDirectory,
      remindersDirectory,
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
  });

  Future<List<GoodDayTask>> loadTasks() => _writeOperation(() async {
    await initialize();
    await _ensureRepeatingTasks();
    final tasks = await _readTasks(tasksDirectory);
    final now = _clock();

    _sort(tasks);
    await _syncDaily(tasks, now);
    return tasks;
  });

  Future<List<GoodDayEvent>> loadEvents() => _operations.run(() async {
    if (!await eventsDirectory.exists()) return [];
    final events = <GoodDayEvent>[];
    await for (final file in eventsDirectory.list(followLinks: false)) {
      if (file is! File || !file.path.toLowerCase().endsWith('.md')) continue;
      try {
        final event = GoodDayEvent.fromMarkdown(await file.readAsString());
        if (file.absolute.path.toLowerCase() !=
            _eventFile(event.id).absolute.path.toLowerCase()) {
          throw const FormatException('事件标识与文件名不一致');
        }
        if (event.deletedAt == null) events.add(event);
        _unreadableFiles.remove(file.path);
      } on FormatException {
        _unreadableFiles.add(file.path);
      } on FileSystemException {
        _unreadableFiles.add(file.path);
      }
    }
    return events;
  });

  Future<List<GoodDayTask>> loadTaskReminders() =>
      _operations.run(() => _readTasks(tasksDirectory));

  Future<GoodDayEvent?> prepareTaskReminder(String taskId, DateTime now) =>
      _writeOperation(() async {
        final file = _taskFile(tasksDirectory, taskId);
        if (!await file.exists()) return null;
        final task = await _readTaskFile(file);
        final reminder = task.activeReminder;
        final occurrence = reminder?.dueOccurrence(now);
        if (reminder == null || occurrence == null) return null;
        final prepared = reminder.pending(occurrence);
        await _writeTask(task.copyWith(reminder: prepared));
        return prepared;
      });

  Future<void> resolveTaskReminder(
    String taskId,
    DateTime occurrence, {
    DateTime? snoozeUntil,
  }) => _writeOperation(() async {
    final task = await _readTaskFile(_taskFile(tasksDirectory, taskId));
    final reminder = task.activeReminder;
    if (reminder == null ||
        !reminder.enabled ||
        reminder.pendingOccurrence != occurrence) {
      throw const FileSystemException('待办提醒已发生变化，请重新查看');
    }
    if (snoozeUntil != null && !snoozeUntil.isAfter(_clock())) {
      throw const FormatException('稍后提醒时间必须在未来');
    }
    await _writeTask(
      task.copyWith(
        reminder: reminder.resolve(occurrence, snoozeUntil: snoozeUntil),
      ),
    );
  });

  File _eventFile(String id, {bool archived = false}) {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id)) {
      throw const FormatException('事件标识无效');
    }
    return _taskFile(archived ? archivedEventsDirectory : eventsDirectory, id);
  }

  Future<GoodDayEvent> saveEvent(GoodDayEvent draft) =>
      _writeOperation(() async {
        final isNew = draft.id.isEmpty;
        var event = draft;
        if (isNew) {
          event = GoodDayEvent(
            id: _newId('event', _clock()),
            title: draft.title.trim(),
            notes: draft.notes.trim(),
            startsAt: draft.startsAt,
            repeat: draft.repeat,
            reminderMinutes: draft.reminderMinutes,
            enabled: draft.enabled,
          );
        } else {
          final current = GoodDayEvent.fromMarkdown(
            await _eventFile(draft.id).readAsString(),
          );
          event = current.edit(
            title: draft.title,
            notes: draft.notes,
            startsAt: draft.startsAt,
            repeat: draft.repeat,
            reminderMinutes: draft.reminderMinutes,
            enabled: draft.enabled,
          );
        }
        // Validate before touching live data, including values from external callers.
        GoodDayEvent.fromMarkdown(event.toMarkdown());
        await SafeFile.write(_eventFile(event.id), event.toMarkdown());
        return event;
      });

  Future<GoodDayEvent?> prepareEventReminder(String id, DateTime now) =>
      _writeOperation(() async {
        final file = _eventFile(id);
        if (!await file.exists()) return null;
        final current = GoodDayEvent.fromMarkdown(await file.readAsString());
        final occurrence = current.dueOccurrence(now);
        if (occurrence == null) return null;
        final prepared = current.pending(occurrence);
        if (prepared.toMarkdown() != current.toMarkdown()) {
          await SafeFile.write(file, prepared.toMarkdown());
        }
        return prepared;
      });

  Future<void> resolveEventReminder(
    String id,
    DateTime occurrence, {
    DateTime? snoozeUntil,
  }) => _writeOperation(() async {
    final file = _eventFile(id);
    final current = GoodDayEvent.fromMarkdown(await file.readAsString());
    if (!current.enabled || current.pendingOccurrence != occurrence) {
      throw const FileSystemException('事件已发生变化，请重新查看事件');
    }
    if (snoozeUntil != null && !snoozeUntil.isAfter(_clock())) {
      throw const FormatException('稍后提醒时间必须在未来');
    }
    await SafeFile.write(
      file,
      current.resolve(occurrence, snoozeUntil: snoozeUntil).toMarkdown(),
    );
  });

  Future<void> deleteEvent(GoodDayEvent event) => _writeOperation(() async {
    final file = _eventFile(event.id);
    final current = GoodDayEvent.fromMarkdown(await file.readAsString());
    await SafeFile.write(
      _eventFile(event.id, archived: true),
      current.markDeleted(_clock()).toMarkdown(),
    );
    await file.delete();
  });

  Future<GoodDayTask> addTask(String title) =>
      addPeriodTask(title, TaskPeriod.day);

  Future<String> _resolveTaskTitle(String title, {GoodDayTask? current}) async {
    final normalized = title.trim();
    if (normalized.isNotEmpty) return normalized;
    final pattern = RegExp(r'^未命名([1-9][0-9]*)$');
    if (current != null && pattern.hasMatch(current.title)) {
      return current.title;
    }
    final tasks = [
      ...await _readTasks(tasksDirectory),
      ...await _readTasks(archiveDirectory),
      for (final series in await _readTaskSeries()) series.template,
    ];
    var highest = 0;
    for (final task in tasks) {
      final match = pattern.firstMatch(task.title);
      final number = match == null ? null : int.tryParse(match.group(1)!);
      if (number != null && number > highest) highest = number;
    }
    return '未命名${highest + 1}';
  }

  Future<GoodDayTask> addPeriodTask(String title, TaskPeriod period) =>
      _writeOperation(() async {
        if (period == TaskPeriod.backlog) {
          throw const FormatException('请选择一个安排周期');
        }
        final resolvedTitle = await _resolveTaskTitle(title);
        final now = _clock();
        final task = GoodDayTask(
          id: _newId('gd', now),
          title: resolvedTitle,
          createdAt: now,
          scheduledDate: now,
          period: period,
        );
        await _writeTask(task);
        await _syncDaily(await _readTasks(tasksDirectory), now);
        return task;
      });

  Future<GoodDayTask> setCompleted(GoodDayTask task, bool completed) =>
      _writeOperation(() async {
        task = await _currentTask(task);
        final now = _clock();
        final updated = task.setCompleted(completed, now);
        await _writeTask(updated);
        if (completed && updated.seriesId != null && !usesReminderWorkflow) {
          final seriesFile = _seriesFile(updated.seriesId!);
          if (await seriesFile.exists()) {
            final series = TaskSeries.fromMarkdown(
              await seriesFile.readAsString(),
            );
            final next = series.schedule.nextOccurrenceAfter(
              updated.occurrenceDate ?? updated.scheduledDate,
            );
            if (series.enabled && next != null) {
              await _generateOccurrence(series, next);
            }
          }
        }
        await _syncDaily(await _readTasks(tasksDirectory), now);
        return updated;
      });

  File _seriesFile(String id) {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id)) {
      throw const FormatException('重复任务标识无效');
    }
    return _taskFile(taskSeriesDirectory, id);
  }

  Future<List<TaskSeries>> loadTaskSeries() => _operations.run(_readTaskSeries);
  Future<List<TaskSeries>> _readTaskSeries() async {
    if (!await taskSeriesDirectory.exists()) return [];
    final result = <TaskSeries>[];
    await for (final file in taskSeriesDirectory.list(followLinks: false)) {
      if (file is! File || !file.path.endsWith('.md')) continue;
      try {
        final series = TaskSeries.fromMarkdown(await file.readAsString());
        if (file.absolute.path.toLowerCase() !=
            _seriesFile(series.id).absolute.path.toLowerCase()) {
          throw const FormatException('重复任务文件名不一致');
        }
        result.add(series);
        _unreadableFiles.remove(file.path);
      } on FormatException {
        _unreadableFiles.add(file.path);
      } on FileSystemException {
        _unreadableFiles.add(file.path);
      }
    }
    return result;
  }

  Future<void> _ensureRepeatingTasks() async {
    if (usesReminderWorkflow) {
      return; // Old tasks remain historical, not active.
    }
    final now = _clock();
    final today = DateTime(now.year, now.month, now.day);
    for (final series in await _readTaskSeries()) {
      if (!series.enabled) continue;
      final due = series.schedule.latestOccurrenceAtOrBefore(today);
      if (due != null) await _generateOccurrence(series, due);
    }
  }

  Future<void> _generateOccurrence(TaskSeries series, DateTime date) async {
    if (!series.enabled ||
        (series.generatedThrough != null &&
            !date.isAfter(series.generatedThrough!))) {
      return;
    }
    final id = '${series.id}_${dateKey(date).replaceAll('-', '')}';
    // Deterministic IDs and a saved cursor prevent duplicates after restart,
    // concurrent refresh, trash deletion, or a failed cursor write.
    final file = _taskFile(tasksDirectory, id);
    if (!await file.exists() &&
        !await _taskFile(archiveDirectory, id).exists()) {
      final base = series.template;
      final task = GoodDayTask(
        id: id,
        title: base.title,
        notes: base.notes,
        createdAt: _clock(),
        scheduledDate: date,
        originalDate: date,
        repeat: base.repeat,
        seriesId: series.id,
        repeatAnchor: base.repeatAnchor,
        occurrenceDate: date,
        goalId: base.goalId,
        period: base.period,
        reminder: _reminderForDate(base, date, id),
        subtasks: [
          for (final step in base.subtasks)
            GoodDaySubtask(id: step.id, title: step.title),
        ],
      );
      await _writeTask(task);
    }
    await SafeFile.write(
      _seriesFile(series.id),
      series.advance(date).toMarkdown(),
    );
  }

  Future<GoodDayTask> saveScheduledTask({
    GoodDayTask? task,
    required String title,
    required String notes,
    required DateTime date,
    required EventRepeat repeat,
  }) => _writeOperation(
    () => _saveScheduledTask(
      task: task,
      title: title,
      notes: notes,
      date: date,
      repeat: repeat,
    ),
  );

  Future<GoodDayTask> rescheduleTaskPeriod(
    GoodDayTask task,
    TaskPeriod period,
  ) => _writeOperation(() async {
    if (period == TaskPeriod.backlog) throw const FormatException('请选择一个安排周期');
    final current = await _currentTask(task);
    if (current.isCompleted) throw const FormatException('已完成记录无需重新安排');
    final date = _clock();
    final reminder = current.reminder;
    final reminderAt = reminder == null
        ? null
        : reminder.startsAt.isAfter(date) &&
              period.contains(reminder.startsAt, date)
        ? reminder.startsAt
        : DateTime(
            date.year,
            date.month,
            date.day,
            reminder.startsAt.hour,
            reminder.startsAt.minute,
          );
    return _saveScheduledTask(
      task: current,
      title: current.title,
      notes: current.notes,
      date: date,
      repeat: current.repeat,
      period: period,
      preserveOriginalDate: true,
      updateReminder: true,
      reminderAt: reminderAt,
      reminderIntervalMinutes:
          (reminder?.intervalMinutes ?? 0) <
              period.end(date).difference(period.start(date)).inMinutes
          ? (reminder?.intervalMinutes ?? 0)
          : 0,
      pausePastReminder: true,
    );
  });

  Future<GoodDayTask> saveTaskOptions({
    required GoodDayTask task,
    required EventRepeat repeat,
    required DateTime? reminderAt,
    int reminderIntervalMinutes = 0,
  }) => _writeOperation(() async {
    final current = await _currentTask(task);
    if (reminderAt != null &&
        (reminderAt != current.reminder?.startsAt ||
            reminderIntervalMinutes !=
                (current.reminder?.intervalMinutes ?? 0))) {
      final maxInterval = current.period
          .end(current.scheduledDate)
          .difference(current.period.start(current.scheduledDate))
          .inMinutes;
      if (!reminderAt.isAfter(_clock()) ||
          !current.period.contains(reminderAt, current.scheduledDate)) {
        throw const FormatException('提醒时间必须在当前任务周期内，并晚于现在');
      }
      if (reminderIntervalMinutes < 0 ||
          reminderIntervalMinutes >= maxInterval) {
        throw const FormatException('重复提醒间隔必须小于任务周期');
      }
    }
    return _saveScheduledTask(
      task: current,
      title: current.title,
      notes: current.notes,
      date: current.scheduledDate,
      repeat: repeat,
      updateReminder: true,
      reminderAt: reminderAt,
      reminderIntervalMinutes: reminderIntervalMinutes,
    );
  });

  GoodDayEvent? _reminderForDate(GoodDayTask base, DateTime date, String id) {
    final reminder = base.reminder;
    if (reminder == null) return null;
    final calendarAnchor = reminder.calendarAnchor ?? reminder.startsAt;
    final offset =
        DateTime.utc(
              reminder.startsAt.year,
              reminder.startsAt.month,
              reminder.startsAt.day,
            )
            .difference(
              DateTime.utc(
                base.scheduledDate.year,
                base.scheduledDate.month,
                base.scheduledDate.day,
              ),
            )
            .inDays;
    var reminderDate = DateTime(date.year, date.month, date.day + offset);
    if (reminder.expiresAt != null &&
        !(offset == 0 && base.period.contains(date, base.scheduledDate))) {
      reminderDate = switch (base.period) {
        TaskPeriod.week =>
          base.period
              .start(date)
              .add(Duration(days: calendarAnchor.weekday - 1)),
        TaskPeriod.month => DateTime(
          date.year,
          date.month,
          calendarAnchor.day.clamp(
            1,
            DateTime(date.year, date.month + 1, 0).day,
          ),
        ),
        TaskPeriod.year => DateTime(
          date.year,
          calendarAnchor.month,
          calendarAnchor.day.clamp(
            1,
            DateTime(date.year, calendarAnchor.month + 1, 0).day,
          ),
        ),
        _ => reminderDate,
      };
    }
    return GoodDayEvent(
      id: 'task_$id',
      intervalMinutes: reminder.intervalMinutes,
      expiresAt: reminder.expiresAt == null ? null : base.period.end(date),
      calendarAnchor: calendarAnchor,
      title: base.title,
      notes: base.notes,
      startsAt: DateTime(
        reminderDate.year,
        reminderDate.month,
        reminderDate.day,
        reminder.startsAt.hour,
        reminder.startsAt.minute,
      ),
    );
  }

  GoodDayTask _configureReminder(
    GoodDayTask task,
    DateTime? time,
    int interval,
  ) {
    if (time == null) return task.copyWith(clearReminder: true);
    if (task.reminder?.startsAt == time &&
        task.reminder?.intervalMinutes == interval &&
        ((interval == 0 && task.reminder?.expiresAt == null) ||
            task.reminder?.expiresAt == task.period.end(task.scheduledDate))) {
      return task;
    }
    return task.copyWith(
      reminder: GoodDayEvent(
        id: 'task_${task.id}',
        intervalMinutes: interval,
        expiresAt: task.period.end(task.scheduledDate),
        calendarAnchor: time,
        title: task.title,
        notes: task.notes,
        startsAt: time,
      ),
    );
  }

  Future<void> _writeReminderOptions(
    GoodDayTask current,
    GoodDayTask updated,
  ) async {
    final changes = <File, String>{
      _taskFile(tasksDirectory, current.id): updated.toMarkdown(),
    };
    if (current.seriesId != null && !current.isCompleted) {
      final file = _seriesFile(current.seriesId!);
      if (await file.exists()) {
        final series = TaskSeries.fromMarkdown(await file.readAsString());
        if (series.enabled) {
          changes[file] = TaskSeries(
            id: series.id,
            template: updated,
            enabled: true,
            generatedThrough: series.generatedThrough,
          ).toMarkdown();
          final today = DateTime(_clock().year, _clock().month, _clock().day);
          for (final future in await _readTasks(tasksDirectory)) {
            if (future.id == updated.id ||
                future.seriesId != series.id ||
                future.isCompleted ||
                !future.scheduledDate.isAfter(today)) {
              continue;
            }
            changes[_taskFile(tasksDirectory, future.id)] = future
                .copyWith(
                  reminder: _reminderForDate(
                    updated,
                    future.scheduledDate,
                    future.id,
                  ),
                  clearReminder: updated.reminder == null,
                )
                .toMarkdown();
          }
        }
      }
    }
    final originals = <File, String>{};
    for (final file in changes.keys) {
      originals[file] = await file.readAsString();
    }
    final written = <File>[];
    try {
      for (final entry in changes.entries) {
        await SafeFile.write(entry.key, entry.value);
        written.add(entry.key);
      }
    } catch (_) {
      for (final file in written.reversed) {
        await SafeFile.write(file, originals[file]!);
      }
      rethrow;
    }
  }

  Future<GoodDayTask> _saveScheduledTask({
    GoodDayTask? task,
    required String title,
    required String notes,
    required DateTime date,
    required EventRepeat repeat,
    TaskPeriod? period,
    bool preserveOriginalDate = false,
    bool pausePastReminder = false,
    bool updateReminder = false,
    DateTime? reminderAt,
    int reminderIntervalMinutes = 0,
  }) async {
    var current = task == null ? null : await _currentTask(task);
    title = await _resolveTaskTitle(title, current: current);
    final selectedPeriod = period ?? current?.period ?? TaskPeriod.day;
    final normalized = DateTime(date.year, date.month, date.day);
    final changed =
        current == null ||
        !isSameDay(current.scheduledDate, normalized) ||
        current.repeat != repeat ||
        current.period != selectedPeriod;
    if (current != null && current.isCompleted && changed) {
      throw const FormatException('已完成的记录保留原日期，请新建任务安排下一次');
    }
    if (!changed) {
      if (updateReminder) {
        final updated = _configureReminder(
          current,
          reminderAt,
          reminderIntervalMinutes,
        );
        await _writeReminderOptions(current, updated);
        return updated;
      }
      final updated = current.updateDetails(title: title, notes: notes);
      if (current.seriesId != null &&
          await _seriesFile(current.seriesId!).exists()) {
        final series = TaskSeries.fromMarkdown(
          await _seriesFile(current.seriesId!).readAsString(),
        );
        final updatedSeries = TaskSeries(
          id: series.id,
          template: series.template.updateDetails(title: title, notes: notes),
          enabled: series.enabled,
          generatedThrough: series.generatedThrough,
        );
        await SafeFile.write(
          _seriesFile(series.id),
          updatedSeries.toMarkdown(),
        );
        for (final future in await _readTasks(tasksDirectory)) {
          if (future.seriesId == series.id &&
              !future.isCompleted &&
              future.scheduledDate.isAfter(_clock())) {
            await _writeTask(future.updateDetails(title: title, notes: notes));
          }
        }
      }
      await _writeTask(updated);
      await _syncDaily(await _readTasks(tasksDirectory), _clock());
      return updated;
    }
    final previous = current;
    final now = _clock();
    final seriesId = repeat == EventRepeat.once ? null : _newId('series', now);
    final first = RepeatSchedule(normalized, repeat).nextOccurrenceAfter(
      normalized.subtract(const Duration(microseconds: 1)),
    )!;
    current ??= GoodDayTask(
      id: seriesId == null
          ? _newId('gd', now)
          : '${seriesId}_${dateKey(first).replaceAll('-', '')}',
      title: title,
      createdAt: now,
      scheduledDate: first,
    );
    var saved = current.copyWith(
      title: title.trim(),
      notes: notes.trim(),
      scheduledDate: first,
      originalDate: preserveOriginalDate
          ? current.originalScheduledDate
          : first,
      period: selectedPeriod,
      repeat: repeat,
      seriesId: seriesId,
      repeatAnchor: normalized,
      occurrenceDate: first,
      clearSeries: seriesId == null,
    );
    if (updateReminder) {
      saved = _configureReminder(saved, reminderAt, reminderIntervalMinutes);
    }
    if (saved.reminder != null && !isSameDay(normalized, first)) {
      saved = saved.copyWith(
        reminder: _reminderForDate(
          saved.copyWith(scheduledDate: normalized),
          first,
          saved.id,
        ),
      );
    }
    if (pausePastReminder &&
        saved.reminder != null &&
        !saved.reminder!.startsAt.isAfter(now)) {
      saved = saved.copyWith(
        reminder: saved.reminder!.edit(
          title: saved.title,
          notes: saved.notes,
          startsAt: saved.reminder!.startsAt,
          repeat: EventRepeat.once,
          reminderMinutes: 0,
          enabled: false,
        ),
      );
    }
    await _writeTask(saved);
    try {
      if (seriesId != null) {
        await SafeFile.write(
          _seriesFile(seriesId),
          TaskSeries(
            id: seriesId,
            template: saved,
            enabled: true,
            generatedThrough: first,
          ).toMarkdown(),
        );
      }
    } catch (_) {
      if (previous != null) {
        await _writeTask(previous);
      } else {
        await _taskFile(tasksDirectory, saved.id).delete();
      }
      rethrow;
    }
    if (previous?.seriesId != null) {
      await _stopTaskSeries(previous!.seriesId!, exceptId: saved.id);
    }
    await _syncDaily(await _readTasks(tasksDirectory), now);
    return saved;
  }

  Future<void> stopTaskSeries(String id) =>
      _writeOperation(() => _stopTaskSeries(id));
  Future<void> _stopTaskSeries(String id, {String? exceptId}) async {
    final file = _seriesFile(id);
    if (!await file.exists()) return;
    final series = TaskSeries.fromMarkdown(await file.readAsString());
    await SafeFile.write(file, series.stop().toMarkdown());
    final now = _clock();
    final today = DateTime(now.year, now.month, now.day);
    for (final task in await _readTasks(tasksDirectory)) {
      if (task.seriesId != id ||
          task.id == exceptId ||
          task.isCompleted ||
          !task.scheduledDate.isAfter(today)) {
        continue;
      }
      await SafeFile.write(
        _taskFile(archiveDirectory, task.id),
        task.markDeleted(now).toMarkdown(),
      );
      await _taskFile(tasksDirectory, task.id).delete();
    }
    await _syncDaily(await _readTasks(tasksDirectory), now);
  }

  Future<GoodDayTask> assignTaskGoal(GoodDayTask task, String? goalId) =>
      _writeOperation(() async {
        task = await _currentTask(task);
        final updated = task.assignGoal(goalId);
        await _writeTask(updated);
        await _updateSeriesTemplate(updated);
        await _syncDaily(await _readTasks(tasksDirectory), _clock());
        return updated;
      });

  Future<List<GoodDayGoal>> loadGoals() async {
    await initialize();
    final goals = <GoodDayGoal>[];
    await for (final entity in goalsDirectory.list()) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.md')) {
        continue;
      }
      try {
        final goal = GoodDayGoal.fromMarkdown(await entity.readAsString());
        _validateRecordFile(entity, goal.id);
        goals.add(goal);
        _unreadableFiles.remove(entity.path);
      } on FormatException {
        _unreadableFiles.add(entity.path);
      } on FileSystemException {
        _unreadableFiles.add(entity.path);
      }
    }
    goals.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return goals;
  }

  Future<GoodDayGoal> addGoal({
    required String name,
    required String description,
    required int colorValue,
  }) => _writeOperation(() async {
    final normalizedName = name.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    if (normalizedName.isEmpty) throw const FormatException('目标名称不能为空');
    final now = _clock();
    final goal = GoodDayGoal(
      id: _newId('goal', now),
      name: normalizedName,
      description: description,
      colorValue: colorValue,
      createdAt: now,
    );
    await _writeGoal(goal);
    return goal;
  });

  Future<GoodDayGoal> updateGoal(
    GoodDayGoal goal, {
    required String name,
    required String description,
    required int colorValue,
  }) => _writeOperation(() async {
    goal = await _currentGoal(goal);
    if (name.trim().isEmpty) throw const FormatException('目标名称不能为空');
    final updated = goal.update(
      name: name,
      description: description,
      colorValue: colorValue,
    );
    await _writeGoal(updated);
    return updated;
  });

  Future<void> deleteGoal(GoodDayGoal goal) => _writeOperation(() async {
    goal = await _currentGoal(goal);
    await initialize();
    await SafeFile.write(
      _taskFile(archivedGoalsDirectory, goal.id),
      goal.toMarkdown(),
    );
    final activeFile = _taskFile(goalsDirectory, goal.id);
    if (await activeFile.exists()) await activeFile.delete();
  });

  Future<List<GoodDayPlan>> loadPlans() async {
    await initialize();
    final plans = <GoodDayPlan>[];
    await for (final entity in plansDirectory.list()) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.md')) {
        continue;
      }
      try {
        final plan = GoodDayPlan.fromMarkdown(await entity.readAsString());
        _validateRecordFile(entity, plan.id);
        plans.add(plan);
        _unreadableFiles.remove(entity.path);
      } on FormatException {
        _unreadableFiles.add(entity.path);
      } on FileSystemException {
        _unreadableFiles.add(entity.path);
      }
    }
    _sortPlans(plans);
    return plans;
  }

  Future<GoodDayPlan> addPlan({
    required String title,
    required DateTime deadline,
    String? goalId,
  }) => _writeOperation(() async {
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
      id: _newId('plan', now),
      title: normalizedTitle,
      createdAt: now,
      deadline: normalizedDeadline,
      goalId: goalId,
    );
    await _writePlan(plan);
    return plan;
  });

  Future<GoodDayPlan> setPlanCompleted(GoodDayPlan plan, bool completed) =>
      _writeOperation(() async {
        plan = await _currentPlan(plan);
        final updated = plan.setCompleted(completed, _clock());
        await _writePlan(updated);
        return updated;
      });

  Future<GoodDayPlan> updatePlan(
    GoodDayPlan plan, {
    String? title,
    DateTime? deadline,
    String? goalId,
    bool clearGoal = false,
  }) => _writeOperation(() async {
    plan = await _currentPlan(plan);
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
  });

  Future<void> deletePlan(GoodDayPlan plan) => _writeOperation(() async {
    plan = await _currentPlan(plan);
    await initialize();
    await SafeFile.write(
      _taskFile(archivedPlansDirectory, plan.id),
      plan.toMarkdown(),
    );
    final activeFile = _taskFile(plansDirectory, plan.id);
    if (await activeFile.exists()) await activeFile.delete();
  });

  Future<GoodDayTask> updateTaskDetails(
    GoodDayTask task, {
    required String title,
    required String notes,
  }) => _writeOperation(() async {
    task = await _currentTask(task);
    title = await _resolveTaskTitle(title, current: task);
    final updated = task.updateDetails(title: title, notes: notes);
    await _writeTask(updated);
    await _updateSeriesTemplate(updated);
    await _syncDaily(await _readTasks(tasksDirectory), _clock());
    return updated;
  });

  Future<GoodDayTask> addSubtask(GoodDayTask task, String title) =>
      _writeOperation(() async {
        task = await _currentTask(task);
        final normalizedTitle = title
            .replaceAll(RegExp(r'[\r\n]+'), ' ')
            .trim();
        if (normalizedTitle.isEmpty) {
          throw const FormatException('子任务内容不能为空');
        }
        final now = _clock();
        final updated = task.addSubtask(
          GoodDaySubtask(id: _newId('sub', now), title: normalizedTitle),
        );
        await _writeTask(updated);
        await _updateSeriesTemplate(updated);
        await _syncDaily(await _readTasks(tasksDirectory), now);
        return updated;
      });

  Future<GoodDayTask> updateSubtask(
    GoodDayTask task,
    String subtaskId, {
    String? title,
    bool? isCompleted,
  }) => _writeOperation(() async {
    task = await _currentTask(task);
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
    await _updateSeriesTemplate(updated);
    await _syncDaily(await _readTasks(tasksDirectory), now);
    return updated;
  });

  Future<GoodDayTask> removeSubtask(GoodDayTask task, String subtaskId) =>
      _writeOperation(() async {
        task = await _currentTask(task);
        final now = _clock();
        final updated = task.removeSubtask(subtaskId);
        await _writeTask(updated);
        await _updateSeriesTemplate(updated);
        await _syncDaily(await _readTasks(tasksDirectory), now);
        return updated;
      });

  Future<void> deleteTask(GoodDayTask task) => _writeOperation(() async {
    task = await _currentTask(task);
    final now = _clock();
    final deleted = task.markDeleted(now);
    final archiveFile = _taskFile(archiveDirectory, task.id);
    await SafeFile.write(archiveFile, deleted.toMarkdown());

    final activeFile = _taskFile(tasksDirectory, task.id);
    if (await activeFile.exists()) {
      await activeFile.delete();
    }
    await _syncDaily(await _readTasks(tasksDirectory), now);
  });

  Future<List<TrashItem>> loadTrash() async {
    await initialize();
    final items = <TrashItem>[];
    await for (final entity in archiveDirectory.list()) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.md')) {
        continue;
      }
      try {
        final task = await _readTaskFile(entity);
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
        _unreadableFiles.add(entity.path);
      } on FileSystemException {
        _unreadableFiles.add(entity.path);
      }
    }
    await _appendArchivedPlans(items);
    await _appendArchivedGoals(items);
    for (final reminder in await _readReminderItems()) {
      if (reminder.deletedAt != null) {
        items.add(
          TrashItem(
            type: TrashItemType.reminder,
            id: reminder.id,
            title: reminder.title,
            deletedAt: reminder.deletedAt!,
          ),
        );
      }
    }
    await for (final file in archivedEventsDirectory.list(followLinks: false)) {
      if (file is! File || !file.path.toLowerCase().endsWith('.md')) continue;
      try {
        final event = GoodDayEvent.fromMarkdown(await file.readAsString());
        items.add(
          TrashItem(
            type: TrashItemType.event,
            id: event.id,
            title: event.title,
            deletedAt: event.deletedAt ?? (await file.stat()).changed,
          ),
        );
      } on FormatException {
        _unreadableFiles.add(file.path);
      } on FileSystemException {
        _unreadableFiles.add(file.path);
      }
    }
    items.sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
    return items;
  }

  Future<void> restoreTrashItem(TrashItem item) => _writeOperation(() async {
    await initialize();
    switch (item.type) {
      case TrashItemType.task:
        final source = _taskFile(archiveDirectory, item.id);
        final restored = (await _readTaskFile(source)).restore();
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
      case TrashItemType.event:
        final source = _eventFile(item.id, archived: true);
        final restored = GoodDayEvent.fromMarkdown(await source.readAsString())
            .restore();
        await SafeFile.write(_eventFile(item.id), restored.toMarkdown());
        await source.delete();
        return;
      case TrashItemType.reminder:
        final reminder = await _readReminderItem(item.id);
        await _writeReminderItem(
          reminder.patch({
            'deletedAt': null,
            'enabled': false,
            'pendingPhase': null,
            'snoozedUntil': null,
          }),
        );
        return;
    }
  });

  Future<void> emptyTrash() => _writeOperation(() async {
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
    await _deleteContents(archivedEventsDirectory);
    for (final reminder in await _readReminderItems()) {
      if (reminder.deletedAt != null) {
        await _taskFile(remindersDirectory, reminder.id).delete();
      }
    }
    _reminderChanges.add(null);
    await _syncDaily(await _readTasks(tasksDirectory), _clock());
  });

  Future<void> _appendArchivedPlans(List<TrashItem> items) async {
    await for (final entity in archivedPlansDirectory.list()) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.md')) {
        continue;
      }
      try {
        final plan = GoodDayPlan.fromMarkdown(await entity.readAsString());
        _validateRecordFile(entity, plan.id);
        items.add(
          TrashItem(
            type: TrashItemType.plan,
            id: plan.id,
            title: plan.title,
            deletedAt: (await entity.stat()).changed,
          ),
        );
      } on FormatException {
        _unreadableFiles.add(entity.path);
      } on FileSystemException {
        _unreadableFiles.add(entity.path);
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
        _validateRecordFile(entity, goal.id);
        items.add(
          TrashItem(
            type: TrashItemType.goal,
            id: goal.id,
            title: goal.name,
            deletedAt: (await entity.stat()).changed,
          ),
        );
      } on FormatException {
        _unreadableFiles.add(entity.path);
      } on FileSystemException {
        _unreadableFiles.add(entity.path);
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
        tasks.add(await _readTaskFile(entity));
        _unreadableFiles.remove(entity.path);
      } on FormatException {
        _unreadableFiles.add(entity.path);
      } on FileSystemException {
        _unreadableFiles.add(entity.path);
      }
    }
    _sort(tasks);
    return tasks;
  }

  Future<void> _writeTask(GoodDayTask task) async {
    await tasksDirectory.create(recursive: true);
    await SafeFile.write(_taskFile(tasksDirectory, task.id), task.toMarkdown());
  }

  Future<void> _updateSeriesTemplate(GoodDayTask task) async {
    if (task.seriesId == null || task.isCompleted) return;
    final file = _seriesFile(task.seriesId!);
    if (!await file.exists()) return;
    final series = TaskSeries.fromMarkdown(await file.readAsString());
    if (!series.enabled) return;
    await SafeFile.write(
      file,
      TaskSeries(
        id: series.id,
        enabled: true,
        generatedThrough: series.generatedThrough,
        template: series.template.copyWith(
          title: task.title,
          notes: task.notes,
          goalId: task.goalId,
          clearGoal: task.goalId == null,
          subtasks: task.subtasks,
          reminder: _reminderForDate(
            task,
            series.template.scheduledDate,
            series.template.id,
          ),
          clearReminder: task.reminder == null,
        ),
      ).toMarkdown(),
    );
  }

  Future<void> _writeGoal(GoodDayGoal goal) async {
    await goalsDirectory.create(recursive: true);
    await SafeFile.write(_taskFile(goalsDirectory, goal.id), goal.toMarkdown());
  }

  Future<void> _writePlan(GoodDayPlan plan) async {
    await plansDirectory.create(recursive: true);
    await SafeFile.write(_taskFile(plansDirectory, plan.id), plan.toMarkdown());
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
    if (existing != next) await SafeFile.write(dailyFile, next);
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

  static File _taskFile(Directory parent, String id) {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id)) {
      throw const FormatException('记录标识无效');
    }
    return _childFile(parent, '$id.md');
  }

  static void _validateRecordFile(File file, String id) {
    if (file.absolute.path.toLowerCase() !=
        _taskFile(file.parent, id).absolute.path.toLowerCase()) {
      throw const FormatException('记录编号与文件名不一致，原文件已保留');
    }
  }

  static Future<void> _copyDirectory(
    Directory source,
    Directory destination,
  ) async {
    if (!await source.exists()) return;
    await destination.create(recursive: true);
    await for (final entity in source.list(followLinks: false)) {
      final name = entity.uri.pathSegments
          .where((segment) => segment.isNotEmpty)
          .last;
      if (entity is Directory) {
        await _copyDirectory(entity, _childDirectory(destination, name));
      } else if (entity is File) {
        if (name == 'session.lock' || name.endsWith('.tmp')) continue;
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
    await SafeFile.write(destination, await source.readAsString());
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
