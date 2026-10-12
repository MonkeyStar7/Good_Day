part of 'vault_repository.dart';

extension ReminderRepository on VaultRepository {
  Future<List<ReminderItem>> loadReminders({bool includeDeleted = false}) =>
      _operations.run(() async {
        final items = await _readReminderItems();
        return items
            .where((item) => includeDeleted || item.deletedAt == null)
            .toList()
          ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
      });

  Future<List<ReminderItem>> _readReminderItems() async {
    if (!await remindersDirectory.exists()) return [];
    final items = <ReminderItem>[];
    await for (final file in remindersDirectory.list(followLinks: false)) {
      if (file is! File || !file.path.toLowerCase().endsWith('.md')) continue;
      try {
        final item = ReminderItem.fromMarkdown(await file.readAsString());
        VaultRepository._validateRecordFile(file, item.id);
        items.add(item);
        _unreadableFiles.remove(file.path);
      } on FormatException {
        _unreadableFiles.add(file.path);
      } on FileSystemException {
        _unreadableFiles.add(file.path);
      }
    }
    return items;
  }

  Future<ReminderItem> _readReminderItem(String id) async {
    final file = VaultRepository._taskFile(remindersDirectory, id);
    final item = ReminderItem.fromMarkdown(await file.readAsString());
    VaultRepository._validateRecordFile(file, item.id);
    return item;
  }

  Future<void> _writeReminderItem(ReminderItem item) async {
    await SafeFile.write(
      VaultRepository._taskFile(remindersDirectory, item.id),
      item.toMarkdown(),
    );
    _reminderChanges.add(null);
  }

  Future<ReminderItem> saveReminder({
    ReminderItem? item,
    required String title,
    required DateTime dueAt,
    required String notes,
    required ReminderRule rule,
    EarlyReminder? early,
    String? goalId,
    bool enabled = true,
    List<GoodDaySubtask>? subtasks,
  }) => _writeOperation(() async {
    final current = item == null ? null : await _readReminderItem(item.id);
    var name = title.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    if (name.isEmpty) {
      if (current != null &&
          RegExp(r'^未命名[1-9][0-9]*$').hasMatch(current.title)) {
        name = current.title;
      } else {
        var highest = 0;
        for (final record in await _readReminderItems()) {
          final match = RegExp(r'^未命名([1-9][0-9]*)$').firstMatch(record.title);
          final number = match == null ? 0 : int.tryParse(match.group(1)!) ?? 0;
          if (number > highest) highest = number;
        }
        name = '未命名${highest + 1}';
      }
    }
    final now = _clock();
    final base =
        current ??
        ReminderItem(
          id: VaultRepository._newId('rem', now),
          title: name,
          dueAt: dueAt,
          createdAt: now,
        );
    final scheduleChanged =
        base.dueAt != dueAt ||
        base.rule.toJson().toString() != rule.toJson().toString();
    final changed =
        scheduleChanged ||
        base.early?.toJson().toString() != early?.toJson().toString() ||
        base.enabled != enabled;
    final result = base.patch({
      'title': name,
      'notes': notes.trim(),
      if (subtasks != null)
        'subtasks': [
          for (final task in subtasks)
            {'id': task.id, 'title': task.title, 'completed': task.isCompleted},
        ],
      'dueAt': dueAt.toIso8601String(),
      'rule': rule.toJson(),
      'early': early?.toJson(),
      'enabled': enabled,
      'goalId': goalId,
      if (changed || current == null) ...{
        'earlyHandled': early != null && early.before(dueAt).isBefore(now),
        // Choosing a time in the past records an overdue todo; it must not
        // trigger an immediate alarm merely because it was just configured.
        'dueHandled': dueAt.isBefore(now),
        'pendingPhase': null,
        'snoozedUntil': null,
      },
      if (scheduleChanged || current == null) ...{
        'anchor': dueAt.toIso8601String(),
        'seriesRoot': base.id,
      },
    });
    await _writeReminderItem(result);
    return result;
  });

  Future<void> completeReminder(
    ReminderItem item,
    bool completed,
  ) => _writeOperation(() async {
    final current = await _readReminderItem(item.id);
    if (current.deletedAt != null || current.isCompleted == completed) return;
    File? generated;
    try {
      if (completed) {
        final next = current.rule.nextAfter(
          current.anchor ?? current.dueAt,
          _clock().isAfter(current.dueAt) ? _clock() : current.dueAt,
        );
        if (next != null) {
          final root = current.seriesRoot ?? current.id;
          final suffix =
              '${dateKey(next).replaceAll('-', '')}_${next.hour.toString().padLeft(2, '0')}${next.minute.toString().padLeft(2, '0')}';
          final id = '${root}_$suffix';
          final file = VaultRepository._taskFile(remindersDirectory, id);
          if (!await file.exists()) {
            await _writeReminderItem(
              ReminderItem(
                id: id,
                title: current.title,
                notes: current.notes,
                subtasks: [
                  for (final task in current.subtasks)
                    task.copyWith(isCompleted: false),
                ],
                dueAt: next,
                createdAt: _clock(),
                goalId: current.goalId,
                rule: current.rule,
                early: current.early,
                earlyHandled:
                    current.early?.before(next).isBefore(_clock()) ?? false,
                enabled: current.enabled,
                seriesRoot: root,
                anchor: current.anchor ?? current.dueAt,
              ),
            );
            generated = file;
          }
        }
      }
      await _writeReminderItem(
        current.patch({
          'completedAt': completed ? _clock().toIso8601String() : null,
          'pendingPhase': null,
          'snoozedUntil': null,
        }),
      );
    } catch (_) {
      if (generated != null && await generated.exists()) {
        await generated.delete();
        _reminderChanges.add(null);
      }
      rethrow;
    }
  });

  Future<void> setReminderSubtaskCompleted(
    ReminderItem item,
    String subtaskId,
    bool completed,
  ) => _writeOperation(() async {
    final current = await _readReminderItem(item.id);
    if (current.deletedAt != null || current.isCompleted) return;
    await _writeReminderItem(
      current.patch({
        'subtasks': [
          for (final task in current.subtasks)
            {
              'id': task.id,
              'title': task.title,
              'completed': task.id == subtaskId ? completed : task.isCompleted,
            },
        ],
      }),
    );
  });

  Future<void> deleteReminder(ReminderItem item) => _writeOperation(() async {
    final current = await _readReminderItem(item.id);
    await _writeReminderItem(
      current.patch({
        'deletedAt': _clock().toIso8601String(),
        'pendingPhase': null,
        'snoozedUntil': null,
      }),
    );
  });

  Future<ReminderItem?> prepareReminder(String id, DateTime now) =>
      _writeOperation(() async {
        final current = await _readReminderItem(id);
        final phase = current.phaseDue(now);
        if (phase == null) return null;
        final result = current.patch({
          'pendingPhase': phase,
          if (phase != current.pendingPhase) 'snoozedUntil': null,
        });
        await _writeReminderItem(result);
        return result;
      });
  Future<void> resolveReminder(
    String id,
    String phase, {
    DateTime? snoozeUntil,
  }) => _writeOperation(() async {
    final current = await _readReminderItem(id);
    if (current.pendingPhase != phase ||
        current.isCompleted ||
        current.deletedAt != null ||
        !current.enabled) {
      return; // A stale notification can close without altering newer state.
    }
    if (snoozeUntil != null && !snoozeUntil.isAfter(_clock())) {
      throw const FormatException('稍后提醒时间必须在未来');
    }
    await _writeReminderItem(
      current.patch(
        snoozeUntil == null
            ? {
                if (phase == 'early')
                  'earlyHandled': true
                else
                  'dueHandled': true,
                'pendingPhase': null,
                'snoozedUntil': null,
              }
            : {'snoozedUntil': snoozeUntil.toIso8601String()},
      ),
    );
  });
}
