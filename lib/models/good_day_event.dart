import 'dart:convert';

enum EventRepeat { once, daily, weekdays, weekly, monthly }

extension EventRepeatLabel on EventRepeat {
  String get label => switch (this) {
    EventRepeat.once => '仅一次',
    EventRepeat.daily => '每天',
    EventRepeat.weekdays => '工作日（周一至周五）',
    EventRepeat.weekly => '每周',
    EventRepeat.monthly => '每月',
  };
}

class GoodDayEvent {
  const GoodDayEvent({
    required this.id,
    required this.title,
    required this.startsAt,
    this.notes = '',
    this.repeat = EventRepeat.once,
    this.reminderMinutes = 0,
    this.enabled = true,
    this.handledThrough,
    this.pendingOccurrence,
    this.snoozedUntil,
    this.deletedAt,
  });

  final String id, title, notes;
  final DateTime startsAt;
  final EventRepeat repeat;
  final int reminderMinutes;
  final bool enabled;
  final DateTime? handledThrough, pendingOccurrence, snoozedUntil, deletedAt;

  GoodDayEvent edit({
    required String title,
    required String notes,
    required DateTime startsAt,
    required EventRepeat repeat,
    required int reminderMinutes,
    required bool enabled,
  }) {
    final rescheduled =
        startsAt != this.startsAt ||
        repeat != this.repeat ||
        reminderMinutes != this.reminderMinutes;
    return GoodDayEvent(
      id: id,
      title: title.trim(),
      notes: notes.trim(),
      startsAt: startsAt,
      repeat: repeat,
      reminderMinutes: reminderMinutes,
      enabled: enabled,
      handledThrough: rescheduled ? null : handledThrough,
      pendingOccurrence: rescheduled || !enabled ? null : pendingOccurrence,
      snoozedUntil: rescheduled || !enabled ? null : snoozedUntil,
      deletedAt: deletedAt,
    );
  }

  GoodDayEvent pending(DateTime occurrence) => GoodDayEvent(
    id: id,
    title: title,
    notes: notes,
    startsAt: startsAt,
    repeat: repeat,
    reminderMinutes: reminderMinutes,
    enabled: enabled,
    handledThrough: handledThrough,
    pendingOccurrence: occurrence,
    snoozedUntil: occurrence == pendingOccurrence ? snoozedUntil : null,
    deletedAt: deletedAt,
  );

  GoodDayEvent resolve(DateTime occurrence, {DateTime? snoozeUntil}) =>
      GoodDayEvent(
        id: id,
        title: title,
        notes: notes,
        startsAt: startsAt,
        repeat: repeat,
        reminderMinutes: reminderMinutes,
        enabled: snoozeUntil != null || repeat != EventRepeat.once,
        handledThrough: snoozeUntil == null ? occurrence : handledThrough,
        pendingOccurrence: snoozeUntil == null ? null : occurrence,
        snoozedUntil: snoozeUntil,
        deletedAt: deletedAt,
      );

  GoodDayEvent markDeleted(DateTime now) => GoodDayEvent(
    id: id,
    title: title,
    notes: notes,
    startsAt: startsAt,
    repeat: repeat,
    reminderMinutes: reminderMinutes,
    enabled: false,
    handledThrough: handledThrough,
    deletedAt: now,
  );

  // Restoring an event is deliberately paused: restoring old data must not
  // unexpectedly enable an overdue alarm. Its schedule can be enabled in UI.
  GoodDayEvent restore() => GoodDayEvent(
    id: id,
    title: title,
    notes: notes,
    startsAt: startsAt,
    repeat: repeat,
    reminderMinutes: reminderMinutes,
    enabled: false,
    handledThrough: handledThrough,
  );

  DateTime _at(DateTime day, {int? dayOfMonth}) => DateTime(
    day.year,
    day.month,
    dayOfMonth ?? day.day,
    startsAt.hour,
    startsAt.minute,
  );
  DateTime _monthly(int year, int month) {
    final first = DateTime(year, month);
    final lastDay = DateTime(first.year, first.month + 1, 0).day;
    return _at(
      first,
      dayOfMonth: startsAt.day > lastDay ? lastDay : startsAt.day,
    );
  }

  DateTime? latestOccurrenceAtOrBefore(DateTime limit) {
    if (limit.isBefore(startsAt)) return null;
    if (repeat == EventRepeat.once) return startsAt;
    var candidate = _at(limit);
    if (candidate.isAfter(limit)) {
      candidate = _at(DateTime(limit.year, limit.month, limit.day - 1));
    }
    switch (repeat) {
      case EventRepeat.once:
        break;
      case EventRepeat.daily:
        break;
      case EventRepeat.weekdays:
        while (candidate.weekday > DateTime.friday) {
          candidate = _at(
            DateTime(candidate.year, candidate.month, candidate.day - 1),
          );
        }
      case EventRepeat.weekly:
        final days = (candidate.weekday - startsAt.weekday + 7) % 7;
        candidate = _at(
          DateTime(candidate.year, candidate.month, candidate.day - days),
        );
      case EventRepeat.monthly:
        candidate = _monthly(limit.year, limit.month);
        if (candidate.isAfter(limit)) {
          candidate = _monthly(limit.year, limit.month - 1);
        }
    }
    return candidate.isBefore(startsAt) ? null : candidate;
  }

  DateTime? nextOccurrenceAfter(DateTime boundary) {
    if (repeat == EventRepeat.once) {
      return startsAt.isAfter(boundary) ? startsAt : null;
    }
    final floor = boundary.isBefore(startsAt) ? startsAt : boundary;
    var candidate = _at(floor);
    switch (repeat) {
      case EventRepeat.once:
        break;
      case EventRepeat.daily:
      case EventRepeat.weekdays:
        if (!candidate.isAfter(boundary)) {
          candidate = _at(DateTime(floor.year, floor.month, floor.day + 1));
        }
        if (repeat == EventRepeat.weekdays) {
          while (candidate.weekday > DateTime.friday) {
            candidate = _at(
              DateTime(candidate.year, candidate.month, candidate.day + 1),
            );
          }
        }
      case EventRepeat.weekly:
        final days = (startsAt.weekday - candidate.weekday + 7) % 7;
        candidate = _at(
          DateTime(candidate.year, candidate.month, candidate.day + days),
        );
        if (!candidate.isAfter(boundary)) {
          candidate = _at(
            DateTime(candidate.year, candidate.month, candidate.day + 7),
          );
        }
      case EventRepeat.monthly:
        candidate = _monthly(floor.year, floor.month);
        if (candidate.isBefore(startsAt) || !candidate.isAfter(boundary)) {
          candidate = _monthly(floor.year, floor.month + 1);
        }
    }
    return candidate;
  }

  DateTime? dueOccurrence(DateTime now) {
    if (!enabled || deletedAt != null) return null;
    if (snoozedUntil != null && pendingOccurrence != null) {
      return now.isBefore(snoozedUntil!) ? null : pendingOccurrence;
    }
    // One latest missed occurrence, not a flood of every missed day.
    final latest = latestOccurrenceAtOrBefore(
      now.add(Duration(minutes: reminderMinutes)),
    );
    if (latest == null ||
        (handledThrough != null && !latest.isAfter(handledThrough!))) {
      return null;
    }
    return latest;
  }

  DateTime? nextReminderAt(DateTime now) {
    if (!enabled || deletedAt != null) return null;
    if (snoozedUntil != null) return snoozedUntil;
    final due = dueOccurrence(now);
    if (due != null) return due.subtract(Duration(minutes: reminderMinutes));
    final boundary = now.add(Duration(minutes: reminderMinutes));
    final after = handledThrough != null && handledThrough!.isAfter(boundary)
        ? handledThrough!
        : boundary;
    return nextOccurrenceAfter(after)
        ?.subtract(Duration(minutes: reminderMinutes));
  }

  String toMarkdown() =>
      '---\ngoodday-event: ${jsonEncode({'id': id, 'title': title, 'notes': notes, 'startsAt': startsAt.toIso8601String(), 'repeat': repeat.name, 'reminderMinutes': reminderMinutes, 'enabled': enabled, 'handledThrough': handledThrough?.toIso8601String(), 'pendingOccurrence': pendingOccurrence?.toIso8601String(), 'snoozedUntil': snoozedUntil?.toIso8601String(), 'deletedAt': deletedAt?.toIso8601String()})}\n---\n\n# ${title.replaceAll(RegExp(r'[\r\n]+'), ' ')}\n\n$notes\n';

  factory GoodDayEvent.fromMarkdown(String source) {
    try {
      final lines = source.split(RegExp(r'\r?\n'));
      if (lines.length < 3 ||
          lines.first != '---' ||
          lines[2] != '---' ||
          !lines[1].startsWith('goodday-event: ')) {
        throw const FormatException('事件格式无效');
      }
      final json = jsonDecode(
        lines[1].substring('goodday-event: '.length),
      ) as Map<String, dynamic>;
      DateTime? optionalDate(String key) => json[key] == null
          ? null
          : DateTime.parse(json[key] as String).toLocal();
      final id = json['id'] as String;
      final title = json['title'] as String;
      final minutes = json['reminderMinutes'] as int;
      if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id) ||
          title.trim().isEmpty ||
          minutes < 0 ||
          minutes > 10080) {
        throw const FormatException('事件内容无效');
      }
      final pending = optionalDate('pendingOccurrence');
      final snoozed = optionalDate('snoozedUntil');
      if (snoozed != null && pending == null) {
        throw const FormatException('稍后提醒缺少事件时间');
      }
      return GoodDayEvent(
        id: id,
        title: title,
        notes: json['notes'] as String,
        startsAt: DateTime.parse(json['startsAt'] as String).toLocal(),
        repeat: EventRepeat.values.byName(json['repeat'] as String),
        reminderMinutes: minutes,
        enabled: json['enabled'] as bool,
        handledThrough: optionalDate('handledThrough'),
        pendingOccurrence: pending,
        snoozedUntil: snoozed,
        deletedAt: optionalDate('deletedAt'),
      );
    } on Object catch (error) {
      throw FormatException('无法读取待办事件：$error');
    }
  }
}

String eventDateTimeLabel(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
