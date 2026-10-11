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

class RepeatSchedule {
  const RepeatSchedule(this.startsAt, this.repeat);
  final DateTime startsAt;
  final EventRepeat repeat;

  DateTime _at(DateTime day, {int? dayOfMonth}) => DateTime(
    day.year,
    day.month,
    dayOfMonth ?? day.day,
    startsAt.hour,
    startsAt.minute,
  );
  DateTime _monthly(int year, int month) {
    final first = DateTime(year, month);
    final last = DateTime(first.year, first.month + 1, 0).day;
    return _at(first, dayOfMonth: startsAt.day > last ? last : startsAt.day);
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
        candidate = _at(
          DateTime(
            candidate.year,
            candidate.month,
            candidate.day - (candidate.weekday - startsAt.weekday + 7) % 7,
          ),
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
        candidate = _at(
          DateTime(
            candidate.year,
            candidate.month,
            candidate.day + (startsAt.weekday - candidate.weekday + 7) % 7,
          ),
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
}
