import 'dart:convert';

import 'repeat_schedule.dart';
export 'repeat_schedule.dart';

class GoodDayEvent {
  const GoodDayEvent({
    required this.id,
    required this.title,
    required this.startsAt,
    this.notes = '',
    this.repeat = EventRepeat.once,
    this.reminderMinutes = 0,
    this.intervalMinutes = 0,
    this.expiresAt,
    this.calendarAnchor,
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
  final int intervalMinutes;
  final DateTime? expiresAt;
  final DateTime? calendarAnchor;
  final bool enabled;
  final DateTime? handledThrough, pendingOccurrence, snoozedUntil, deletedAt;

  GoodDayEvent edit({
    required String title,
    required String notes,
    required DateTime startsAt,
    required EventRepeat repeat,
    required int reminderMinutes,
    required bool enabled,
    int? intervalMinutes,
    DateTime? expiresAt,
  }) {
    final nextInterval = intervalMinutes ?? this.intervalMinutes;
    final nextExpiry = expiresAt ?? this.expiresAt;
    final rescheduled =
        startsAt != this.startsAt ||
        repeat != this.repeat ||
        reminderMinutes != this.reminderMinutes ||
        nextInterval != this.intervalMinutes ||
        nextExpiry != this.expiresAt;
    return GoodDayEvent(
      id: id,
      title: title.trim(),
      notes: notes.trim(),
      startsAt: startsAt,
      repeat: repeat,
      reminderMinutes: reminderMinutes,
      intervalMinutes: nextInterval,
      expiresAt: nextExpiry,
      calendarAnchor: calendarAnchor,
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
    intervalMinutes: intervalMinutes,
    expiresAt: expiresAt,
    calendarAnchor: calendarAnchor,
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
        intervalMinutes: intervalMinutes,
        expiresAt: expiresAt,
        calendarAnchor: calendarAnchor,
        enabled:
            (snoozeUntil != null ||
                repeat != EventRepeat.once ||
                intervalMinutes > 0) &&
            (expiresAt == null ||
                (snoozeUntil ??
                        occurrence.add(Duration(minutes: intervalMinutes)))
                    .isBefore(expiresAt!)),
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
    intervalMinutes: intervalMinutes,
    expiresAt: expiresAt,
    calendarAnchor: calendarAnchor,
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
    intervalMinutes: intervalMinutes,
    expiresAt: expiresAt,
    calendarAnchor: calendarAnchor,
    enabled: false,
    handledThrough: handledThrough,
  );

  DateTime? latestOccurrenceAtOrBefore(DateTime limit) {
    if (intervalMinutes == 0) {
      return RepeatSchedule(startsAt, repeat).latestOccurrenceAtOrBefore(limit);
    }
    if (limit.isBefore(startsAt)) return null;
    final capped = expiresAt != null && !limit.isBefore(expiresAt!)
        ? expiresAt!.subtract(const Duration(microseconds: 1))
        : limit;
    if (capped.isBefore(startsAt)) return null;
    return startsAt.add(
      Duration(
        minutes:
            (capped.difference(startsAt).inMinutes ~/ intervalMinutes) *
            intervalMinutes,
      ),
    );
  }

  DateTime? nextOccurrenceAfter(DateTime boundary) {
    final next = intervalMinutes == 0
        ? RepeatSchedule(startsAt, repeat).nextOccurrenceAfter(boundary)
        : boundary.isBefore(startsAt)
        ? startsAt
        : startsAt.add(
            Duration(
              minutes:
                  (boundary.difference(startsAt).inMinutes ~/ intervalMinutes +
                      1) *
                  intervalMinutes,
            ),
          );
    return next != null && (expiresAt == null || next.isBefore(expiresAt!))
        ? next
        : null;
  }

  DateTime? dueOccurrence(DateTime now) {
    if (!enabled ||
        deletedAt != null ||
        (expiresAt != null && !now.isBefore(expiresAt!))) {
      return null;
    }
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
    if (!enabled ||
        deletedAt != null ||
        (expiresAt != null && !now.isBefore(expiresAt!))) {
      return null;
    }
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
      '---\ngoodday-event: ${jsonEncode({'id': id, 'title': title, 'notes': notes, 'startsAt': startsAt.toIso8601String(), 'repeat': repeat.name, 'reminderMinutes': reminderMinutes, 'intervalMinutes': intervalMinutes, 'expiresAt': expiresAt?.toIso8601String(), 'calendarAnchor': calendarAnchor?.toIso8601String(), 'enabled': enabled, 'handledThrough': handledThrough?.toIso8601String(), 'pendingOccurrence': pendingOccurrence?.toIso8601String(), 'snoozedUntil': snoozedUntil?.toIso8601String(), 'deletedAt': deletedAt?.toIso8601String()})}\n---\n\n# ${title.replaceAll(RegExp(r'[\r\n]+'), ' ')}\n\n$notes\n';

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
      final interval = (json['intervalMinutes'] ?? 0) as int;
      final expiry = optionalDate('expiresAt');
      if (interval < 0 ||
          interval >= 527040 ||
          (interval > 0 &&
              (expiry == null ||
                  !expiry.isAfter(DateTime.parse(json['startsAt'] as String)) ||
                  json['repeat'] != 'once'))) {
        throw const FormatException('重复提醒设置无效');
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
        intervalMinutes: interval,
        expiresAt: expiry,
        calendarAnchor: optionalDate('calendarAnchor'),
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
