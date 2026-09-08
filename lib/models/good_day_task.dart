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
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime scheduledDate;
  final bool isCompleted;
  final DateTime? completedAt;
  final DateTime? deletedAt;
  final String notes;

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
        ..writeln(notes.trimRight());
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

    var notesStart = titleIndex + 1;
    while (notesStart < lines.length && lines[notesStart].trim().isEmpty) {
      notesStart++;
    }

    return GoodDayTask(
      id: id,
      title: lines[titleIndex].substring(2).trim(),
      createdAt: created,
      scheduledDate: scheduled,
      isCompleted: values['status'] == 'done',
      completedAt: DateTime.tryParse(values['completed'] ?? ''),
      deletedAt: DateTime.tryParse(values['deleted'] ?? ''),
      notes: notesStart < lines.length
          ? lines.sublist(notesStart).join('\n').trimRight()
          : '',
    );
  }
}

String dateKey(DateTime value) {
  final local = value.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

bool isSameDay(DateTime a, DateTime b) => dateKey(a) == dateKey(b);
