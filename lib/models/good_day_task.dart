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

  GoodDayTask setCompleted(bool completed, DateTime now) {
    return GoodDayTask(
      id: id,
      title: title,
      createdAt: createdAt,
      scheduledDate: scheduledDate,
      isCompleted: completed,
      completedAt: completed ? now : null,
      deletedAt: deletedAt,
      notes: notes,
      subtasks: subtasks,
    );
  }

  GoodDayTask rollForward(DateTime date) {
    return GoodDayTask(
      id: id,
      title: title,
      createdAt: createdAt,
      scheduledDate: date,
      isCompleted: isCompleted,
      completedAt: completedAt,
      deletedAt: deletedAt,
      notes: notes,
      subtasks: subtasks,
    );
  }

  GoodDayTask markDeleted(DateTime now) {
    return GoodDayTask(
      id: id,
      title: title,
      createdAt: createdAt,
      scheduledDate: scheduledDate,
      isCompleted: isCompleted,
      completedAt: completedAt,
      deletedAt: now,
      notes: notes,
      subtasks: subtasks,
    );
  }

  GoodDayTask updateDetails({required String title, required String notes}) {
    return GoodDayTask(
      id: id,
      title: title.trim(),
      createdAt: createdAt,
      scheduledDate: scheduledDate,
      isCompleted: isCompleted,
      completedAt: completedAt,
      deletedAt: deletedAt,
      notes: _singleLine(notes),
      subtasks: subtasks,
    );
  }

  GoodDayTask addSubtask(GoodDaySubtask subtask) {
    return _withSubtasks([...subtasks, subtask]);
  }

  GoodDayTask updateSubtask(
    String subtaskId, {
    String? title,
    bool? isCompleted,
  }) {
    return _withSubtasks([
      for (final subtask in subtasks)
        if (subtask.id == subtaskId)
          subtask.copyWith(
            title: title == null ? null : _singleLine(title).trim(),
            isCompleted: isCompleted,
          )
        else
          subtask,
    ]);
  }

  GoodDayTask removeSubtask(String subtaskId) {
    return _withSubtasks(
      subtasks.where((subtask) => subtask.id != subtaskId).toList(),
    );
  }

  GoodDayTask _withSubtasks(List<GoodDaySubtask> nextSubtasks) {
    return GoodDayTask(
      id: id,
      title: title,
      createdAt: createdAt,
      scheduledDate: scheduledDate,
      isCompleted: isCompleted,
      completedAt: completedAt,
      deletedAt: deletedAt,
      notes: notes,
      subtasks: List.unmodifiable(nextSubtasks),
    );
  }

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
      ..writeln('completed: ${completedAt?.toIso8601String() ?? ''}')
      ..writeln('deleted: ${deletedAt?.toIso8601String() ?? ''}')
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

    return GoodDayTask(
      id: id,
      title: lines[titleIndex].substring(2).trim(),
      createdAt: created,
      scheduledDate: scheduled,
      isCompleted: values['status'] == 'done',
      completedAt: DateTime.tryParse(values['completed'] ?? ''),
      deletedAt: DateTime.tryParse(values['deleted'] ?? ''),
      notes: notes,
      subtasks: List.unmodifiable(subtasks),
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
