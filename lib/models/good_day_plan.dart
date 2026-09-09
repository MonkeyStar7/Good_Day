class GoodDayPlan {
  const GoodDayPlan({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.deadline,
    this.goalId,
    this.isCompleted = false,
    this.completedAt,
    this.notes = '',
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime deadline;
  final String? goalId;
  final bool isCompleted;
  final DateTime? completedAt;
  final String notes;

  GoodDayPlan setCompleted(bool completed, DateTime now) {
    return copyWith(
      isCompleted: completed,
      completedAt: completed ? now : null,
      clearCompletedAt: !completed,
    );
  }

  GoodDayPlan update({
    String? title,
    DateTime? deadline,
    String? goalId,
    bool clearGoal = false,
    String? notes,
  }) {
    return copyWith(
      title: title == null ? null : _singleLine(title).trim(),
      deadline: deadline,
      goalId: goalId,
      clearGoal: clearGoal,
      notes: notes == null ? null : _singleLine(notes).trim(),
    );
  }

  GoodDayPlan copyWith({
    String? title,
    DateTime? deadline,
    String? goalId,
    bool clearGoal = false,
    bool? isCompleted,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    String? notes,
  }) {
    return GoodDayPlan(
      id: id,
      title: title ?? this.title,
      createdAt: createdAt,
      deadline: deadline ?? this.deadline,
      goalId: clearGoal ? null : goalId ?? this.goalId,
      isCompleted: isCompleted ?? this.isCompleted,
      completedAt: clearCompletedAt ? null : completedAt ?? this.completedAt,
      notes: notes ?? this.notes,
    );
  }

  double remainingFraction(DateTime now) {
    final end = deadlineEnd;
    final total = end.difference(createdAt).inMilliseconds;
    if (total <= 0) return now.isBefore(end) ? 1 : 0;
    final remaining = end.difference(now).inMilliseconds;
    return (remaining / total).clamp(0.0, 1.0);
  }

  DateTime get deadlineEnd =>
      DateTime(deadline.year, deadline.month, deadline.day, 23, 59, 59, 999);

  int remainingDays(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final deadlineDay = DateTime(deadline.year, deadline.month, deadline.day);
    return deadlineDay.difference(today).inDays;
  }

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('---')
      ..writeln('id: $id')
      ..writeln('status: ${isCompleted ? 'done' : 'active'}')
      ..writeln('created: ${createdAt.toIso8601String()}')
      ..writeln('deadline: ${_dateKey(deadline)}')
      ..writeln('completed: ${completedAt?.toIso8601String() ?? ''}')
      ..writeln('goal: ${goalId ?? ''}')
      ..writeln('---')
      ..writeln()
      ..writeln('# ${_singleLine(title).trim()}');
    if (notes.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('> ${_singleLine(notes).trim()}');
    }
    return buffer.toString();
  }

  factory GoodDayPlan.fromMarkdown(String source) {
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
    final id = values['id'];
    final created = DateTime.tryParse(values['created'] ?? '');
    final deadline = DateTime.tryParse(values['deadline'] ?? '');
    if (titleIndex == -1 ||
        id == null ||
        id.isEmpty ||
        created == null ||
        deadline == null) {
      throw const FormatException('Invalid plan metadata.');
    }
    final notes = lines
        .sublist(titleIndex + 1)
        .where((line) => line.trim().isNotEmpty)
        .map((line) => line.startsWith('> ') ? line.substring(2) : line)
        .join(' ')
        .trim();
    final goal = values['goal']?.trim();
    return GoodDayPlan(
      id: id,
      title: lines[titleIndex].substring(2).trim(),
      createdAt: created,
      deadline: deadline,
      goalId: goal == null || goal.isEmpty ? null : goal,
      isCompleted: values['status'] == 'done',
      completedAt: DateTime.tryParse(values['completed'] ?? ''),
      notes: notes,
    );
  }
}

String _dateKey(DateTime value) {
  final local = value.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

String _singleLine(String value) =>
    value.replaceAll(RegExp(r'[\r\n]+'), ' ').trimRight();
