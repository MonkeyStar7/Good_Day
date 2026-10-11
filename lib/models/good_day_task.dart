import 'dart:convert';

import 'good_day_event.dart';
import 'task_period.dart';
export 'task_period.dart';

class GoodDaySubtask {
  const GoodDaySubtask({
    required this.id,
    required this.title,
    this.isCompleted = false,
  });

  final String id;
  final String title;
  final bool isCompleted;

  GoodDaySubtask copyWith({String? title, bool? isCompleted}) {
    return GoodDaySubtask(
      id: id,
      title: title ?? this.title,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }
}

class GoodDayTask {
  const GoodDayTask({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.scheduledDate,
    this.isCompleted = false,
    this.completedAt,
    this.deletedAt,
    this.notes = '',
    this.subtasks = const [],
    this.goalId,
    this.repeat = EventRepeat.once,
    this.seriesId,
    this.repeatAnchor,
    this.occurrenceDate,
    this.originalDate,
    this.reminder,
    this.period = TaskPeriod.day,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime scheduledDate;
  final bool isCompleted;
  final DateTime? completedAt;
  final DateTime? deletedAt;
  final String notes;
  final List<GoodDaySubtask> subtasks;
  final String? goalId;
  final EventRepeat repeat;
  final String? seriesId;
  final DateTime? repeatAnchor, occurrenceDate, originalDate;
  final GoodDayEvent? reminder;
  final TaskPeriod period;

  bool isWaitingForSchedule(DateTime now) =>
      deletedAt == null &&
      !isCompleted &&
      !period.end(scheduledDate).isAfter(now);

  bool appearsIn(TaskPeriod view, DateTime now) {
    if (deletedAt != null) return false;
    if (view == TaskPeriod.backlog) return isWaitingForSchedule(now);
    if (isCompleted) {
      return period.index <= view.index &&
          view.contains(completedAt ?? scheduledDate, now);
    }
    return period == view && view.contains(scheduledDate, now);
  }

  GoodDayEvent? get activeReminder => isCompleted || deletedAt != null
      ? null
      : reminder?.edit(
          title: title,
          notes: notes,
          startsAt: reminder!.startsAt,
          repeat: EventRepeat.once,
          reminderMinutes: 0,
          enabled: reminder!.enabled,
        );
  DateTime get originalScheduledDate => originalDate ?? scheduledDate;

  GoodDayTask copyWith({
    String? title,
    String? notes,
    DateTime? scheduledDate,
    bool? isCompleted,
    DateTime? completedAt,
    DateTime? deletedAt,
    bool clearCompletedAt = false,
    bool clearDeletedAt = false,
    String? goalId,
    bool clearGoal = false,
    List<GoodDaySubtask>? subtasks,
    EventRepeat? repeat,
    String? seriesId,
    DateTime? repeatAnchor,
    DateTime? occurrenceDate,
    DateTime? originalDate,
    bool clearSeries = false,
    GoodDayEvent? reminder,
    bool clearReminder = false,
    TaskPeriod? period,
  }) => GoodDayTask(
    id: id,
    title: title ?? this.title,
    notes: notes ?? this.notes,
    createdAt: createdAt,
    scheduledDate: scheduledDate ?? this.scheduledDate,
    isCompleted: isCompleted ?? this.isCompleted,
    completedAt: clearCompletedAt ? null : completedAt ?? this.completedAt,
    deletedAt: clearDeletedAt ? null : deletedAt ?? this.deletedAt,
    goalId: clearGoal ? null : goalId ?? this.goalId,
    subtasks: List.unmodifiable(subtasks ?? this.subtasks),
    repeat: repeat ?? this.repeat,
    seriesId: clearSeries ? null : seriesId ?? this.seriesId,
    repeatAnchor: clearSeries ? null : repeatAnchor ?? this.repeatAnchor,
    occurrenceDate: clearSeries ? null : occurrenceDate ?? this.occurrenceDate,
    originalDate: originalDate ?? originalScheduledDate,
    reminder: clearReminder ? null : reminder ?? this.reminder,
    period: period ?? this.period,
  );

  GoodDayTask setCompleted(bool completed, DateTime now) => copyWith(
    isCompleted: completed,
    completedAt: completed ? now : null,
    clearCompletedAt: !completed,
  );
  GoodDayTask rollForward(DateTime date) => copyWith(scheduledDate: date);
  GoodDayTask markDeleted(DateTime now) => copyWith(deletedAt: now);
  GoodDayTask restore() => copyWith(
    clearDeletedAt: true,
    reminder: reminder?.edit(
      title: title,
      notes: notes,
      startsAt: reminder!.startsAt,
      repeat: EventRepeat.once,
      reminderMinutes: 0,
      enabled: false,
    ),
  );
  GoodDayTask updateDetails({required String title, required String notes}) =>
      copyWith(title: title.trim(), notes: _singleLine(notes));
  GoodDayTask assignGoal(String? nextGoalId) =>
      copyWith(goalId: nextGoalId, clearGoal: nextGoalId == null);
  GoodDayTask addSubtask(GoodDaySubtask subtask) =>
      copyWith(subtasks: [...subtasks, subtask]);
  GoodDayTask updateSubtask(
    String subtaskId, {
    String? title,
    bool? isCompleted,
  }) => copyWith(
    subtasks: [
      for (final subtask in subtasks)
        if (subtask.id == subtaskId)
          subtask.copyWith(
            title: title == null ? null : _singleLine(title).trim(),
            isCompleted: isCompleted,
          )
        else
          subtask,
    ],
  );
  GoodDayTask removeSubtask(String subtaskId) => copyWith(
    subtasks: subtasks.where((subtask) => subtask.id != subtaskId).toList(),
  );

  String toMarkdown() {
    final safeTitle = title.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    final buffer = StringBuffer()
      ..writeln('---')
      ..writeln('id: $id')
      ..writeln(
        'status: ${deletedAt != null
            ? 'deleted'
            : isCompleted
            ? 'done'
            : 'todo'}',
      )
      ..writeln('created: ${createdAt.toIso8601String()}')
      ..writeln('scheduled: ${dateKey(scheduledDate)}')
      ..writeln('period: ${period.name}')
      ..writeln('original_scheduled: ${dateKey(originalScheduledDate)}')
      ..writeln('recurrence: ${repeat.name}')
      ..writeln('series: ${seriesId ?? ''}')
      ..writeln(
        'repeat_anchor: ${repeatAnchor == null ? '' : dateKey(repeatAnchor!)}',
      )
      ..writeln(
        'occurrence: ${occurrenceDate == null ? '' : dateKey(occurrenceDate!)}',
      )
      ..writeln('completed: ${completedAt?.toIso8601String() ?? ''}')
      ..writeln('deleted: ${deletedAt?.toIso8601String() ?? ''}')
      ..writeln('goal: ${goalId ?? ''}')
      ..writeln(
        'reminder: ${reminder == null ? '' : jsonEncode(reminder!.toMarkdown())}',
      )
      ..writeln('---')
      ..writeln()
      ..writeln('# $safeTitle');
    if (notes.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('> ${_singleLine(notes)}');
    }
    if (subtasks.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## 子任务')
        ..writeln();
      for (final subtask in subtasks) {
        final checked = subtask.isCompleted ? 'x' : ' ';
        final title = _singleLine(subtask.title).trim();
        buffer.writeln(
          '- [$checked] $title <!-- goodday-subtask:${subtask.id} -->',
        );
      }
    }
    return buffer.toString();
  }

  factory GoodDayTask.fromMarkdown(String source) {
    final lines = source.split(RegExp(r'\r?\n'));
    if (lines.isEmpty || lines.first.trim() != '---') {
      throw const FormatException('Missing Markdown front matter.');
    }

    final values = <String, String>{};
    var index = 1;
    for (; index < lines.length; index++) {
      final line = lines[index];
      if (line.trim() == '---') {
        index++;
        break;
      }
      final separator = line.indexOf(':');
      if (separator > 0) {
        values[line.substring(0, separator).trim()] = line
            .substring(separator + 1)
            .trim();
      }
    }

    var titleIndex = -1;
    for (var i = index; i < lines.length; i++) {
      if (lines[i].startsWith('# ')) {
        titleIndex = i;
        break;
      }
    }
    if (titleIndex == -1) {
      throw const FormatException('Missing task title.');
    }

    final id = values['id'];
    final created = DateTime.tryParse(values['created'] ?? '');
    final scheduled = DateTime.tryParse(values['scheduled'] ?? '');
    if (id == null || id.isEmpty || created == null || scheduled == null) {
      throw const FormatException('Invalid task metadata.');
    }

    var subtasksIndex = -1;
    for (var i = titleIndex + 1; i < lines.length; i++) {
      if (lines[i].trim() == '## 子任务') {
        subtasksIndex = i;
        break;
      }
    }

    final bodyEnd = subtasksIndex == -1 ? lines.length : subtasksIndex;
    final noteLines = lines.sublist(titleIndex + 1, bodyEnd)
      ..removeWhere((line) => line.trim().isEmpty);
    final notes = noteLines.isEmpty
        ? ''
        : noteLines
              .map((line) => line.startsWith('> ') ? line.substring(2) : line)
              .join(' ')
              .trim();

    final subtasks = <GoodDaySubtask>[];
    if (subtasksIndex >= 0) {
      final pattern = RegExp(
        r'^- \[([ xX])\] (.*?) <!-- goodday-subtask:([^>]+) -->$',
      );
      for (var i = subtasksIndex + 1; i < lines.length; i++) {
        final match = pattern.firstMatch(lines[i].trim());
        if (match == null) continue;
        subtasks.add(
          GoodDaySubtask(
            id: match.group(3)!.trim(),
            title: match.group(2)!.trim(),
            isCompleted: match.group(1)!.toLowerCase() == 'x',
          ),
        );
      }
    }

    final goal = values['goal']?.trim();
    final originalScheduled =
        DateTime.tryParse(values['original_scheduled'] ?? '') ?? scheduled;
    // Older versions moved unfinished daily tasks forward automatically.
    // Recover their original assignment once when introducing period views.
    final legacyRollover =
        !values.containsKey('period') &&
        values['status'] == 'todo' &&
        (values['series'] ?? '').isEmpty &&
        originalScheduled.isBefore(scheduled);
    final periodName = values['period'] ?? 'day';
    if (!TaskPeriod.values.any(
      (period) => period != TaskPeriod.backlog && period.name == periodName,
    )) {
      throw const FormatException('Invalid task period.');
    }
    GoodDayEvent? reminder;
    if ((values['reminder'] ?? '').isNotEmpty) {
      final encoded = jsonDecode(values['reminder']!);
      if (encoded is! String) {
        throw const FormatException('Invalid task reminder.');
      }
      reminder = GoodDayEvent.fromMarkdown(encoded);
      if (reminder.repeat != EventRepeat.once || reminder.id != 'task_$id') {
        throw const FormatException('Invalid task reminder identity.');
      }
    }
    if (values['recurrence'] != null &&
        !EventRepeat.values.any(
          (repeat) => repeat.name == values['recurrence'],
        )) {
      throw const FormatException('Invalid task recurrence.');
    }
    return GoodDayTask(
      id: id,
      title: lines[titleIndex].substring(2).trim(),
      createdAt: created,
      scheduledDate: legacyRollover ? originalScheduled : scheduled,
      period: TaskPeriod.values.byName(periodName),
      isCompleted: values['status'] == 'done',
      completedAt: DateTime.tryParse(values['completed'] ?? ''),
      deletedAt: DateTime.tryParse(values['deleted'] ?? ''),
      notes: notes,
      subtasks: List.unmodifiable(subtasks),
      goalId: goal == null || goal.isEmpty ? null : goal,
      repeat: values['recurrence'] == null
          ? EventRepeat.once
          : EventRepeat.values.byName(values['recurrence']!),
      seriesId: (values['series'] ?? '').isEmpty ? null : values['series'],
      repeatAnchor: DateTime.tryParse(values['repeat_anchor'] ?? ''),
      occurrenceDate: DateTime.tryParse(values['occurrence'] ?? ''),
      originalDate:
          DateTime.tryParse(values['original_scheduled'] ?? '') ?? scheduled,
      reminder: reminder,
    );
  }

  static String _singleLine(String value) =>
      value.replaceAll(RegExp(r'[\r\n]+'), ' ').trimRight();
}

String dateKey(DateTime value) {
  final local = value.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

bool isSameDay(DateTime a, DateTime b) => dateKey(a) == dateKey(b);
