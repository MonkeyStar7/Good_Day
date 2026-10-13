part of 'vault_repository.dart';

extension ReminderRepository on VaultRepository {
  File get _reminderJournal =>
      VaultRepository._childFile(remindersDirectory, '.series-operation.json');

  Future<Map<String, File>> _managedReminderFiles() async {
    final result = <String, File>{};
    if (!await remindersDirectory.exists()) return result;
    await for (final entity in remindersDirectory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      final relative = entity.path
          .substring(remindersDirectory.path.length + 1)
          .replaceAll('\\', '/');
      if (RegExp(r'^(Series/)?[a-zA-Z0-9_-]+\.md$').hasMatch(relative)) {
        result[relative] = entity;
      }
    }
    return result;
  }

  Future<void> _recoverReminderTransaction() async {
    if (!await _reminderJournal.exists()) return;
    final originals = (jsonDecode(
      await _reminderJournal.readAsString(),
    ) as Map<String, dynamic>).cast<String, String>();
    if (originals.keys.any(
      (key) => !RegExp(r'^(Series/)?[a-zA-Z0-9_-]+\.md$').hasMatch(key),
    )) {
      throw const FormatException('待办恢复记录无效，请保留数据并恢复备份');
    }
    for (final entry in (await _managedReminderFiles()).entries) {
      if (!originals.containsKey(entry.key)) await entry.value.delete();
    }
    for (final entry in originals.entries) {
      final file = File(
        '${remindersDirectory.path}${Platform.pathSeparator}${entry.key.replaceAll('/', Platform.pathSeparator)}',
      );
      if (!await file.exists() ||
          base64Encode(await file.readAsBytes()) != entry.value) {
        await SafeFile.writeBytes(file, base64Decode(entry.value));
      }
    }
    await _reminderJournal.delete();
    _reminderChanges.add(null);
  }

  Future<T> _reminderTransaction<T>(Future<T> Function() action) async {
    final snapshot = <String, String>{};
    for (final entry in (await _managedReminderFiles()).entries) {
      snapshot[entry.key] = base64Encode(await entry.value.readAsBytes());
    }
    await SafeFile.write(_reminderJournal, jsonEncode(snapshot));
    try {
      final result = await action();
      await _reminderJournal.delete();
      return result;
    } catch (_) {
      await _recoverReminderTransaction();
      rethrow;
    }
  }

  Directory get _reminderSeries =>
      VaultRepository._childDirectory(remindersDirectory, 'Series');

  File _seriesFile(String id) => VaultRepository._taskFile(_reminderSeries, id);

  String _occurrenceId(String root, DateTime date) =>
      '${root}_${dateKey(date).replaceAll('-', '')}_${date.hour.toString().padLeft(2, '0')}${date.minute.toString().padLeft(2, '0')}';

  ReminderItem _occurrence(ReminderItem template, DateTime date) =>
      ReminderItem(
        id: date == template.dueAt
            ? template.id
            : _occurrenceId(template.seriesRoot ?? template.id, date),
        title: template.title,
        notes: template.notes,
        dueAt: date,
        createdAt: _clock(),
        subtasks: [
          for (final task in template.subtasks)
            task.copyWith(isCompleted: false),
        ],
        rule: template.rule,
        early: template.early,
        enabled: template.enabled,
        seriesRoot: template.seriesRoot ?? template.id,
        anchor: template.anchor ?? template.dueAt,
        calendarRepeat: true,
        // Do not announce every missed day after an offline gap.
        dueHandled: !isSameDay(date, _clock()) && date.isBefore(_clock()),
        earlyHandled: template.early?.before(date).isBefore(_clock()) ?? false,
      );

  Future<ReminderItem> _currentReminder(ReminderItem item) async {
    final file = VaultRepository._taskFile(remindersDirectory, item.id);
    if (await file.exists()) return _readReminderItem(item.id);
    if (!item.projected || item.seriesRoot == null) {
      throw const FileSystemException('事项不存在，请刷新');
    }
    final template = ReminderItem.fromMarkdown(
      await _seriesFile(item.seriesRoot!).readAsString(),
    );
    final date = template.rule.nextAfter(
      template.anchor ?? template.dueAt,
      item.dueAt.subtract(const Duration(microseconds: 1)),
    );
    if (template.deletedAt != null ||
        template.rule.unit == RepeatUnit.none ||
        date != item.dueAt) {
      throw const FileSystemException('重复设置已更改，请刷新');
    }
    final fresh = _occurrence(template, item.dueAt);
    await _writeReminderItem(fresh);
    return fresh;
  }

  Future<void> _stopCalendarSeries(ReminderItem item) async {
    final file = _seriesFile(item.seriesRoot ?? item.id);
    if (await file.exists()) {
      final template = ReminderItem.fromMarkdown(await file.readAsString());
      await SafeFile.write(
        file,
        template.patch({'deletedAt': _clock().toIso8601String()}).toMarkdown(),
      );
    }
    // Future materialized edits belong to the stopped series too. Past records remain intact.
    for (final future in await _readReminderItems()) {
      if (future.id != item.id &&
          future.seriesRoot == (item.seriesRoot ?? item.id) &&
          future.dueAt.isAfter(item.dueAt) &&
          !future.isCompleted &&
          future.deletedAt == null) {
        await _writeReminderItem(
          future.patch({'deletedAt': _clock().toIso8601String()}),
        );
      }
    }
  }

  Future<void> _saveCalendarTemplate(
    ReminderItem item,
    ReminderItem previous,
  ) async {
    final scheduleChanged =
        previous.anchor != item.anchor ||
        previous.rule.toJson().toString() != item.rule.toJson().toString();
    if (previous.calendarRepeat &&
        (previous.seriesRoot != item.seriesRoot ||
            scheduleChanged ||
            item.rule.unit == RepeatUnit.none)) {
      await _stopCalendarSeries(previous);
    }
    final root = item.seriesRoot ?? item.id;
    final file = _seriesFile(root);
    final old = await file.exists()
        ? ReminderItem.fromMarkdown(await file.readAsString())
        : null;
    final template = item.patch({
      'id': root,
      'seriesRoot': root,
      'dueAt': (item.anchor ?? item.dueAt).toIso8601String(),
      'completedAt': null,
      'deletedAt': item.rule.unit == RepeatUnit.none
          ? _clock().toIso8601String()
          : null,
      'calendarThrough': scheduleChanged
          ? null
          : old?.calendarThrough?.toIso8601String(),
      'pendingPhase': null,
      'snoozedUntil': null,
      'nextRepeatAt': null,
    });
    await _reminderSeries.create(recursive: true);
    await SafeFile.write(file, template.toMarkdown());
  }

  /// Upgrade old day/week/month rules without changing completion records.
  Future<void> migrateReminderRecurrence() => _writeOperation(() async {
    final records = await _readReminderItems();
    final roots = <String, ReminderItem>{};
    for (final item in records) {
      if (item.deletedAt != null ||
          item.calendarRepeat ||
          item.rule.unit.index < RepeatUnit.day.index) {
        continue;
      }
      final root = item.seriesRoot ?? item.id;
      if (roots[root] == null || roots[root]!.dueAt.isBefore(item.dueAt)) {
        roots[root] = item;
      }
    }
    for (final entry in roots.entries) {
      final source = entry.value;
      final migrated = source.patch({'calendarRepeat': true});
      if (!await _seriesFile(entry.key).exists()) {
        await _saveCalendarTemplate(migrated, migrated);
      }
      for (final item in records.where(
        (item) => (item.seriesRoot ?? item.id) == entry.key,
      )) {
        await _writeReminderItem(item.patch({'calendarRepeat': true}));
      }
    }
  });

  Future<List<ReminderItem>> _calendarOccurrences(
    List<ReminderItem> records,
    DateTime? through,
  ) async {
    if (!await _reminderSeries.exists()) return [];
    final generated = <ReminderItem>[];
    final now = _clock();
    final endToday = DateTime(now.year, now.month, now.day + 1);
    final horizon = through == null
        ? endToday
        : DateTime(through.year, through.month, through.day + 1);
    final existing = {
      for (final item in records)
        '${item.seriesRoot ?? item.id}:${item.dueAt.toIso8601String()}',
    };
    await for (final file in _reminderSeries.list(followLinks: false)) {
      if (file is! File || !file.path.endsWith('.md')) continue;
      ReminderItem template;
      try {
        template = ReminderItem.fromMarkdown(await file.readAsString());
        VaultRepository._validateRecordFile(file, template.id);
        _unreadableFiles.remove(file.path);
      } on FormatException {
        _unreadableFiles.add(file.path);
        continue;
      } on FileSystemException {
        _unreadableFiles.add(file.path);
        continue;
      }
      if (template.deletedAt != null || template.rule.unit == RepeatUnit.none) {
        continue;
      }
      final anchor = template.anchor ?? template.dueAt;
      var cursor =
          template.calendarThrough ??
          anchor.subtract(const Duration(microseconds: 1));
      // Persist actual dates only. Future plan entries are projections, so years of plans
      // do not create thousands of files or inflate backups.
      var next = template.rule.nextAfter(anchor, cursor);
      var count = 0;
      while (next != null && next.isBefore(endToday) && count++ < 4000) {
        final key = '${template.id}:${next.toIso8601String()}';
        if (!existing.contains(key)) {
          await backups.ensureDaily();
          final item = _occurrence(template, next);
          await _writeReminderItem(item);
          generated.add(item);
          existing.add(key);
        }
        cursor = next;
        next = template.rule.nextAfter(anchor, cursor);
      }
      if (template.calendarThrough != cursor) {
        await backups.ensureDaily();
        await SafeFile.write(
          file,
          template.patch({
            'calendarThrough': cursor.toIso8601String(),
          }).toMarkdown(),
        );
      }
      cursor = endToday.subtract(const Duration(microseconds: 1));
      next = template.rule.nextAfter(anchor, cursor);
      count = 0;
      while (next != null && next.isBefore(horizon) && count++ < 4000) {
        if (!existing.contains('${template.id}:${next.toIso8601String()}')) {
          final item = _occurrence(template, next);
          generated.add(ReminderItem.fromJson(item.toJson()).asProjection());
        }
        next = template.rule.nextAfter(anchor, next);
      }
    }
    return generated;
  }

  Future<List<ReminderItem>> loadReminders({
    bool includeDeleted = false,
    DateTime? through,
  }) => _operations.run(() async {
    final items = await _readReminderItems();
    items.addAll(await _calendarOccurrences(items, through));
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
    bool? calendarRepeat,
    int? repeatReminderMinutes,
  }) => _writeOperation(
    () => _reminderTransaction(() async {
      final current = item == null ? null : await _currentReminder(item);
      var name = title.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
      if (name.isEmpty) {
        if (current != null &&
            RegExp(r'^未命名[1-9][0-9]*$').hasMatch(current.title)) {
          name = current.title;
        } else {
          var highest = 0;
          for (final record in await _readReminderItems()) {
            final match = RegExp(r'^未命名([1-9][0-9]*)$')
                .firstMatch(record.title);
            final number = match == null
                ? 0
                : int.tryParse(match.group(1)!) ?? 0;
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
          base.repeatReminderMinutes != repeatReminderMinutes ||
          base.early?.toJson().toString() != early?.toJson().toString() ||
          base.enabled != enabled;
      final result = base.patch({
        'title': name,
        'notes': notes.trim(),
        if (subtasks != null)
          'subtasks': [
            for (final task in subtasks)
              {
                'id': task.id,
                'title': task.title,
                'completed': task.isCompleted,
              },
          ],
        'dueAt': dueAt.toIso8601String(),
        'rule': rule.toJson(),
        'early': early?.toJson(),
        'enabled': enabled,
        'goalId': goalId,
        'calendarRepeat': calendarRepeat ?? base.calendarRepeat,
        'repeatReminderMinutes': repeatReminderMinutes,
        if (changed || current == null) ...{
          'earlyHandled': early != null && early.before(dueAt).isBefore(now),
          // Choosing a time in the past records an overdue todo; it must not
          // trigger an immediate alarm merely because it was just configured.
          'dueHandled': dueAt.isBefore(now),
          'pendingPhase': null,
          'snoozedUntil': null,
          'nextRepeatAt': null,
        },
        if (scheduleChanged || current == null) ...{
          'anchor': dueAt.toIso8601String(),
          'seriesRoot': base.id,
        },
      });
      await _writeReminderItem(result);
      if (result.calendarRepeat || base.calendarRepeat) {
        await _saveCalendarTemplate(result, base);
      }
      return result;
    }),
  );

  Future<void> completeReminder(
    ReminderItem item,
    bool completed,
  ) => _writeOperation(() async {
    final current = await _currentReminder(item);
    if (current.deletedAt != null || current.isCompleted == completed) return;
    File? generated;
    try {
      if (completed && !current.calendarRepeat) {
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
          'subtasks': [
            for (final task in current.subtasks)
              {
                'id': task.id,
                'title': task.title,
                'completed': completed || task.isCompleted,
              },
          ],
          'pendingPhase': null,
          'snoozedUntil': null,
          'nextRepeatAt': null,
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
    final current = await _currentReminder(item);
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

  Future<void> deleteReminder(ReminderItem item) => _writeOperation(
    () => _reminderTransaction(() async {
      final current = await _currentReminder(item);
      await _writeReminderItem(
        current.patch({
          'deletedAt': _clock().toIso8601String(),
          'pendingPhase': null,
          'snoozedUntil': null,
        }),
      );
      if (current.calendarRepeat) {
        await _stopCalendarSeries(current);
      }
    }),
  );

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
                'nextRepeatAt': null,
              }
            : {'snoozedUntil': snoozeUntil.toIso8601String()},
      ),
    );
  });
}
